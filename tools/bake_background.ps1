<#
.SYNOPSIS
    Bakes every per-mode background PNG the game draws, from its source art.

.DESCRIPTION
    The game draws the baked copy, not the original — Main.gd's custom-draw
    setup has no shader pass, so anything that is not a flat colour multiply
    has to be in the file (see MODE_BG_TEXTURE_PATH and
    MODE_BG_NEAR_TEXTURE_PATH). Run this whenever a mode's background art is
    added or replaced.

    $ModeBackgrounds names every file the game loads, one row per file,
    because a mode is not always one image: SKY, JUNGLE and OCEAN are
    far/near parallax pairs and only DREAM is still single.

    FAR and NEAR are graded to opposite ends, and the reason is aerial
    perspective rather than focus. Distance does not just soften an outline,
    it washes the colour out and floods it with whatever the air between
    here and there is made of. So a far layer is desaturated, flattened in
    contrast and blended into a fog drawn from its own palette, with only a
    light blur helping; a near layer keeps every outline it arrived with and
    is pulled back on presence instead — a small desaturation, an evened-out
    value range, and an alpha the game applies at draw time.

    The pipeline per file, in order:

      1. Gaussian blur (Sigma; CutOut rows premultiply first — see below)
      2. Saturation toward luma (Sat)
      3. Contrast about the layer's own mean luma (Contrast), so flattening
         the range does not also shift how bright the layer reads
      4. Fog: blend toward lerp(layer's own mean colour, white, FogLighten)
         by Fog. Self-derived, so JUNGLE hazes to misty green and OCEAN to
         misty blue without a palette being hand-picked per mode
      5. Soft ceilings on saturation and value (SatCap/ValCap), knee'd rather
         than clamped so the brightest coral compresses instead of flattening
         into a posterised band

    CutOut is the difference between a full-bleed painting and a near layer
    with transparency. An opaque background can be blurred on RGB alone —
    there is no edge in the alpha to soften. A cut-out cannot: blurring
    colour and alpha separately drags the transparent pixels' colour into
    the silhouette as a dark fringe. CutOut rows premultiply, blur all four
    channels, then divide alpha back out.

    The ceilings exist so the backdrop never out-shouts what is played
    against it. They are set from the art: -Foreground measures each mode's
    character and gate ring, and tools/check_bg_layers.gd fails the build if
    a background's 99th-percentile saturation or value ever reaches its
    mode's foreground. See $SatCap/$ValCap for the numbers.

    Sharpness (-Sharpness) is the mean |Laplacian| over RGB sampled only
    where the pixel is fully opaque, measured after resampling to the height
    the game draws the layer at. Screen space is the only space worth
    comparing in, and it stopped being the same as source space once SKY's
    far layer arrived at 1472x704 while everything else is 2208x1056. It
    tracks contrast as well as blur, so grading a far layer down shows up
    here too.

    The metric is a proxy, not a verdict. It averages over the whole image,
    so a painting that is mostly flat with a few hard-outlined structures
    scores softer than it looks — see OCEAN's far layer.

    Use -SelfTest to re-derive every row and diff against what is committed;
    anything but a near-zero residual means the table and the files have
    drifted apart. It also prints each pair's far/near sharpness margin.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/bake_background.ps1 -Mode jungle

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/bake_background.ps1 -SelfTest

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/bake_background.ps1 -Sharpness

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/bake_background.ps1 -Foreground
#>
param(
    [string]$Mode,
    [switch]$SelfTest,
    [switch]$Sharpness,
    [switch]$Foreground,
    [double]$Sigma = 0    # 0 = use the per-file value in $ModeBackgrounds below
)

$ErrorActionPreference = 'Stop'

$csharp = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

public static class BgBake {
    static double[] Kernel(double sigma, out int radius) {
        radius = (int)Math.Ceiling(sigma * 3.0);
        double[] k = new double[2 * radius + 1];
        double sum = 0;
        for (int i = -radius; i <= radius; i++) { k[i + radius] = Math.Exp(-(i * i) / (2.0 * sigma * sigma)); sum += k[i + radius]; }
        for (int i = 0; i < k.Length; i++) k[i] /= sum;
        return k;
    }

    // Rec. 601 luma. Used as the grey a colour desaturates toward and as the
    // brightness contrast pivots about.
    static double Luma(double r, double g, double b) { return 0.299 * r + 0.587 * g + 0.114 * b; }

    // Below the knee nothing moves; above it, [knee, 1] is squeezed into
    // [knee, cap]. A hard clamp would drive every bright pixel to exactly
    // the cap and posterise the coral into a flat band.
    static double SoftCap(double v, double cap) {
        if (cap >= 1.0) return v;
        double knee = cap * 0.75;
        if (v <= knee) return v;
        return knee + (v - knee) * (cap - knee) / (1.0 - knee);
    }

    public static void Run(string inPath, string outPath, double sigma, bool premultiply,
                           double sat, double contrast, double fog, double fogLighten,
                           double satCap, double valCap) {
        Bitmap src = (Bitmap)Bitmap.FromFile(inPath);
        int w = src.Width, h = src.Height;
        BitmapData d = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        byte[] buf = new byte[d.Stride * h];
        Marshal.Copy(d.Scan0, buf, 0, buf.Length);
        int stride = d.Stride;
        src.UnlockBits(d);
        src.Dispose();

        // ---- 1. blur ----
        // premultiply=false: alpha carried through untouched and only RGB
        // blurred, correct for a full-bleed background with no alpha edge.
        // premultiply=true: RGB scaled by alpha first, all four channels
        // blurred, then RGB divided back out — required for a cut-out, or
        // the black stored in its transparent pixels bleeds inward as a
        // dark fringe around the silhouette.
        float[][] blurred = new float[4][];
        if (sigma > 0.0) {
            int r;
            double[] k = Kernel(sigma, out r);
            int channels = premultiply ? 4 : 3;
            float[] plane = new float[w * h];
            float[] tmp = new float[w * h];
            for (int c = 0; c < channels; c++) {
                for (int y = 0; y < h; y++)
                    for (int x = 0; x < w; x++) {
                        float v = buf[y * stride + x * 4 + c];
                        if (premultiply && c < 3) v = v * buf[y * stride + x * 4 + 3] / 255f;
                        plane[y * w + x] = v;
                    }
                for (int y = 0; y < h; y++)
                    for (int x = 0; x < w; x++) {
                        double s = 0;
                        for (int i = -r; i <= r; i++) { int xx = Math.Min(w - 1, Math.Max(0, x + i)); s += plane[y * w + xx] * k[i + r]; }
                        tmp[y * w + x] = (float)s;
                    }
                float[] res = new float[w * h];
                for (int y = 0; y < h; y++)
                    for (int x = 0; x < w; x++) {
                        double s = 0;
                        for (int i = -r; i <= r; i++) { int yy = Math.Min(h - 1, Math.Max(0, y + i)); s += tmp[yy * w + x] * k[i + r]; }
                        res[y * w + x] = (float)s;
                    }
                blurred[c] = res;
            }
        }

        // Working buffer in 0..1, alpha kept separately.
        double[] R = new double[w * h], G = new double[w * h], B = new double[w * h], A = new double[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int i = y * w + x;
                double a;
                if (sigma > 0.0 && premultiply) a = blurred[3][i];
                else a = buf[y * stride + x * 4 + 3];
                double[] ch = new double[3];
                for (int c = 0; c < 3; c++) {
                    double v = (sigma > 0.0) ? blurred[c][i] : buf[y * stride + x * 4 + c];
                    // Under half a level of alpha the un-premultiply divides
                    // by ~nothing and amplifies rounding noise into stray
                    // bright pixels; that pixel is invisible anyway.
                    if (sigma > 0.0 && premultiply) v = (a > 0.5) ? v * 255.0 / a : 0.0;
                    ch[c] = Math.Max(0.0, Math.Min(255.0, v)) / 255.0;
                }
                B[i] = ch[0]; G[i] = ch[1]; R[i] = ch[2];
                A[i] = a / 255.0;
            }

        // ---- mean luma and mean colour, over the pixels that actually show ----
        double mR = 0, mG = 0, mB = 0, mL = 0, wsum = 0;
        for (int i = 0; i < w * h; i++) {
            if (A[i] < 0.5) continue;
            mR += R[i]; mG += G[i]; mB += B[i]; mL += Luma(R[i], G[i], B[i]); wsum += 1.0;
        }
        if (wsum > 0) { mR /= wsum; mG /= wsum; mB /= wsum; mL /= wsum; } else { mL = 0.5; }
        double fR = mR + (1.0 - mR) * fogLighten;
        double fG = mG + (1.0 - mG) * fogLighten;
        double fB = mB + (1.0 - mB) * fogLighten;

        byte[] outBuf = (byte[])buf.Clone();
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int i = y * w + x;
                double r = R[i], g = G[i], b = B[i];

                // ---- 2. saturation ----
                if (sat != 1.0) {
                    double l = Luma(r, g, b);
                    r = l + (r - l) * sat; g = l + (g - l) * sat; b = l + (b - l) * sat;
                }
                // ---- 3. contrast, pivoting on the layer's own mean luma ----
                if (contrast != 1.0) {
                    r = mL + (r - mL) * contrast; g = mL + (g - mL) * contrast; b = mL + (b - mL) * contrast;
                }
                // ---- 4. fog ----
                if (fog > 0.0) {
                    r = r + (fR - r) * fog; g = g + (fG - g) * fog; b = b + (fB - b) * fog;
                }
                r = Math.Max(0.0, Math.Min(1.0, r));
                g = Math.Max(0.0, Math.Min(1.0, g));
                b = Math.Max(0.0, Math.Min(1.0, b));

                // ---- 5. soft ceilings, hue preserved ----
                if (satCap < 1.0 || valCap < 1.0) {
                    double V = Math.Max(r, Math.Max(g, b));
                    double m = Math.Min(r, Math.Min(g, b));
                    double C = V - m;
                    double S = (V > 0.0) ? C / V : 0.0;
                    double V2 = SoftCap(V, valCap);
                    double S2 = SoftCap(S, satCap);
                    double C2 = S2 * V2;
                    if (C > 1e-6) {
                        double k = C2 / C;
                        r = V2 - (V - r) * k; g = V2 - (V - g) * k; b = V2 - (V - b) * k;
                    } else { r = V2; g = V2; b = V2; }
                    r = Math.Max(0.0, Math.Min(1.0, r));
                    g = Math.Max(0.0, Math.Min(1.0, g));
                    b = Math.Max(0.0, Math.Min(1.0, b));
                }

                outBuf[y * stride + x * 4 + 0] = (byte)Math.Round(b * 255.0);
                outBuf[y * stride + x * 4 + 1] = (byte)Math.Round(g * 255.0);
                outBuf[y * stride + x * 4 + 2] = (byte)Math.Round(r * 255.0);
                outBuf[y * stride + x * 4 + 3] = (byte)Math.Round(Math.Max(0.0, Math.Min(1.0, A[i])) * 255.0);
            }

        Bitmap dst = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        BitmapData dd = dst.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(outBuf, 0, dd.Scan0, outBuf.Length);
        dst.UnlockBits(dd);
        dst.Save(outPath, ImageFormat.Png);
        dst.Dispose();
    }

    public static double Rmse(string aPath, string bPath) {
        Bitmap a = (Bitmap)Bitmap.FromFile(aPath);
        Bitmap b = (Bitmap)Bitmap.FromFile(bPath);
        if (a.Width != b.Width || a.Height != b.Height) { a.Dispose(); b.Dispose(); return -1; }
        int w = a.Width, h = a.Height;
        BitmapData da = a.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        BitmapData db = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        byte[] ba = new byte[da.Stride * h]; byte[] bb = new byte[db.Stride * h];
        Marshal.Copy(da.Scan0, ba, 0, ba.Length);
        Marshal.Copy(db.Scan0, bb, 0, bb.Length);
        a.UnlockBits(da); b.UnlockBits(db);
        double s = 0; long n = 0;
        // All four channels: a cut-out's blur moves alpha too, so an
        // RGB-only comparison would call a drifted silhouette identical.
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                for (int c = 0; c < 4; c++) {
                    double diff = ba[y * da.Stride + x * 4 + c] - bb[y * db.Stride + x * 4 + c];
                    s += diff * diff; n++;
                }
        a.Dispose(); b.Dispose();
        return Math.Sqrt(s / n);
    }

    // Mean |Laplacian| over RGB, sampled only where the pixel and its four
    // neighbours are all fully opaque. Skipping the soft rim is what lets a
    // cut-out and a full-bleed painting be compared on one scale.
    //
    // Measured after resampling to the height the game draws at, not on the
    // source pixels: the sources are no longer all one size, and SKY's far
    // layer is magnified 1.21x where the 1056-tall ones are minified to
    // 0.81x — a factor of 1.5 in how far the same sigma spreads on screen.
    public static double Sharpness(string path, int viewHeight) {
        Bitmap loaded = (Bitmap)Bitmap.FromFile(path);
        Bitmap b = loaded;
        if (loaded.Height != viewHeight) {
            int sw = (int)Math.Round(loaded.Width * (double)viewHeight / loaded.Height);
            Bitmap scaled = new Bitmap(sw, viewHeight, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(scaled)) {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(loaded, 0, 0, sw, viewHeight);
            }
            loaded.Dispose();
            b = scaled;
        }
        int w = b.Width, h = b.Height;
        BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        byte[] buf = new byte[d.Stride * h];
        Marshal.Copy(d.Scan0, buf, 0, buf.Length);
        int st = d.Stride;
        b.UnlockBits(d); b.Dispose();
        double sum = 0; long n = 0;
        for (int y = 1; y < h - 1; y++)
            for (int x = 1; x < w - 1; x++) {
                if (buf[y * st + x * 4 + 3] != 255) continue;
                if (buf[y * st + (x - 1) * 4 + 3] != 255 || buf[y * st + (x + 1) * 4 + 3] != 255) continue;
                if (buf[(y - 1) * st + x * 4 + 3] != 255 || buf[(y + 1) * st + x * 4 + 3] != 255) continue;
                for (int c = 0; c < 3; c++) {
                    int v = 4 * buf[y * st + x * 4 + c] - buf[y * st + (x - 1) * 4 + c] - buf[y * st + (x + 1) * 4 + c]
                          - buf[(y - 1) * st + x * 4 + c] - buf[(y + 1) * st + x * 4 + c];
                    sum += Math.Abs(v); n++;
                }
            }
        return n == 0 ? 0 : sum / n;
    }

    // Saturation and value percentiles over mostly-opaque pixels. Returns
    // s50, s90, s99, v50, v90, v99. Percentiles rather than a raw max: one
    // stray pixel must not set the bar a whole background is held under.
    public static double[] Levels(string[] paths) {
        List<byte> sats = new List<byte>();
        List<byte> vals = new List<byte>();
        foreach (string path in paths) {
            Bitmap b = (Bitmap)Bitmap.FromFile(path);
            int w = b.Width, h = b.Height;
            BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            byte[] buf = new byte[d.Stride * h];
            Marshal.Copy(d.Scan0, buf, 0, buf.Length);
            int st = d.Stride;
            b.UnlockBits(d); b.Dispose();
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                    if (buf[y * st + x * 4 + 3] < 200) continue;
                    int bl = buf[y * st + x * 4 + 0], g = buf[y * st + x * 4 + 1], r = buf[y * st + x * 4 + 2];
                    int max = Math.Max(r, Math.Max(g, bl));
                    int min = Math.Min(r, Math.Min(g, bl));
                    sats.Add((byte)((max == 0) ? 0 : (int)Math.Round(255.0 * (max - min) / max)));
                    vals.Add((byte)max);
                }
        }
        if (sats.Count == 0) return new double[] { 0, 0, 0, 0, 0, 0 };
        sats.Sort(); vals.Sort();
        return new double[] {
            Pct(sats, 0.50), Pct(sats, 0.90), Pct(sats, 0.99),
            Pct(vals, 0.50), Pct(vals, 0.90), Pct(vals, 0.99)
        };
    }

    static double Pct(List<byte> l, double p) {
        int i = (int)Math.Round(p * (l.Count - 1));
        if (i < 0) i = 0;
        if (i > l.Count - 1) i = l.Count - 1;
        return l[i] / 255.0;
    }
}
"@
Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing

