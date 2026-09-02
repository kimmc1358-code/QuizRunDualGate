<#
.SYNOPSIS
    Cuts assets/backgrounds/ambient_sheet.png into the per-mode ambient
    particle sprites, blurring each one on the way out.

.DESCRIPTION
    One sheet, six rows, each row feeding a different mode's backdrop:

        row 1  flowers  -> DREAM    row 4  leaves   -> JUNGLE
        row 2  petals   -> DREAM    row 5  bubbles  -> OCEAN
        row 3  feathers -> SKY      row 6  bubbles  -> OCEAN

    Rows that share a mode keep numbering upward, so DREAM ends up with
    petal_01.. covering both its rows and OCEAN with bubble_01.. covering
    both of its. Output lands in assets/backgrounds/<mode>_world/particles/,
    the layout MODE_PARTICLE_DIR/PREFIX/COUNT in Main.gd already walks.

    Sprites are found, not computed: the sheet is scanned for rows of
    non-transparent pixels and then for runs of them across each row, so
    the cuts land on the artwork wherever it happens to sit. Column runs
    closer together than -MinGap are merged, which is what keeps a cluster
    of two or three bubbles as ONE sprite instead of splitting it.

    Every sprite is blurred (-Sigma) so the backdrop stays soft and never
    competes with the gate the player has to read. This project has no
    runtime blur shader — the softness is baked into the file, exactly as
    tools/bake_background.ps1 does for the backgrounds themselves.

    Unlike that tool, this one blurs the ALPHA channel too, and does it in
    premultiplied space. Backgrounds are opaque so it can leave alpha
    alone; these are cut-outs, and blurring colour while leaving a hard
    alpha edge leaves the silhouette crisp, while blurring alpha without
    premultiplying drags the transparent pixels' colour inward as a dark
    fringe. Each crop is also padded by the blur radius first, so the soft
    edge has somewhere to land instead of being clipped at the cut.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/slice_ambient_sheet.ps1 -Measure

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/slice_ambient_sheet.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/slice_ambient_sheet.ps1 -Sigma 2.4
#>
param(
    [string]$Source = "assets/backgrounds/ambient_sheet.png",
    [string]$OutRoot = "assets/backgrounds",
    # Transparent-pixel cutoff used to find rows and sprites.
    [int]$Threshold = 8,
    # Column runs with a gap smaller than this are one sprite. Keeps the
    # multi-bubble clusters in rows 5-6 together.
    [int]$MinGap = 18,
    # Margin kept around each sprite's tight bounds, on top of the blur
    # radius the script adds itself.
    [int]$Pad = 4,
    # Blur strength. Deliberately heavy — these are backdrop, and at a
    # gentler setting they read as foreground objects and pull the eye off
    # the gate. This is the value the committed sprites were cut at; change
    # it and re-cut, do not hand-edit the outputs.
    [double]$Sigma = 5.0,
    # Report the detected layout and write nothing.
    [switch]$Measure
)

$ErrorActionPreference = "Stop"

$sourcePath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Source))
if (-not (Test-Path $sourcePath)) { throw "Sheet not found: $sourcePath" }
$outRootPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutRoot))

# Row index -> which mode folder it feeds and what its files are called.
$RowTargets = @(
    @{ Dir = "dream_world";  Prefix = "petal"   },   # row 1, flowers
    @{ Dir = "dream_world";  Prefix = "petal"   },   # row 2, petals
    # Row 3's feathers did not suit the sky scene and were dropped — SKY
    # runs with no ambient layer (MODE_PARTICLE_COUNT[0] is 0). The row is
    # still detected so the row/target indexes keep lining up with the
    # sheet; it just is not written.
    @{ Dir = "sky_world";    Prefix = "feather"; Skip = $true },   # row 3
    @{ Dir = "jungle_world"; Prefix = "leaf"    },   # row 4
    @{ Dir = "ocean_world";  Prefix = "bubble"  },   # row 5
    @{ Dir = "ocean_world";  Prefix = "bubble"  }    # row 6
)

