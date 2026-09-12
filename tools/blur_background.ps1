<#
.SYNOPSIS
    Produces a mode's pre-blurred background PNGs from its source art.

.DESCRIPTION
    The game draws the pre-blurred copy, not the original — there is no
    runtime blur shader in Main.gd's custom-draw setup, so the softness has
    to be baked into the file (see MODE_BG_TEXTURE_PATH and
    MODE_BG_NEAR_TEXTURE_PATH). Run this whenever a mode's background art is
    added or replaced, so its backdrop recedes behind the gate and
    character like the rest.

    $ModeBackgrounds below names every file the game actually loads, two rows
    per mode: all four are far/near parallax pairs now. Each row carries its
    own CutOut flag; far rows carry their own sigma, near rows all share
    $NearSigma.

    Far and near are tuned to opposite ends. A far layer is measured onto a
    common softness; a near layer is barely touched, so it keeps whatever
    crispness its painting arrived with. See $NearSigma for why.

    That holds for three of the four. DREAM's near layer is a pale cloud
    bank whose raw sharpness (0.78) is already below every far layer in the
    project, so no sigma can make its pair order the way the others do —
    see its row. Blur is not the depth cue there; occlusion and the speed
    difference are.

    CutOut is the difference between a full-bleed painting and a near layer
    with transparency. An opaque background can be blurred on RGB alone —
    there is no edge in the alpha to soften. A cut-out cannot: blurring
    colour and alpha separately drags the transparent pixels' colour into
    the silhouette as a dark fringe. CutOut rows premultiply, blur all four
    channels, then divide alpha back out.

    Far-layer strength was not picked by eye. Sharpness here is the mean
    |Laplacian| over RGB sampled only where the pixel is fully opaque,
    measured after resampling to the height the game draws the layer at
    (-Sharpness reports it, with each file's source height and draw scale).
    Screen space is the only space worth comparing in, and it stopped being
    the same as source space once SKY's far layer arrived at 1472x704 while
    everything else is 2208x1056.

    The scale is anchored on art nobody chose by eye. Every mode shipped
    with a single background before it got a pair, and each of those sigmas
    was recovered by re-blurring the source across a range of values and
    finding which one reproduced the committed *_blur.png, with a residual
    around 1/255 — down at PNG quantisation noise. Those recovered numbers
    are what the pairs were then measured against. The single files are all
    gone from the tree now (git has them), so the figures quoted in the
    table comments are the only record of where they sat.

    The metric is a proxy, not a verdict. It averages over the whole image,
    so a painting that is mostly flat with a few hard-outlined structures
    scores softer than it looks — see OCEAN's far layer, the one row where
    that was worth overruling.

    Use -SelfTest to re-derive every row and diff against what is committed;
    anything but a near-zero residual means the table and the files have
    drifted apart.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/blur_background.ps1 -Mode jungle

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/blur_background.ps1 -SelfTest

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/blur_background.ps1 -Sharpness

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/blur_background.ps1 -Mode ocean -Probe -ProbeSigmas "1.0,1.5,2.0,2.5"
#>
param(
    [string]$Mode,
    [switch]$SelfTest,
    [switch]$Sharpness,
    # Report what a range of sigmas WOULD measure for -Mode, writing nothing.
    # The committed sigmas were picked this way; this is how to pick the next
    # one without a round of guess-blur-look-revert.
    [switch]$Probe,
    # Comma-separated, NOT a real array: this script is always run through
    # `powershell -File`, which hands every argument over as a string and
    # binds only the first element of a [double[]]. Passing "0.5,0.9,1.4"
    # and splitting here is what makes -File work.
    [string]$ProbeSigmas = "0.5,1.0,1.5,2.0,2.5,3.0,4.0",
    [double]$Sigma = 0    # 0 = use the per-file value in $ModeBackgrounds below
)

$ErrorActionPreference = 'Stop'

$csharp = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

public static class BgBlur {
    static double[] Kernel(double sigma, out int radius) {
        radius = (int)Math.Ceiling(sigma * 3.0);
        double[] k = new double[2 * radius + 1];
        double sum = 0;
        for (int i = -radius; i <= radius; i++) { k[i + radius] = Math.Exp(-(i * i) / (2.0 * sigma * sigma)); sum += k[i + radius]; }
        for (int i = 0; i < k.Length; i++) k[i] /= sum;
        return k;
    }

    // Separable Gaussian, clamped at the edges.
    //
    // premultiply=false: alpha is carried through untouched and only RGB is
    // blurred. Correct for a full-bleed opaque background, where there is
    // no alpha edge to soften.
    //
    // premultiply=true: RGB is scaled by alpha first, all four channels are
    // blurred, then RGB is divided back out. Required for a cut-out —
    // blurring straight RGB pulls the colour stored in the fully
    // transparent pixels (black here) inward, and it shows up as a dark
    // fringe all around the silhouette.
    public static void Run(string inPath, string outPath, double sigma, bool premultiply) {
        Bitmap src = (Bitmap)Bitmap.FromFile(inPath);
        int w = src.Width, h = src.Height;
        BitmapData d = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        byte[] buf = new byte[d.Stride * h];
        Marshal.Copy(d.Scan0, buf, 0, buf.Length);
        int stride = d.Stride;
        src.UnlockBits(d);
        src.Dispose();

        int r;
        double[] k = Kernel(sigma, out r);
        int channels = premultiply ? 4 : 3;
        float[][] blurred = new float[4][];

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

        byte[] outBuf = (byte[])buf.Clone();
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int i = y * w + x;
                float a = premultiply ? blurred[3][i] : buf[y * stride + x * 4 + 3];
                for (int c = 0; c < 3; c++) {
                    double v = blurred[c][i];
                    // Under half a level of alpha the divide amplifies
                    // rounding noise into stray bright pixels, and that
                    // pixel is invisible anyway.
                    if (premultiply) v = (a > 0.5f) ? v * 255.0 / a : 0.0;
                    int iv = (int)Math.Round(v);
                    outBuf[y * stride + x * 4 + c] = (byte)(iv < 0 ? 0 : (iv > 255 ? 255 : iv));
                }
                if (premultiply) {
                    int ia = (int)Math.Round(a);
                    outBuf[y * stride + x * 4 + 3] = (byte)(ia < 0 ? 0 : (ia > 255 ? 255 : ia));
                }
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
    // cut-out and a full-bleed painting be compared on one scale —
    // otherwise a mostly-transparent layer scores low for having little
    // opaque art rather than for being soft.
    //
    // Measured after resampling to the height the game draws at, not on the
    // source pixels. _draw_bg_layer scales every layer to fill the view, and
    // the sources are no longer all one size: SKY's far layer is 704 tall
    // and gets magnified 1.21x, while the 1056-tall ones are minified to
    // 0.81x. That is a factor of 1.5 between them, so the same sigma does
    // not buy the same softness — and softness on screen is the only thing
    // the player sees.
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
}
"@
Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing

# The height _draw_bg_layer scales every layer to fill (project.godot
# window/size/viewport_height). Sharpness is measured after resampling to
# it, so sources of different resolutions stay comparable.
$ViewHeight = 854

$repo = Split-Path -Parent $PSScriptRoot
$bgRoot = [System.IO.Path]::Combine($repo, 'assets', 'backgrounds')

# Every background file the game loads, keyed by mode. File is the stem —
# the source is <File>.png and the output is <File>_blur.png, which is what
# MODE_BG_TEXTURE_PATH / MODE_BG_NEAR_TEXTURE_PATH point at.
#
# Keep this table in step with what is actually committed. It is the only
# record of how each file was made — the PNGs themselves do not say, so a
# bare re-run is what would otherwise quietly flatten a deliberate value
# back to a shared one.
# Every near layer's sigma, shared rather than per-mode on purpose.
#
# The far layers are blurred and the near layers are only just touched. That
# is depth of field the way a camera does it — the backdrop goes soft, the
# thing near the lens stays sharp — and it is a deliberate reversal of how
# these pairs first shipped, which had the near layer as the *softest* thing
# on screen on the theory that a fast-moving layer over the gate lanes
# needed the most help receding. It looked wrong: blurring the near layer
# hardest flattens the parallax, because softness is the main cue telling
# the eye which layer is further away.
#
# Shared, because the point of a light touch is that each painting keeps its
# own natural crispness. Matching them to a common sharpness the way the far
# layers are matched would mean blurring OCEAN's near layer five times
# harder than SKY's, which is exactly what was just undone.
#
# 0.5 is the lightest value that does anything: the kernel is built out to
# ceil(3*sigma), so at 0.3 it collapses to a near-delta and every near layer
# measures its raw sharpness back, unchanged. Enough to take the alpha edge
# off a cut-out so its silhouette does not sit on the far layer as a hard
# line.
#
# It is the FLOOR now, not the shared value it used to be. Holding every
# near layer at 0.5 kept each painting's own crispness, and that turned out
# to mean keeping wildly different amounts of it — 2.33 for SKY against
# 10.73 for OCEAN, because the OCEAN art is intrinsically five times
# busier. The foreground did start pulling the eye off the gates, which the
# JUNGLE and OCEAN rows below had both been flagged as the ones to watch.
#
# Where the numbers landed, and how each was arrived at:
#
#   SKY    1.47 / 1.70 = 0.86   sigma 0.9   by eye
#   JUNGLE 3.67 / 2.53 = 1.45   sigma 1.0   measured
#   OCEAN  4.53 / 1.72 = 2.64   sigma 1.5   by eye
#   DREAM  0.46 / 1.03 = 0.45   sigma 1.1   by eye
#
# Only JUNGLE's is what the metric alone would pick. The first pass matched
# all three ratios onto ~1.45, and looking at it on a screen said otherwise:
# SKY and DREAM still read too busy in front, OCEAN had gone too soft. Take
# that as the standing correction to the metric rather than an exception to
# it — it averages over a whole painting, and how much a foreground pulls
# the eye depends on where its detail sits, not on the mean.
#
# It does cost SKY the ordering. Its near layer is now softer than its own
# far layer, joining DREAM, so two of the four pairs no longer get their
# depth from blur. That is the same inversion this project once shipped and
# reverted wholesale; the difference is that it is now two deliberate rows
# rather than the whole scheme, with occlusion and the 2.5x speed split
# still carrying the depth. -SelfTest lists them as notes and still warns
# for any mode not named in $DepthInversionExpected.
#
# Use -Probe to re-derive any of it; that is where the numbers came from.
$NearSigma = 0.5

# Modes whose near layer is knowingly softer than its far layer, and why.
# Anything NOT listed here that inverts is a mistake and -SelfTest says so.
$DepthInversionExpected = @{
    sky   = 'judged by eye; its far layer paints hard-edged stone arches that the mean does not weight the way the eye does'
    dream = 'near art is softer raw (0.78) than any far layer in the project, so no sigma can order this pair'
}

$ModeBackgrounds = @{
    sky = @(
        # The one source that is not 2208x1056. At 1472x704 it is *magnified*
        # 1.21x to fill the view, where every other layer is minified to
        # 0.81x — a factor of 1.5 in how far the same sigma spreads on
        # screen, which is exactly why Sharpness measures after resampling.
        # 1.0 lands it at 1.70, level with the single background it replaces
        # (1.76) and a touch under it for the near layer now on top.
        #
        # Do not reach for a bigger number to hide the stone arches, which
        # share the SKY gate's white-and-gold-with-a-blue-gem look. Blur does
        # not fix that: at 1.6 the whole painting is softer than anything
        # this project ships and the arch still reads as an arch. It is a
        # shape-and-palette problem, so the fix is in the art.
        @{ File = 'background_far';  Sigma = 1.0; CutOut = $false }
        # Clouds, and only over the bottom half of the screen (0% coverage
        # above y=512 of 854, ~65% below). Softest raw near layer of the
        # three (2.52), and at the old floor of 0.5 it only came down to
        # 2.32.
        #
        # 0.9 takes it to 1.47, and that is BELOW this mode's far layer at
        # 1.70 — the pair is deliberately inverted here, see
        # $DepthInversionExpected. The metric wanted 0.5 and the screen
        # disagreed: the far layer's sharpness sits in hard-edged stone
        # arches that a whole-image mean under-weights, so 1.70 reads
        # sharper than it measures and the clouds in front of it needed to
        # come down further than the number allowed.
        @{ File = 'background_near'; Sigma = 0.9; CutOut = $true }
    )
    jungle = @(
        # Two layers, so neither can be as strong as a lone background would
        # be. 1.2 lands the far layer at sharpness 2.53, just under the
        # sharpest of the retired single backgrounds (OCEAN's, at 2.71) — it
        # gives up a little more than it would alone because the near layer
        # now stacks its own detail on top. It needs *less* sigma than the
        # 1.55 those singles used, not more: the painting is already hazy.
        @{ File = 'background_far';  Sigma = 1.2; CutOut = $false }
        # Busiest near layer of the three (raw 6.76), and the one that sits
        # most heavily over the play area — it covers 28% of the midriff and
        # 79% of the bottom strip. This is the row that said to watch it
        # first if the foreground started pulling the eye off the gates, and
        # it did.
        #
        # 1.0 takes it from 5.85 to 3.67, a 1.45 ratio against its own far
        # layer. That is as far as it goes: at 1.5 it measures 2.49, under
        # the 2.53 of the far layer behind it, and the pair inverts.
        @{ File = 'background_near'; Sigma = 1.0; CutOut = $true }
    )
    ocean = @(
        # The painting arrives gentle — an underwater scene carries its own
        # haze, so raw it is already at 3.16 where JUNGLE's far layer was
        # 4.26 — and 0.6 would be enough to land it at 2.49, level with
        # JUNGLE's far layer and just under what OCEAN shipped alone (2.71).
        #
        # 1.0 anyway, landing at 1.72 beside SKY's far layer (1.70, the other
        # already-hazy source). This is the one place the metric had to be
        # overruled, and it is worth knowing why: mean |Laplacian| averages
        # over the whole image, and this one is mostly flat blue water around
        # a few hard-outlined stone structures. The flat majority drags the
        # mean down while the ruins stay every bit as crisp to the eye —
        # 0.6 and 1.0 composite almost identically on screen despite reading
        # 2.49 against 1.72. When the extra softness is that cheap, spend it.
        @{ File = 'background_far';  Sigma = 1.0; CutOut = $false }
        # Sharpest art in the project: coral and pillar detail put it at
        # 12.48 raw, nearly twice JUNGLE's near layer and five times SKY's.
        # At the old shared 0.5 it measured 10.73 — far and away the crispest
        # thing on screen behind the gates, and the row that was called out
        # as most likely to want a second look in play. It wanted one.
        #
        # 1.5, three times any other near layer's sigma, and that is the
        # point rather than a mistake: sigma is not comparable between
        # paintings, only the sharpness it lands on is. This one starts so
        # far ahead that it takes that much just to reach 4.53.
        #
        # Walked back from 2.5. That landed it at 2.52, a 1.46 ratio matching
        # JUNGLE's — the tidiest number of the four and too soft to look at.
        # This art is the project's most detailed, and flattening it to the
        # same reading as everything else threw away what the scene is. 4.53
        # is still 2.4x softer than the 10.73 that started this, and it keeps
        # the widest near/far gap of any pair (2.64), which is the right way
        # round for the mode with the busiest foreground.
        @{ File = 'background_near'; Sigma = 1.5; CutOut = $true }
    )
    dream = @(
        # 시그마 1.1은 이 모드가 단일 배경이던 시절 쓰던 값이고, 원경이 된
        # 뒤에도 그대로다. 이 그림은 처음부터 부드러운 파스텔이라 세게 걸면
        # 꽃 모양만 뭉개진다 — 1.8까지 올려 봤지만 화면에서 달라지는 게 없고
        # 꽃만 잃는다.
        #
        # 이 쌍만은 흐림이 깊이를 말해 주지 않는다. 근경이 원본 그대로도
        # 0.78인데, 이는 프로젝트의 어떤 *원경*보다 부드럽다(스카이 1.70,
        # 정글 2.53, 오션 1.72). 같은 파스텔 구름을 같은 톤으로 그린 두 장이라
        # 고유 부드러움이 같아서, 원경을 2.0까지 밀어도 겨우 동점이다.
        #
        # 그래서 깊이는 다른 두 단서가 맡는다: 근경이 화면 아래에서 원경을
        # 가리는 것(occlusion), 그리고 2.67배 속도차. 선명도 순서가 뒤집혀
        # 보이는 것은 처리가 잘못된 게 아니라 소재가 그런 것이다.
        @{ File = 'background_far';  Sigma = 1.1; CutOut = $false }
        # 1472x704 — 네 모드의 근경 중 유일하게 2208x1056 이 아니라 화면을
        # 채우며 1.21배 확대된다(스카이는 원경이 그랬다). Sharpness 가 리샘플
        # 뒤에 재는 이유가 이것이다.
        #
        # 0.5 에서 1.1 로. 0.72 -> 0.46 이고, 이 그림에서 얻어낼 수 있는
        # 거의 전부다 — 원본이 이미 부드러워서 곡선이 여기서 눕는다(0.9 에
        # 0.50, 1.4 에 0.43, 1.8 에 0.40). 더 올리면 꽃 모양만 잃고 부드러움은
        # 안 는다. 이미 뒤집힌 쌍이라 순서를 더 망가뜨릴 것도 없다.
        @{ File = 'background_near'; Sigma = 1.1; CutOut = $true }
    )
}

$ModeOrder = @('sky', 'jungle', 'ocean', 'dream')

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

function Get-Sigma($row) {
    if ($Sigma -gt 0) { return $Sigma }   # explicit -Sigma wins, for trying a value out
    return $row.Sigma
}

if ($Sharpness) {
    Write-Host "Sharpness of every committed blur, measured at the $ViewHeight px height the game draws it."
    Write-Host "(mean |Laplacian| over opaque RGB; 'draw' is how far the source is scaled to get there)"
    foreach ($m in $ModeOrder) {
        foreach ($row in (Get-Rows $m)) {
            $p = Get-Paths $m $row
            if (-not [System.IO.File]::Exists($p.Out)) { continue }
            $img = [System.Drawing.Bitmap]::FromFile($p.Out)
            $srcH = $img.Height
            $img.Dispose()
            Write-Host ("  {0,-7} {1,-22} src {2,5}px  draw {3,5:N2}x  sigma {4,4} -> sharpness {5,6:N3}" -f `
                $m, $row.File, $srcH, ($ViewHeight / $srcH), $row.Sigma, ([BgBlur]::Sharpness($p.Out, $ViewHeight)))
        }
    }
    return
}

if ($Probe) {
    if (-not $Mode) { throw "-Probe needs -Mode <name> to say which pair to sweep." }
    Write-Host "Probing $Mode. Sharpness each sigma WOULD produce, measured at $ViewHeight px. Nothing is written."
    $tmp = [System.IO.Path]::GetTempPath()
    $candidates = @($ProbeSigmas -split ',' | ForEach-Object { [double]$_.Trim() })
    foreach ($row in (Get-Rows $Mode)) {
        $p = Get-Paths $Mode $row
        if (-not [System.IO.File]::Exists($p.In)) { continue }
        $kind = if ($row.CutOut) { 'near' } else { 'far ' }
        Write-Host ("  {0} {1,-22} committed sigma {2}" -f $kind, $row.File, $row.Sigma)
        foreach ($s in $candidates) {
            $probePath = [System.IO.Path]::Combine($tmp, ('bgprobe_{0}_{1}.png' -f $Mode, $row.File))
            [BgBlur]::Run($p.In, $probePath, $s, $row.CutOut)
            Write-Host ("      sigma {0,4} -> sharpness {1,7:N3}" -f $s, ([BgBlur]::Sharpness($probePath, $ViewHeight)))
            [System.IO.File]::Delete($probePath)
        }
    }
    return
}

if ($SelfTest) {
    # The far/near relationship is the whole look, and nothing else would
    # notice it inverting — the art would just quietly go flat again.
    #
    # Asserted on measured SHARPNESS, not on the sigmas. Comparing sigmas
    # was the old check and it is wrong now that the near rows carry their
    # own: OCEAN needs 2.5 against its far layer's 1.0 purely because that
    # painting starts five times busier, and the pair it produces is
    # correctly ordered. Only what the files measure at is comparable.
    #
    # Modes in $DepthInversionExpected are reported, not warned about; see
    # that table for each one's reason.
    foreach ($m in $ModeOrder) {
        $lvl = @{}
        foreach ($row in (Get-Rows $m)) {
            $p = Get-Paths $m $row
            if (-not [System.IO.File]::Exists($p.Out)) { continue }
            $lvl[$(if ($row.CutOut) { 'near' } else { 'far' })] = [BgBlur]::Sharpness($p.Out, $ViewHeight)
        }
        if ($lvl.ContainsKey('near') -and $lvl.ContainsKey('far')) {
            $ratio = $lvl['near'] / $lvl['far']
            if ($DepthInversionExpected.ContainsKey($m)) {
                Write-Host ("  note  {0}: near {1:N2} / far {2:N2} = {3:N2} — inversion expected: {4}" -f $m, $lvl['near'], $lvl['far'], $ratio, $DepthInversionExpected[$m])
            } elseif ($ratio -le 1.0) {
                Write-Host ("  WARN  {0}: near {1:N2} is no sharper than far {2:N2} — the pair has inverted and the parallax will read flat" -f $m, $lvl['near'], $lvl['far'])
            } else {
                Write-Host ("  ok    {0}: near {1:N2} / far {2:N2} = {3:N2}" -f $m, $lvl['near'], $lvl['far'], $ratio)
            }
        }
    }
    Write-Host "Self-test: re-deriving each committed blur and comparing to the file on disk."
    $tmp = [System.IO.Path]::GetTempPath()
    foreach ($m in $ModeOrder) {
        foreach ($row in (Get-Rows $m)) {
            $p = Get-Paths $m $row
            if (-not ([System.IO.File]::Exists($p.In) -and [System.IO.File]::Exists($p.Out))) {
                Write-Host ("  {0,-7} {1,-22} skipped (needs both the source and its _blur)" -f $m, $row.File)
                continue
            }
            $probePath = [System.IO.Path]::Combine($tmp, ('bgblur_{0}_{1}.png' -f $m, $row.File))
            $s = Get-Sigma $row
            [BgBlur]::Run($p.In, $probePath, $s, $row.CutOut)
            $rmse = [BgBlur]::Rmse($probePath, $p.Out)
            Write-Host ("  {0,-7} {1,-22} sigma {2,4} -> RMSE vs committed: {3:N3} / 255" -f $m, $row.File, $s, $rmse)
            [System.IO.File]::Delete($probePath)
        }
    }
    return
}

if (-not $Mode) { throw "Pass -Mode <name> (e.g. jungle), -SelfTest, or -Sharpness." }
Write-Host "Blurring backgrounds"
foreach ($row in (Get-Rows $Mode)) {
    $p = Get-Paths $Mode $row
    if (-not [System.IO.File]::Exists($p.In)) {
        Write-Host ("  {0,-22} source not found: {1}" -f $row.File, $p.In)
        continue
    }
    $s = Get-Sigma $row
    [BgBlur]::Run($p.In, $p.Out, $s, $row.CutOut)
    $kind = if ($row.CutOut) { 'cut-out' } else { 'opaque ' }
    Write-Host ("  {0,-22} {1} sigma {2,4} -> sharpness {3,6:N3}" -f $row.File, $kind, $s, ([BgBlur]::Sharpness($p.Out, $ViewHeight)))
}