# The height _draw_bg_layer scales every layer to fill (project.godot
# window/size/viewport_height). Sharpness is measured after resampling to
# it, so sources of different resolutions stay comparable.
$ViewHeight = 854

$repo = Split-Path -Parent $PSScriptRoot
$assets = [System.IO.Path]::Combine($repo, 'assets')
$bgRoot = [System.IO.Path]::Combine($assets, 'backgrounds')

# ---- Ceilings ----
#
# The backdrop must never out-shout what is played against it, so no
# background pixel may reach the saturation or brightness the character and
# gate ring live at. Measured with -Foreground, at the 90th percentile: the
# weakest foreground saturation of the four modes is DREAM's 0.81 and the
# weakest value is JUNGLE's 0.92, so 0.72 and 0.85 clear the tightest mode
# in each axis rather than only the loud ones.
#
# Applied to far and near alike — it is the same backdrop — though after
# the fog treatment a far layer is nowhere near them.
#
# tools/check_bg_layers.gd fails if a committed background's 99th-percentile
# saturation or value ever reaches its own mode's foreground.
$SatCap = 0.72
$ValCap = 0.85

# ---- Near layers ----
#
# Shared across modes, because a near layer is meant to keep whatever
# crispness and colour its own painting arrived with; matching them to
# common numbers is what would flatten one mode's art to fit another's.
#
# Sigma is edge treatment, not softening: the near layer is supposed to stay
# sharp, and 0.5 is the lightest setting that does anything at all (the
# kernel runs to ceil(3*sigma), so by 0.3 it has collapsed to a near-delta
# and every layer measures its raw sharpness back). What it buys is a cut-out
# whose silhouette does not sit on the far layer as a hard aliased line.
#
# Presence comes off through colour instead — 0.83 saturation is the 17% cut
# the spec asks for, and 0.86 contrast evens the value range so the layer
# stops having bright spots that catch the eye. The rest is alpha, which the
# game applies at draw time (bg_near_alpha in Main.gd) rather than being
# baked, since a plain modulate needs no shader.
$NearSigma = 0.5
$NearSat = 0.83
$NearContrast = 0.86