$csharp = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class AmbientSlicer {
    static byte[] px; static int W, H, stride;
    static int A(int x, int y) { return px[y * stride + x * 4 + 3]; }

    public static void Load(string path) {
        Bitmap bmp = (Bitmap)Bitmap.FromFile(path);
        W = bmp.Width; H = bmp.Height;
        BitmapData d = bmp.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        stride = d.Stride; px = new byte[stride * H];
        Marshal.Copy(d.Scan0, px, 0, px.Length);
        bmp.UnlockBits(d); bmp.Dispose();
    }
    public static int Width { get { return W; } }
    public static int Height { get { return H; } }

    // Runs of consecutive lines holding at least one pixel above thr.
    public static int[][] Runs(bool vertical, int from, int to, int thr, int minGap) {
        var runs = new List<int[]>();
        int start = -1;
        int limit = vertical ? W : H;
        for (int i = 0; i < limit; i++) {
            bool any = false;
            for (int j = from; j <= to && !any; j++) {
                if (vertical) { if (A(i, j) > thr) any = true; }
                else { if (A(j, i) > thr) any = true; }
            }
            if (any && start < 0) start = i;
            if (!any && start >= 0) { runs.Add(new int[] { start, i - 1 }); start = -1; }
        }
        if (start >= 0) runs.Add(new int[] { start, limit - 1 });
        // Merge runs separated by less than minGap — a cluster of bubbles
        // drawn with a sliver of gap is still one sprite.
        var merged = new List<int[]>();
        foreach (var r in runs) {
            if (merged.Count > 0 && r[0] - merged[merged.Count - 1][1] - 1 < minGap)
                merged[merged.Count - 1][1] = r[1];
            else merged.Add(new int[] { r[0], r[1] });
        }
        return merged.ToArray();
    }

    public static int[] Tight(int x0, int y0, int x1, int y1, int thr) {
        int minx = int.MaxValue, miny = int.MaxValue, maxx = -1, maxy = -1;
        for (int y = y0; y <= y1; y++)
            for (int x = x0; x <= x1; x++)
                if (A(x, y) > thr) {
                    if (x < minx) minx = x; if (x > maxx) maxx = x;
                    if (y < miny) miny = y; if (y > maxy) maxy = y;
                }
        if (maxx < 0) return null;
        return new int[] { minx, miny, maxx - minx + 1, maxy - miny + 1 };
    }

    // Crop, then blur colour AND alpha in premultiplied space. See the
    // .DESCRIPTION for why premultiplied and why alpha is included.
    public static void CropBlurSave(int x, int y, int w, int h, double sigma, string outPath) {
        float[] pr = new float[w * h], pg = new float[w * h], pb = new float[w * h], pa = new float[w * h];
        for (int j = 0; j < h; j++) {
            for (int i = 0; i < w; i++) {
                int sx = Math.Min(W - 1, Math.Max(0, x + i));
                int sy = Math.Min(H - 1, Math.Max(0, y + j));
                int o = sy * stride + sx * 4;
                float a = px[o + 3] / 255f;
                int k = j * w + i;
                pb[k] = px[o] * a; pg[k] = px[o + 1] * a; pr[k] = px[o + 2] * a; pa[k] = px[o + 3];
            }
        }
        if (sigma > 0) {
            int r = (int)Math.Ceiling(sigma * 3.0);
            double[] kern = new double[2 * r + 1];
            double sum = 0;
            for (int i = -r; i <= r; i++) { kern[i + r] = Math.Exp(-(i * i) / (2.0 * sigma * sigma)); sum += kern[i + r]; }
            for (int i = 0; i < kern.Length; i++) kern[i] /= sum;
            pr = Blur(pr, w, h, kern, r); pg = Blur(pg, w, h, kern, r);
            pb = Blur(pb, w, h, kern, r); pa = Blur(pa, w, h, kern, r);
        }
        Bitmap dst = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        BitmapData dd = dst.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        byte[] outBuf = new byte[dd.Stride * h];
        for (int j = 0; j < h; j++) {
            for (int i = 0; i < w; i++) {
                int k = j * w + i;
                float a = pa[k];
                int o = j * dd.Stride + i * 4;
                byte af = Clamp(a);
                outBuf[o + 3] = af;
                // Un-premultiply. Below ~1/255 alpha the colour is
                // meaningless and dividing by it only amplifies noise.
                float inv = a > 0.5f ? 255f / a : 0f;
                outBuf[o] = Clamp(pb[k] * inv);
                outBuf[o + 1] = Clamp(pg[k] * inv);
                outBuf[o + 2] = Clamp(pr[k] * inv);
            }
        }
        Marshal.Copy(outBuf, 0, dd.Scan0, outBuf.Length);
        dst.UnlockBits(dd);
        dst.Save(outPath, ImageFormat.Png);
        dst.Dispose();
    }

    static byte Clamp(float v) { int i = (int)Math.Round(v); return (byte)(i < 0 ? 0 : (i > 255 ? 255 : i)); }

    static float[] Blur(float[] src, int w, int h, double[] k, int r) {
        float[] tmp = new float[w * h], outp = new float[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                double s = 0;
                for (int i = -r; i <= r; i++) { int xx = Math.Min(w - 1, Math.Max(0, x + i)); s += src[y * w + xx] * k[i + r]; }
                tmp[y * w + x] = (float)s;
            }
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                double s = 0;
                for (int i = -r; i <= r; i++) { int yy = Math.Min(h - 1, Math.Max(0, y + i)); s += tmp[yy * w + x] * k[i + r]; }
                outp[y * w + x] = (float)s;
            }
        return outp;
    }
}
"@

Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing
[AmbientSlicer]::Load($sourcePath)

