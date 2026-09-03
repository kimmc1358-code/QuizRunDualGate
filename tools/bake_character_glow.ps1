<#
.SYNOPSIS
    Generates the radial halo the boost glow draws behind the character.

.DESCRIPTION
    Main.gd's custom-draw setup has no shader pass, so a glow cannot be
    computed at draw time — it has to be a texture. This one is generated
    rather than painted, because it is a pure radial falloff with nothing an
    artist would decide: the colour comes from MODE_BOOST_GLOW_COLOR at draw
    time and the size from BOOST_GLOW_SIZE_SCALE, so the file only carries
    the shape of the fade.

    RGB is white everywhere, including where alpha is zero. That is
    deliberate: the texture is drawn minified with linear filtering, and if
    the transparent pixels held black instead, the sampler would drag it
    inward as a dark ring around the halo — the same premultiplied-alpha
    trap the background cut-outs have (see tools/blur_background.ps1).
    White-on-transparent has nothing to bleed.

    The falloff is a Gaussian, shifted and rescaled so it reaches exactly
    zero at the edge of the canvas. A plain (1-r)^p profile has a visible
    kink at the centre and a Gaussian that has not been zeroed leaves a
    faint hard rim where the texture ends, which reads as a disc rather than
    a glow.

    Re-run with -SelfTest to check the committed PNG still matches what this
    script produces; anything but a near-zero residual means the file was
    hand-edited or the parameters drifted.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/bake_character_glow.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/bake_character_glow.ps1 -SelfTest
#>
param(
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# 256 to match the character sheets' own cell size. The halo is drawn at
# roughly 200px, so there is no minification worth worrying about and no
# reason to go bigger.
$Size = 256
# Gaussian tightness. 4.5 puts alpha at ~0.32 half way out, which is the
# part that actually reads: the character covers the middle, so what the
# player sees is the ring between its silhouette and the fade.
$Falloff = 4.5

$csharp = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class GlowBake {
    public static void Run(string outPath, int size, double falloff) {
        Bitmap dst = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        BitmapData d = dst.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        byte[] buf = new byte[d.Stride * size];
        double c = (size - 1) / 2.0;
        double edge = Math.Exp(-falloff);          // what the raw Gaussian still has left at r = 1
        double norm = 1.0 / (1.0 - edge);          // rescale so the centre stays 1.0 after the shift
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                double dx = (x - c) / c;
                double dy = (y - c) / c;
                double r = Math.Sqrt(dx * dx + dy * dy);
                double a = 0.0;
                if (r < 1.0) {
                    a = (Math.Exp(-falloff * r * r) - edge) * norm;
                    if (a < 0.0) a = 0.0;
                }
                int i = y * d.Stride + x * 4;
                buf[i + 0] = 255;   // B — white everywhere, see the header
                buf[i + 1] = 255;   // G
                buf[i + 2] = 255;   // R
                buf[i + 3] = (byte)Math.Round(Math.Min(1.0, a) * 255.0);
            }
        }
        Marshal.Copy(buf, 0, d.Scan0, buf.Length);
        dst.UnlockBits(d);
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
        for (int i = 0; i < ba.Length; i++) { double diff = ba[i] - bb[i]; s += diff * diff; n++; }
        a.Dispose(); b.Dispose();
        return Math.Sqrt(s / n);
    }

    // Alpha at a few radii, as a sanity readout on the falloff shape.
    public static double AlphaAt(string path, double r) {
        Bitmap b = (Bitmap)Bitmap.FromFile(path);
        int size = b.Width;
        double c = (size - 1) / 2.0;
        int x = (int)Math.Round(c + r * c);
        Color px = b.GetPixel(Math.Min(size - 1, x), (int)Math.Round(c));
        b.Dispose();
        return px.A / 255.0;
    }
}
"@
Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing

$repo = Split-Path -Parent $PSScriptRoot
$dir = [System.IO.Path]::Combine($repo, 'assets', 'fx', 'character_glow')
$out = [System.IO.Path]::Combine($dir, 'glow_radial_256.png')

if ($SelfTest) {
    if (-not [System.IO.File]::Exists($out)) { throw "Nothing committed at $out — run without -SelfTest first." }
    $probe = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'glow_probe.png')
    [GlowBake]::Run($probe, $Size, $Falloff)
    $rmse = [GlowBake]::Rmse($probe, $out)
    Write-Host ("glow_radial_256  size {0}  falloff {1}  -> RMSE vs committed: {2:N3} / 255" -f $Size, $Falloff, $rmse)
    [System.IO.File]::Delete($probe)
    return
}

if (-not [System.IO.Directory]::Exists($dir)) { [System.IO.Directory]::CreateDirectory($dir) | Out-Null }
[GlowBake]::Run($out, $Size, $Falloff)
Write-Host ("wrote {0}  ({1}x{1}, falloff {2})" -f $out, $Size, $Falloff)
Write-Host "alpha profile:"
foreach ($r in 0.0, 0.25, 0.5, 0.75, 0.95, 1.0) {
    Write-Host ("  r {0,5:N2}  alpha {1,5:N3}" -f $r, ([GlowBake]::AlphaAt($out, $r)))
}