# ---- Far layers ----
#
# Aerial perspective, not defocus. The blur is deliberately light — this is
# the "1-2px" assist, down from the 1.6-2.4 these layers used to carry — and
# the recession is done by colour: saturation halved, contrast pulled in
# hard, and a third of the way blended into a fog mixed from the painting's
# own mean colour lightened toward white. Deriving the fog from the art is
# what lets one setting suit all four: JUNGLE hazes to misty green, OCEAN to
# misty blue, SKY to pale sky.
#
# Sigma stays per-mode because the paintings are not equally busy — JUNGLE's
# uniformly dense foliage has no flat areas to go quiet, and needs more to
# reach the same place than SKY's does.
$FarSat = 0.50
$FarContrast = 0.70
$FarFog = 0.32
$FarFogLighten = 0.45

$ModeBackgrounds = @{
    sky = @(
        # The one source that is not 2208x1056. At 1472x704 it is *magnified*
        # 1.21x to fill the view, where every other layer is minified to
        # 0.81x — a factor of 1.5 in how far the same sigma spreads on
        # screen, which is exactly why Sharpness measures after resampling.
        #
        # The grading does not buy separation from the stone arches, which
        # share the SKY gate's white-and-gold-with-a-blue-gem look. Washing
        # the colour out of them helps more than blur ever did, but an arch
        # this size still reads as an arch. That is a shape problem and the
        # fix is in the art.
        @{ File = 'background_far';  Sigma = 1.0; Kind = 'far'
           Sat = 0.55; Contrast = 0.78; Fog = 0.18 }
        # Clouds, and only over the bottom half of the screen (0% coverage
        # above y=512 of 854, ~65% below). Softest raw near layer of the
        # three, and the pair whose far/near margin is thinnest — clouds have
        # no more crispness to give, so SKY's separation has to be bought on
        # the far layer's side.
        @{ File = 'background_near'; Sigma = $NearSigma; Kind = 'near' }
    )
    jungle = @(
        # Biggest far sigma of the three and it buys the least: uniformly
        # busy foliage has no flat areas to go quiet, so it takes 1.4 to
        # reach where SKY gets on 1.0. The number is what the art costs, not
        # a judgement that this painting needed more.
        @{ File = 'background_far';  Sigma = 1.4; Kind = 'far' }
        # Busiest near layer of the three (raw 6.76), and the one that sits
        # most heavily over the play area — it covers 28% of the midriff and
        # 79% of the bottom strip. Watch this one first if the foreground
        # ever starts pulling the eye off the gates.
        @{ File = 'background_near'; Sigma = $NearSigma; Kind = 'near' }
    )
    ocean = @(
        # The row where the sharpness metric has to be read with suspicion,
        # and the reason the docstring calls it a proxy: this painting is
        # mostly flat blue water around a few hard-outlined stone ruins, so
        # the flat majority drags the mean down while the arch and the steps
        # stay exactly as crisp to the eye. 1.2 rather than SKY's 1.0 on the
        # strength of the composite, not the figure.
        @{ File = 'background_far';  Sigma = 1.2; Kind = 'far' }
        # Sharpest art in the project: coral and pillar detail put it at
        # 12.48 raw, nearly twice JUNGLE's near layer and five times SKY's.
        # It stays the crispest thing on screen behind the gates — which is
        # the point — and it is the only layer the saturation ceiling
        # actually bites on. Worth a second look in play, as the OCEAN gate
        # ring is coral-decorated too.
        @{ File = 'background_near'; Sigma = $NearSigma; Kind = 'near' }
    )
    dream = @(
        # 근경이 없는 유일한 모드다. 앞에 겹칠 레이어가 없으니 물러날 깊이도
        # 없어서, 원경 등급을 그대로 씌우면 혼자 빈 화면이 된다. 그래서 안개와
        # 채도를 절반만 걸고 블러는 원래의 1.1을 지킨다 — 이 그림은 처음부터
        # 부드러운 파스텔이라 세게 걸면 꽃 모양만 뭉개진다.
        #
        # 이 줄은 예전에 background_single(v1)을 3.5로 가리키고 있었다. 게임이
        # 읽는 건 v2 쪽이라, 자체 테스트는 아무도 쓰지 않는 파일만 초록으로
        # 통과시키고 있었고 v2의 값은 검증된 적이 없었다. 커밋된 v2 블러본에서
        # 되찾은 값이 1.1이다.
        @{ File = 'background_single_v2'; Sigma = 1.1; Kind = 'far'
           Sat = 0.75; Contrast = 0.85; Fog = 0.16 }
    )
}