Write-Host "sheet  : $sourcePath  ($([AmbientSlicer]::Width)x$([AmbientSlicer]::Height))"
if (-not $Measure) { Write-Host "out    : $outRootPath\<mode>_world\particles\" }
Write-Host "sigma  : $Sigma   minGap: $MinGap   pad: $Pad`n"

$rows = [AmbientSlicer]::Runs($false, 0, [AmbientSlicer]::Width - 1, $Threshold, 1)
if ($rows.Count -ne $RowTargets.Count) {
    throw "expected $($RowTargets.Count) rows, found $($rows.Count) — check -Threshold"
}

$blurMargin = [int][Math]::Ceiling($Sigma * 3.0) + 1
$counters = @{}
$dirsSeen = @{}

for ($r = 0; $r -lt $rows.Count; $r++) {
    $target = $RowTargets[$r]
    $dir = Join-Path (Join-Path $outRootPath $target.Dir) "particles"
    $key = "$($target.Dir)/$($target.Prefix)"
    if (-not $counters.ContainsKey($key)) { $counters[$key] = 0 }
    if (-not $Measure -and -not $dirsSeen.ContainsKey($dir)) {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
        $dirsSeen[$dir] = $true
    }

    $cols = [AmbientSlicer]::Runs($true, $rows[$r][0], $rows[$r][1], $Threshold, $MinGap)
    if ($target.ContainsKey("Skip") -and $target.Skip) {
        Write-Host ("row {0}  y {1}..{2}  {3} sprites  -> SKIPPED ({4})" -f ($r + 1), $rows[$r][0], $rows[$r][1], $cols.Count, $target.Prefix)
        continue
    }
    Write-Host ("row {0}  y {1}..{2}  {3} sprites  -> {4}/particles/{5}_NN.png" -f ($r + 1), $rows[$r][0], $rows[$r][1], $cols.Count, $target.Dir, $target.Prefix)

    foreach ($c in $cols) {
        $t = [AmbientSlicer]::Tight($c[0], $rows[$r][0], $c[1], $rows[$r][1], $Threshold)
        if ($null -eq $t) { continue }
        $counters[$key]++
        $margin = $Pad + $blurMargin
        $x = $t[0] - $margin; $y = $t[1] - $margin
        $w = $t[2] + $margin * 2; $h = $t[3] + $margin * 2
        $name = "{0}_{1:d2}.png" -f $target.Prefix, $counters[$key]
        Write-Host ("    {0,-14} art {1}x{2}  ->  {3}x{4}" -f $name, $t[2], $t[3], $w, $h)
        if ($Measure) { continue }
        [AmbientSlicer]::CropBlurSave($x, $y, $w, $h, $Sigma, (Join-Path $dir $name))
    }
}

Write-Host ""
foreach ($k in $counters.Keys | Sort-Object) { Write-Host ("  {0}: {1} sprites" -f $k, $counters[$k]) }
if ($Measure) { Write-Host "`n(measure only - nothing written)" }
else { Write-Host "`ndone - update MODE_PARTICLE_* in Main.gd, then let Godot reimport." }
