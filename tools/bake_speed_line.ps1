<#
.SYNOPSIS
    Bakes the boost speed-line strip from its source art.

.DESCRIPTION
    The source is a 817x309 cluster of soft white streaks. The game draws
    each streak far smaller and far flatter than that — roughly 180-360 wide
    by 12-26 tall — and doing the whole squash at draw time means sampling a
    309px column down to 16px, which aliases into a flickering comb no
    matter what the filter is. So the squash is baked: the file ships at the
    proportions it is actually drawn in, and the draw only has to minify by
    a small factor. That is the same reasoning as slice_boost_bar_sheet's
    -TrackHeight, and CLAUDE.md's "cut UI art at the size it is drawn".

    Premultiplied before the resize, and this one is not optional. The
    source's fully transparent pixels hold black (measured: mean RGB 0,0,0
    where alpha is 0, against 219,219,219 where it is visible), so a plain
    downscale averages that black into every streak and hands back grey
    lines with dark edges.

    No blur is applied. The art arrives soft already — zero fully opaque
    pixels, 71% partially transparent — so there is nothing here for a sigma
    to do that the artist has not done.

    -SelfTest re-derives the strip and diffs it against what is committed.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/bake_speed_line.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/bake_speed_line.ps1 -SelfTest
#>
param(
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# Output size. Wide enough that a streak drawn at its longest (360px) is
# still minifying rather than stretching, and 48 tall so the tallest draw
# (26px) is under 2x. Going thinner here would bake in the squash twice.
$OutW = 512
$OutH = 48

$csharp = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

public static class SpeedLineBake {
    public static void Run(string inPath, string outPath, int outW, int outH) {
        Bitmap src = (Bitmap)Bitmap.FromFile(inPath);
        int w = src.Width, h = src.Height;
        BitmapData d = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        byte[] buf = new byte[d.Stride * h];
        Marshal.Copy(d.Scan0, buf, 0, buf.Length);
        int stride = d.Stride;
        src.UnlockBits(d);
        src.Dispose();

        // ---- premultiply in place ----
        // Everything below resamples, and a resampler averages colour across
        // neighbours regardless of their alpha. Scaling colour by alpha first
        // is what stops the transparent black being part of that average.
        Bitmap pre = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        BitmapData pd = pre.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        byte[] pbuf = new byte[pd.Stride * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int i = y * stride + x * 4;
                int o = y * pd.Stride + x * 4;
                double a = buf[i + 3] / 255.0;
                pbuf[o + 0] = (byte)Math.Round(buf[i + 0] * a);
                pbuf[o + 1] = (byte)Math.Round(buf[i + 1] * a);
                pbuf[o + 2] = (byte)Math.Round(buf[i + 2] * a);
                pbuf[o + 3] = buf[i + 3];
            }
        Marshal.Copy(pbuf, 0, pd.Scan0, pbuf.Length);
        pre.UnlockBits(pd);

        // ---- resize ----
        Bitmap small = new Bitmap(outW, outH, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(small)) {
            g.CompositingMode = CompositingMode.SourceCopy;   // keep the premultiplied values, do not blend
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.DrawImage(pre, new Rectangle(0, 0, outW, outH), 0, 0, w, h, GraphicsUnit.Pixel);
        }
        pre.Dispose();

        // ---- un-premultiply ----
        BitmapData sd = small.LockBits(new Rectangle(0, 0, outW, outH), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        byte[] sbuf = new byte[sd.Stride * outH];
        Marshal.Copy(sd.Scan0, sbuf, 0, sbuf.Length);
        for (int y = 0; y < outH; y++)
            for (int x = 0; x < outW; x++) {
                int i = y * sd.Stride + x * 4;
                double a = sbuf[i + 3];
                for (int c = 0; c < 3; c++) {
                    // Below half a level the divide only amplifies rounding
                    // noise, and that pixel is invisible anyway.
                    double v = (a > 0.5) ? sbuf[i + c] * 255.0 / a : 0.0;
                    sbuf[i + c] = (byte)Math.Max(0, Math.Min(255, Math.Round(v)));
                }
            }
        Marshal.Copy(sbuf, 0, sd.Scan0, sbuf.Length);
        small.UnlockBits(sd);

        small.Save(outPath, ImageFormat.Png);
        small.Dispose();
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
        for (int i = 0; i < ba.Length; i++) { double diff = ba[i] - bb[i]; s += diff * diff; n++; }
        a.Dispose(); b.Dispose();
        return Math.Sqrt(s / n);
    }

    // Mean alpha and the darkest visible pixel, as a readout on whether the
    // premultiply did its job — a botched one shows up as grey streaks.
    public static string Report(string path) {
        Bitmap b = (Bitmap)Bitmap.FromFile(path);
        int w = b.Width, h = b.Height;
        BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        byte[] buf = new byte[d.Stride * h];
        Marshal.Copy(d.Scan0, buf, 0, buf.Length);
        b.UnlockBits(d); b.Dispose();
        double sa = 0; long n = 0; double lum = 0; long vis = 0; int darkest = 255;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int i = y * d.Stride + x * 4;
                sa += buf[i + 3]; n++;
                if (buf[i + 3] > 128) {
                    int l = (buf[i] + buf[i + 1] + buf[i + 2]) / 3;
                    lum += l; vis++;
                    if (l < darkest) darkest = l;
                }
            }
        return String.Format("mean alpha {0:N1}/255, mean luma where alpha>128 {1:N0}/255, darkest such pixel {2}",
            sa / n, vis > 0 ? lum / vis : 0, vis > 0 ? darkest : 0);
    }
}
"@
Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing

$repo = Split-Path -Parent $PSScriptRoot
$dir = [System.IO.Path]::Combine($repo, 'assets', 'fx', 'speed_lines')
$src = [System.IO.Path]::Combine($dir, 'source', 'speed_line.png')
$out = [System.IO.Path]::Combine($dir, 'speed_line_strip.png')

if (-not [System.IO.File]::Exists($src)) { throw "Source not found: $src" }

if ($SelfTest) {
    if (-not [System.IO.File]::Exists($out)) { throw "Nothing committed at $out — run without -SelfTest first." }
    $probe = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'speedline_probe.png')
    [SpeedLineBake]::Run($src, $probe, $OutW, $OutH)
    Write-Host ("speed_line_strip  {0}x{1}  -> RMSE vs committed: {2:N3} / 255" -f $OutW, $OutH, ([SpeedLineBake]::Rmse($probe, $out)))
    [System.IO.File]::Delete($probe)
    return
}

[SpeedLineBake]::Run($src, $out, $OutW, $OutH)
Write-Host ("wrote {0}  ({1}x{2} from {3})" -f $out, $OutW, $OutH, (Split-Path $src -Leaf))
Write-Host ("  " + [SpeedLineBake]::Report($out))