$ModeOrder = @('sky', 'jungle', 'ocean', 'dream')

# Character and gate ring per mode, index-aligned to $ModeOrder. Mirrors
# MODE_CHARACTER_DIR / MODE_GATE_DIR in Main.gd; -Foreground reads these to
# report what the ceilings are set against.
$ModeForeground = @{
    sky    = @('characters\bird_v2\bird_fly.png',        'gates\gate_ring\gate_ring_left.png',        'gates\gate_ring\gate_ring_right.png')
    jungle = @('characters\dragon_green\dragon_fly.png', 'gates\gate_ring_jungle\gate_ring_left.png', 'gates\gate_ring_jungle\gate_ring_right.png')
    ocean  = @('characters\shark_blue\shark_swim.png',   'gates\gate_ring_ocean\gate_ring_left.png',  'gates\gate_ring_ocean\gate_ring_right.png')
    dream  = @('characters\unicorn_dream\unicorn_run.png', 'gates\gate_ring_dream\gate_ring_left.png', 'gates\gate_ring_dream\gate_ring_right.png')
}

function Get-Rows([string]$name) {
    if (-not $ModeBackgrounds.ContainsKey($name)) { throw "Unknown mode '$name'. Known: $($ModeOrder -join ', ')" }
    return $ModeBackgrounds[$name]
}

