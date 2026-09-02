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
    per file, because a mode is no longer always one image: JUNGLE is a
    far/near parallax pair. Each row carries its own sigma and its own
    CutOut flag.

    CutOut is the difference between a full-bleed painting and a near layer
    with transparency. An opaque background can be blurred on RGB alone —
    there is no edge in the alpha to soften. A cut-out cannot: blurring
    colour and alpha separately drags the transparent pixels' colour into
    the silhouette as a dark fringe. CutOut rows premultiply, blur all four
    channels, then divide alpha back out.

    Strength was not picked by eye. Sharpness here is the mean |Laplacian|
    over RGB sampled only where the pixel is fully opaque (-Sharpness
    reports it), and the shipped blurs sit at jungle 2.12, ocean 1.90,
    dream 1.19. The sky/ocean sigma was recovered by re-blurring the
    committed art across a range of values and finding which one reproduced
    its committed *_blur.png, with a residual around 1/255 — down at PNG
    quantisation noise. The jungle pair's values are measured against that
    same band; see their comments in the table.

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
    public static double Sharpness(string path) {
        Bitmap b = (Bitmap)Bitmap.FromFile(path);
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
        @{ File = 'background_single'; Sigma = 1.55; CutOut = $false }
    )
    jungle = @(
        # Two layers, so neither can be as strong as a lone background would
        # be. 1.2 lands the far layer at sharpness 1.79, just under the
        # softest shipped full-scene mode (ocean, 1.90) — it gives up a
        # little more than it would alone because the near layer now stacks
        # its own detail on top. It needs *less* sigma than the 1.55 the
        # other modes use, not more: the painting is already hazy (raw 4.26,
        # against the old single background's 6.35).
        @{ File = 'background_far';  Sigma = 1.2; CutOut = $false }
        # 2.5 lands the near layer at 1.19 — level with DREAM, the softest
        # thing this project ships. It is the only background layer that
        # both moves fast (bg_near_speed_ratio is 2.7x the far layer) and
        # sits over the gate lanes, and detail travelling that quickly
        # across the play area is what actually pulls the eye off the gates.
        @{ File = 'background_near'; Sigma = 2.5; CutOut = $true }
    )
    ocean = @(
        @{ File = 'background_single'; Sigma = 1.55; CutOut = $false }
    )
    dream = @(
        # 드림의 블러는 다른 모드보다 훨씬 약하다. 이 그림은 처음부터 부드러운
        # 파스텔이라(블러본 선명도 1.19로 넷 중 제일 낮다) 세게 걸면 꽃 모양만
        # 뭉개진다.
        #
        # 이 줄은 예전에 background_single(v1)을 3.5로 가리키고 있었다. 게임이
        # 읽는 건 v2 쪽이라, 자체 테스트는 아무도 쓰지 않는 파일만 초록으로
        # 통과시키고 있었고 v2의 값은 검증된 적이 없었다. 커밋된 v2 블러본에서
        # 되찾은 실제 값은 1.1이다(RMSE 1.06/255, sky·ocean과 같은 잡음 수준).
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
    Write-Host "Sharpness (mean |Laplacian| over opaque RGB) of every committed blur:"
    foreach ($m in $ModeOrder) {
        foreach ($row in (Get-Rows $m)) {
            $p = Get-Paths $m $row
            if (-not [System.IO.File]::Exists($p.Out)) { continue }
            Write-Host ("  {0,-7} {1,-22} {2,6:N3}" -f $m, $row.File, ([BgBlur]::Sharpness($p.Out)))
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
    Write-Host ("  {0,-22} {1} sigma {2,4} -> sharpness {3,6:N3}" -f $row.File, $kind, $s, ([BgBlur]::Sharpness($p.Out)))
}
