<#
.SYNOPSIS
    Produces a mode's background_single_blur.png from its background_single.png.

.DESCRIPTION
    The game draws the pre-blurred copy, not the original — there is no
    runtime blur shader in Main.gd's custom-draw setup, so the softness has
    to be baked into the file (see MODE_BG_TEXTURE_PATH). Run this whenever
    a mode's background art is added or replaced, so its backdrop recedes
    behind the gate and character like the rest.

    Strength lives in the $ModeSigma table below, not in a single constant:
    sky, jungle and ocean share one value, dream is softer. The shared
    value was not picked by eye — it was recovered by re-blurring each
    committed background at a range of sigmas and finding which one
    reproduced its committed *_blur.png, with all three landing on the same
    number and a residual around 1/255, down at PNG quantisation noise.

    Use -SelfTest to re-derive every mode and diff against what is
    committed; anything but a near-zero residual means the table and the
    files have drifted apart.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/blur_background.ps1 -Mode dream

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/blur_background.ps1 -SelfTest
#>
param(
    [string]$Mode,
    [switch]$SelfTest,
    [double]$Sigma = 0    # 0 = use the per-mode value in $ModeSigma below
)

$ErrorActionPreference = 'Stop'

$csharp = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class BgBlur {
    // Separable Gaussian, clamped at the edges. Alpha is carried through
    // untouched: these backgrounds are opaque, and blurring alpha would
    // only soften an edge that is not there.
    public static void Run(string inPath, string outPath, double sigma) {
        Bitmap src = (Bitmap)Bitmap.FromFile(inPath);
        int w = src.Width, h = src.Height;
        BitmapData d = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        byte[] buf = new byte[d.Stride * h];
        Marshal.Copy(d.Scan0, buf, 0, buf.Length);
        int stride = d.Stride;
        src.UnlockBits(d);
        src.Dispose();

        int r = (int)Math.Ceiling(sigma * 3.0);
        double[] k = new double[2 * r + 1];
        double sum = 0;
        for (int i = -r; i <= r; i++) { k[i + r] = Math.Exp(-(i * i) / (2.0 * sigma * sigma)); sum += k[i + r]; }
        for (int i = 0; i < k.Length; i++) k[i] /= sum;

        float[] plane = new float[w * h];
        float[] tmp = new float[w * h];
        byte[] outBuf = (byte[])buf.Clone();

        for (int c = 0; c < 3; c++) {
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    plane[y * w + x] = buf[y * stride + x * 4 + c];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                    double s = 0;
                    for (int i = -r; i <= r; i++) { int xx = Math.Min(w - 1, Math.Max(0, x + i)); s += plane[y * w + xx] * k[i + r]; }
                    tmp[y * w + x] = (float)s;
                }
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                    double s = 0;
                    for (int i = -r; i <= r; i++) { int yy = Math.Min(h - 1, Math.Max(0, y + i)); s += tmp[yy * w + x] * k[i + r]; }
                    int v = (int)Math.Round(s);
                    outBuf[y * stride + x * 4 + c] = (byte)(v < 0 ? 0 : (v > 255 ? 255 : v));
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
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                for (int c = 0; c < 3; c++) {
                    double diff = ba[y * da.Stride + x * 4 + c] - bb[y * db.Stride + x * 4 + c];
                    s += diff * diff; n++;
                }
        a.Dispose(); b.Dispose();
        return Math.Sqrt(s / n);
    }
}
"@
Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing

$repo = Split-Path -Parent $PSScriptRoot
$bgRoot = [System.IO.Path]::Combine($repo, 'assets', 'backgrounds')

# Blur strength per mode. The first three share the value recovered from
# their committed art; DREAM is deliberately softer, because its painting
# is busier and higher-contrast than the others and the unicorn and the
# gate flags were getting lost in it at the shared setting.
#
# Keep this table in step with what is actually committed. It is the only
# record of the difference — the PNGs themselves do not say how they were
# made, so a bare re-run of this tool is what would otherwise quietly
# flatten DREAM back to the shared value.
$ModeSigma = @{
    sky    = 1.55
    jungle = 1.55
    ocean  = 1.55
    dream  = 3.5
}
$DefaultSigma = 1.55

function Get-Sigma([string]$name) {
    if ($Sigma -gt 0) { return $Sigma }          # explicit -Sigma wins, for trying a value out
    if ($ModeSigma.ContainsKey($name)) { return $ModeSigma[$name] }
    return $DefaultSigma
}

function Convert-Mode([string]$name) {
    $dir = [System.IO.Path]::Combine($bgRoot, $name + '_world')
    $in  = [System.IO.Path]::Combine($dir, 'background_single.png')
    $out = [System.IO.Path]::Combine($dir, 'background_single_blur.png')
    if (-not [System.IO.File]::Exists($in)) {
        Write-Host ("  {0,-8} background_single.png not found in {1}" -f $name, $dir)
        return
    }
    $s = Get-Sigma $name
    [BgBlur]::Run($in, $out, $s)
    Write-Host ("  {0,-8} blurred at sigma {1} -> {2}" -f $name, $s, $out)
}

if ($SelfTest) {
    Write-Host "Self-test: re-deriving each existing mode's blur and comparing to the committed file."
    $tmp = [System.IO.Path]::GetTempPath()
    foreach ($m in @('sky', 'jungle', 'ocean', 'dream')) {
        $in  = [System.IO.Path]::Combine($bgRoot, $m + '_world', 'background_single.png')
        $ref = [System.IO.Path]::Combine($bgRoot, $m + '_world', 'background_single_blur.png')
        if (-not ([System.IO.File]::Exists($in) -and [System.IO.File]::Exists($ref))) {
            Write-Host ("  {0,-8} skipped (needs both background_single.png and background_single_blur.png)" -f $m)
            continue
        }
        $probe = [System.IO.Path]::Combine($tmp, 'bgblur_' + $m + '.png')
        $s = Get-Sigma $m
        [BgBlur]::Run($in, $probe, $s)
        $rmse = [BgBlur]::Rmse($probe, $ref)
        Write-Host ("  {0,-8} sigma {1,4} -> RMSE vs committed blur: {2:N3} / 255" -f $m, $s, $rmse)
        [System.IO.File]::Delete($probe)
    }
    return
}

if (-not $Mode) { throw "Pass -Mode <name> (e.g. dream), or -SelfTest." }
Write-Host "Blurring background"
Convert-Mode $Mode