function Get-Paths([string]$name, $row) {
    $dir = [System.IO.Path]::Combine($bgRoot, $name + '_world')
    return @{
        In  = [System.IO.Path]::Combine($dir, $row.File + '.png')
        Out = [System.IO.Path]::Combine($dir, $row.File + '_blur.png')
    }
}

# A row's grade: the shared far/near defaults for its Kind, with any
# per-row override winning. Only DREAM overrides anything.
function Get-Grade($row) {
    $near = ($row.Kind -eq 'near')
    $g = @{
        Sigma       = if ($Sigma -gt 0) { $Sigma } else { $row.Sigma }   # explicit -Sigma wins, for trying a value out
        CutOut      = $near
        Sat         = if ($near) { $NearSat } else { $FarSat }
        Contrast    = if ($near) { $NearContrast } else { $FarContrast }
        Fog         = if ($near) { 0.0 } else { $FarFog }
        FogLighten  = $FarFogLighten
        SatCap      = $SatCap
        ValCap      = $ValCap
    }
    foreach ($k in @('Sat', 'Contrast', 'Fog', 'FogLighten', 'SatCap', 'ValCap')) {
        if ($row.ContainsKey($k)) { $g[$k] = $row[$k] }
    }
    return $g
}

function Invoke-Bake($path, $out, $g) {
    [BgBake]::Run($path, $out, $g.Sigma, $g.CutOut, $g.Sat, $g.Contrast, $g.Fog, $g.FogLighten, $g.SatCap, $g.ValCap)
}

