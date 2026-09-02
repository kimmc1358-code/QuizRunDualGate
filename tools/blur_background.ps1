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

    $ModeBackgrounds below names every file the game actually loads, one row
    per file, because a mode is no longer always one image: SKY and JUNGLE
    are far/near parallax pairs. Each row carries its own sigma and its own
    CutOut flag.

    CutOut is the difference between a full-bleed painting and a near layer
    with transparency. An opaque background can be blurred on RGB alone —
    there is no edge in the alpha to soften. A cut-out cannot: blurring
    colour and alpha separately drags the transparent pixels' colour into
    the silhouette as a dark fringe. CutOut rows premultiply, blur all four
    channels, then divide alpha back out.

    Strength was not picked by eye. Sharpness here is the mean |Laplacian|
    over RGB sampled only where the pixel is fully opaque, measured after
    resampling to the height the game draws the layer at (-Sharpness reports
    it, with each file's source height and draw scale). Screen space is the
    only space worth comparing in, and it stopped being the same as source
    space once SKY's far layer arrived at 1472x704 while everything else is
    2208x1056.

    The scale is anchored on art nobody chose by eye. DREAM's sigma was
    recovered by re-blurring its source across a range of values and finding
    which one reproduced the committed *_blur.png, with a residual around
    1/255 — down at PNG quantisation noise; the single backgrounds SKY,
    JUNGLE and OCEAN shipped with before their parallax pairs were recovered
    the same way, and they are what the pairs were measured against. Those
    singles are gone from the tree now (git has them), so the numbers quoted
    in the table comments are the record of where they sat.

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
#>
param(
    [string]$Mode,
    [switch]$SelfTest,
    [switch]$Sharpness,
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
        # above y=512 of 854, ~65% below). They come pre-softened by their
        # own subject, so 1.0 already lands at 1.37 — under JUNGLE's near
        # layer without having to be smeared into fog.
        @{ File = 'background_near'; Sigma = 1.0; CutOut = $true }
    )
    jungle = @(
        # Two layers, so neither can be as strong as a lone background would
        # be. 1.2 lands the far layer at sharpness 2.53, just under the
        # sharpest of the retired single backgrounds (OCEAN's, at 2.71) — it
        # gives up a little more than it would alone because the near layer
        # now stacks its own detail on top. It needs *less* sigma than the
        # 1.55 those singles used, not more: the painting is already hazy.
        @{ File = 'background_far';  Sigma = 1.2; CutOut = $false }
        # 2.5 lands the near layer at 1.57, the softest full-strength layer
        # here. It both moves fast (bg_near_speed_ratio is 2.7x the far
        # layer) and sits over the gate lanes — it clears only 28% of the
        # play area's midriff and 21% of the bottom strip — and detail
        # travelling that quickly across the play area is what actually
        # pulls the eye off the gates.
        @{ File = 'background_near'; Sigma = 2.5; CutOut = $true }
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
        # And the strongest, because this one arrives sharp: coral and
        # pillar detail put the raw art at 12.48, nearly twice JUNGLE's near
        # layer (6.76) and five times SKY's (2.52). 4.0 is what it costs to
        # land at 1.56, the same place JUNGLE's near layer sits — it is the
        # landing that is being matched, not the sigma.
        @{ File = 'background_near'; Sigma = 4.0; CutOut = $true }
    )
    dream = @(
        # 시그마 1.1로, 원경 중에서는 제일 약하게 건다. 이 그림은 처음부터
        # 부드러운 파스텔이라 세게 걸면 꽃 모양만 뭉개진다. 그러고도 1.63으로
        # 앉는 건 원본이 그만큼 부드럽다는 뜻이다.
        #
        # 근경이 없는 유일한 모드이기도 하다. 나머지 셋은 전부 원경/근경 쌍이라,
        # 이 값은 위에서 쌍을 맞출 때 쓴 기준점 중 하나다.
        #
        # 이 줄은 예전에 background_single(v1)을 3.5로 가리키고 있었다. 게임이
        # 읽는 건 v2 쪽이라, 자체 테스트는 아무도 쓰지 않는 파일만 초록으로
        # 통과시키고 있었고 v2의 값은 검증된 적이 없었다. 커밋된 v2 블러본에서
        # 되찾은 실제 값이 1.1이다(RMSE 1.06/255, PNG 양자화 잡음 수준).
        @{ File = 'background_single_v2'; Sigma = 1.1; CutOut = $false }
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

if ($SelfTest) {
    Write-Host "Self-test: re-deriving each committed blur and comparing to the file on disk."
    $tmp = [System.IO.Path]::GetTempPath()
    foreach ($m in $ModeOrder) {
        foreach ($row in (Get-Rows $m)) {
            $p = Get-Paths $m $row
            if (-not ([System.IO.File]::Exists($p.In) -and [System.IO.File]::Exists($p.Out))) {
                Write-Host ("  {0,-7} {1,-22} skipped (needs both the source and its _blur)" -f $m, $row.File)
                continue
            }
            $probe = [System.IO.Path]::Combine($tmp, ('bgblur_{0}_{1}.png' -f $m, $row.File))
            $s = Get-Sigma $row
            [BgBlur]::Run($p.In, $probe, $s, $row.CutOut)
            $rmse = [BgBlur]::Rmse($probe, $p.Out)
            Write-Host ("  {0,-7} {1,-22} sigma {2,4} -> RMSE vs committed: {3:N3} / 255" -f $m, $row.File, $s, $rmse)
            [System.IO.File]::Delete($probe)
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