if ($Foreground) {
    Write-Host "Foreground levels the background ceilings are set against (SatCap $SatCap, ValCap $ValCap):"
    Write-Host "                    SAT p50/p90/p99        VALUE p50/p90/p99"
    foreach ($m in $ModeOrder) {
        $paths = @()
        foreach ($rel in $ModeForeground[$m]) {
            $p = [System.IO.Path]::Combine($assets, $rel)
            if ([System.IO.File]::Exists($p)) { $paths += $p }
        }
        if ($paths.Count -eq 0) { Write-Host ("  {0,-7} no foreground art found" -f $m); continue }
        $s = [BgBake]::Levels([string[]]$paths)
        Write-Host ("  {0,-7} char+gate  {1,5:N2} {2,5:N2} {3,5:N2}     {4,5:N2} {5,5:N2} {6,5:N2}" -f $m, $s[0], $s[1], $s[2], $s[3], $s[4], $s[5])
        foreach ($row in (Get-Rows $m)) {
            $p = Get-Paths $m $row
            if (-not [System.IO.File]::Exists($p.Out)) { continue }
            $b = [BgBake]::Levels([string[]]@($p.Out))
            Write-Host ("          {0,-10} {1,5:N2} {2,5:N2} {3,5:N2}     {4,5:N2} {5,5:N2} {6,5:N2}" -f $row.Kind, $b[0], $b[1], $b[2], $b[3], $b[4], $b[5])
        }
    }
    return
}

if ($Sharpness) {
    Write-Host "Sharpness of every committed background, measured at the $ViewHeight px height the game draws it."
    Write-Host "(mean |Laplacian| over opaque RGB; 'draw' is how far the source is scaled to get there)"
    foreach ($m in $ModeOrder) {
        foreach ($row in (Get-Rows $m)) {
            $p = Get-Paths $m $row
            if (-not [System.IO.File]::Exists($p.Out)) { continue }
            $img = [System.Drawing.Bitmap]::FromFile($p.Out)
            $srcH = $img.Height
            $img.Dispose()
            Write-Host ("  {0,-7} {1,-22} {2,-5} src {3,5}px  draw {4,5:N2}x  sigma {5,4} -> sharpness {6,6:N3}" -f `
                $m, $row.File, $row.Kind, $srcH, ($ViewHeight / $srcH), $row.Sigma, ([BgBake]::Sharpness($p.Out, $ViewHeight)))
        }
    }
    return
}

if ($SelfTest) {
    # The far/near relationship is the whole look, and nothing else would
    # notice it inverting — the art would just quietly go flat again.
    #
    # Compared on the committed files' measured sharpness, not their sigmas.
    # Sigma is a poor stand-in: the same value leaves OCEAN's near layer many
    # times crisper than SKY's, and JUNGLE's far layer needs more than SKY's
    # to reach the same place. Only the measured result says whether the far
    # layer is actually the softer one.
    foreach ($m in $ModeOrder) {
        $rows = Get-Rows $m
        $farRow  = $rows | Where-Object { $_.Kind -eq 'far' }  | Select-Object -First 1
        $nearRow = $rows | Where-Object { $_.Kind -eq 'near' } | Select-Object -First 1
        if ($null -eq $farRow -or $null -eq $nearRow) { continue }
        $farOut  = (Get-Paths $m $farRow).Out
        $nearOut = (Get-Paths $m $nearRow).Out
        if (-not ([System.IO.File]::Exists($farOut) -and [System.IO.File]::Exists($nearOut))) { continue }
        $farSharp  = [BgBake]::Sharpness($farOut, $ViewHeight)
        $nearSharp = [BgBake]::Sharpness($nearOut, $ViewHeight)
        if ($farSharp -ge $nearSharp) {
            Write-Host ("  WARN  {0}: far layer measures {1:N2} against near {2:N2} — the far layer is supposed to be the softer one, and this pair has gone flat" -f $m, $farSharp, $nearSharp)
        } else {
            Write-Host ("  {0,-7} far {1,5:N2} < near {2,5:N2}   margin {3,5:N2}" -f $m, $farSharp, $nearSharp, ($nearSharp - $farSharp))
        }
    }
    Write-Host ""
    Write-Host "Self-test: re-deriving each committed background and comparing to the file on disk."
    $tmp = [System.IO.Path]::GetTempPath()
    foreach ($m in $ModeOrder) {
        foreach ($row in (Get-Rows $m)) {
            $p = Get-Paths $m $row
            if (-not ([System.IO.File]::Exists($p.In) -and [System.IO.File]::Exists($p.Out))) {
                Write-Host ("  {0,-7} {1,-22} skipped (needs both the source and its baked copy)" -f $m, $row.File)
                continue
            }
            $probe = [System.IO.Path]::Combine($tmp, ('bgbake_{0}_{1}.png' -f $m, $row.File))
            $g = Get-Grade $row
            Invoke-Bake $p.In $probe $g
            $rmse = [BgBake]::Rmse($probe, $p.Out)
            Write-Host ("  {0,-7} {1,-22} sigma {2,4} -> RMSE vs committed: {3:N3} / 255" -f $m, $row.File, $g.Sigma, $rmse)
            [System.IO.File]::Delete($probe)
        }
    }
    return
}

if (-not $Mode) { throw "Pass -Mode <name> (e.g. jungle), -SelfTest, -Sharpness, or -Foreground." }
Write-Host "Baking backgrounds"
foreach ($row in (Get-Rows $Mode)) {
    $p = Get-Paths $Mode $row
    if (-not [System.IO.File]::Exists($p.In)) {
        Write-Host ("  {0,-22} source not found: {1}" -f $row.File, $p.In)
        continue
    }
    $g = Get-Grade $row
    Invoke-Bake $p.In $p.Out $g
    $lv = [BgBake]::Levels([string[]]@($p.Out))
    Write-Host ("  {0,-22} {1,-5} sigma {2,4} sat {3,4} contrast {4,4} fog {5,4} -> sharpness {6,6:N3}  s99 {7,4:N2}  v99 {8,4:N2}" -f `
        $row.File, $row.Kind, $g.Sigma, $g.Sat, $g.Contrast, $g.Fog, ([BgBake]::Sharpness($p.Out, $ViewHeight)), $lv[2], $lv[5])
}
