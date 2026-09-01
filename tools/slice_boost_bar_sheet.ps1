<#
.SYNOPSIS
    Cuts assets/ui_assets/boost_bar_sheet.png into the four pieces the boost
    gauge draws: the empty track and one fill per bonus tier.

.DESCRIPTION
    Two rows on the sheet:

        row 1  the empty track (navy rim, cream well)   -> track.png
        row 2  three fills, drawn at different lengths  -> fill_none.png
                                                           fill_mid.png
                                                           fill_best.png

    The three fills are grey / yellow / orange, matching the three bonus
    tiers in Main.gd. Their differing lengths on the sheet are just how they
    were painted — the game stretches whichever one it needs to whatever the
    remaining fraction is, so only their colour and their rounded ends
    matter, not how long they happen to be here.

    Nothing is blurred (unlike tools/slice_ambient_sheet.ps1) — this is UI
    and wants to stay crisp. Each piece is cropped to its own tight bounds
    so the rounded end sits flush at the edge, which is what lets
    _draw_horizontal_slice cut a clean cap off it.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/slice_boost_bar_sheet.ps1 -Measure

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/slice_boost_bar_sheet.ps1
#>
param(
    [string]$Source = "assets/ui_assets/boost_bar_sheet.png",
    [string]$OutDir = "assets/ui_assets/boost_bar",
    # 40, not the usual 8: the sheet carries a 1px sliver of near-transparent
    # pixels just under the fills, which at a low cutoff reads as a third row
    # and throws the row/name mapping off by one. Used only to FIND the rows
    # and columns.
    [int]$Threshold = 40,
    # Used to crop each piece once found. Low, so the artwork keeps its soft
    # antialiased outline — cropping at the detection threshold would shave
    # the very edge the rounded caps are made of.
    [int]$CropThreshold = 4,
    # Column runs closer than this are one piece. The fills are far apart,
    # so this only guards against a sprite with an internal gap.
    [int]$MinGap = 24,
    # Height the TRACK is written at; the fills are scaled by the same factor
    # so they still seat in its well. Match BOOST_BAR_HEIGHT in Main.gd.
    #
    # This wants to be the drawn height, not a multiple of it. The sheet
    # paints the track at 142px and the bar draws at 16, and any surplus is
    # minification at draw time — which is what was eating the right-hand
    # rim. Not because the pixels were lost: because a mipmapped
    # non-power-of-two texture drops a fraction of a pixel at every level
    # (687 -> 343 -> 171 ...), so by the level a 3x reduction samples, the
    # right edge has crept half a texel inward. On an 8px cap that is a
    # visible slice of the rim.
    #
    # Cut at the drawn height there is no minification, the GPU stays on mip
    # 0, and the caps land exactly where the art puts them. The middle is
    # STRETCHED horizontally by the 3-slice, which is magnification and
    # perfectly safe. Re-run this after changing BOOST_BAR_HEIGHT.
    [int]$TrackHeight = 16,
    [switch]$Measure
)

$ErrorActionPreference = "Stop"

$sourcePath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Source))
if (-not (Test-Path $sourcePath)) { throw "Sheet not found: $sourcePath" }
$outPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutDir))

# Row index -> the names its pieces take, left to right.
$RowNames = @(
    @("track"),
    @("fill_none", "fill_mid", "fill_best")
)

$csharp = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class BarSlicer {
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

    // Crops, then AREA-AVERAGES down to targetH (0 = no resample).
    //
    // Downscaling here rather than leaving it to the GPU is the point: the
    // sheet is painted ~9x larger than the bar is drawn, and minifying that
    // far at draw time is what makes the painted rim come out ragged. An
    // area average is the right filter for pure downscaling — every source
    // pixel contributes, so nothing is dropped the way point-sampling drops
    // it. Alpha is premultiplied first, or transparent pixels drag their
    // colour into the rim as a fringe.
    public static void CropResize(int x, int y, int w, int h, int targetH, string outPath) {
        int ow = w, oh = h;
        if (targetH > 0 && targetH < h) {
            oh = targetH;
            ow = Math.Max(1, (int)Math.Round(w * (double)targetH / h));
        }
        Bitmap dst = new Bitmap(ow, oh, PixelFormat.Format32bppArgb);
        BitmapData dd = dst.LockBits(new Rectangle(0, 0, ow, oh), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        byte[] outBuf = new byte[dd.Stride * oh];
        for (int j = 0; j < oh; j++) {
            int sy0 = y + (int)Math.Floor(j * (double)h / oh);
            int sy1 = y + (int)Math.Ceiling((j + 1) * (double)h / oh);
            for (int i = 0; i < ow; i++) {
                int sx0 = x + (int)Math.Floor(i * (double)w / ow);
                int sx1 = x + (int)Math.Ceiling((i + 1) * (double)w / ow);
                double sr = 0, sg = 0, sb = 0, sa = 0; int n = 0;
                for (int sy = sy0; sy < Math.Max(sy1, sy0 + 1); sy++) {
                    int cy = Math.Min(H - 1, Math.Max(0, sy));
                    for (int sx = sx0; sx < Math.Max(sx1, sx0 + 1); sx++) {
                        int cx = Math.Min(W - 1, Math.Max(0, sx));
                        int o = cy * stride + cx * 4;
                        double a = px[o + 3] / 255.0;
                        sb += px[o] * a; sg += px[o + 1] * a; sr += px[o + 2] * a; sa += px[o + 3];
                        n++;
                    }
                }
                if (n == 0) n = 1;
                double aAvg = sa / n;
                double inv = aAvg > 0.5 ? 255.0 / aAvg : 0.0;
                int do_ = j * dd.Stride + i * 4;
                outBuf[do_] = Clamp(sb / n * inv);
                outBuf[do_ + 1] = Clamp(sg / n * inv);
                outBuf[do_ + 2] = Clamp(sr / n * inv);
                outBuf[do_ + 3] = Clamp(aAvg);
            }
        }
        Marshal.Copy(outBuf, 0, dd.Scan0, outBuf.Length);
        dst.UnlockBits(dd);
        dst.Save(outPath, ImageFormat.Png);
        dst.Dispose();
    }

    static byte Clamp(double v) { int i = (int)Math.Round(v); return (byte)(i < 0 ? 0 : (i > 255 ? 255 : i)); }
}
"@

Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing
[BarSlicer]::Load($sourcePath)

Write-Host "sheet : $sourcePath  ($([BarSlicer]::Width)x$([BarSlicer]::Height))"
if (-not $Measure) { Write-Host "out   : $outPath" }
Write-Host ""

$rows = [BarSlicer]::Runs($false, 0, [BarSlicer]::Width - 1, $Threshold, 1)
# Reported before validating, so a mismatch shows WHAT was found rather than
# just that the count was wrong.
Write-Host "detected $($rows.Count) row band(s) at threshold ${Threshold}:"
foreach ($bd in $rows) {
    $t = [BarSlicer]::Tight(0, $bd[0], [BarSlicer]::Width - 1, $bd[1], $Threshold)
    Write-Host ("    y {0,4}..{1,-4} h={2,-4} art {3}x{4} at x={5}" -f $bd[0], $bd[1], ($bd[1] - $bd[0] + 1), $t[2], $t[3], $t[0])
}
Write-Host ""
if ($rows.Count -ne $RowNames.Count) {
    throw "expected $($RowNames.Count) rows, found $($rows.Count) — raise -Threshold to ignore faint rows"
}
if (-not $Measure -and -not (Test-Path $outPath)) { New-Item -ItemType Directory -Force $outPath | Out-Null }

# One scale factor for the whole sheet, taken from the track. Scaling each
# piece to its own target height would break the fill/track proportion the
# rim inset in Main.gd depends on.
$trackTight = [BarSlicer]::Tight(0, $rows[0][0], [BarSlicer]::Width - 1, $rows[0][1], $CropThreshold)
$scale = if ($TrackHeight -gt 0) { $TrackHeight / [double]$trackTight[3] } else { 1.0 }
Write-Host ("scale : track {0}px -> {1}px  ({2:P0})`n" -f $trackTight[3], $TrackHeight, $scale)

for ($r = 0; $r -lt $rows.Count; $r++) {
    $cols = [BarSlicer]::Runs($true, $rows[$r][0], $rows[$r][1], $Threshold, $MinGap)
    if ($cols.Count -ne $RowNames[$r].Count) {
        throw "row $($r + 1): expected $($RowNames[$r].Count) pieces, found $($cols.Count)"
    }
    Write-Host ("row {0}  y {1}..{2}  {3} piece(s)" -f ($r + 1), $rows[$r][0], $rows[$r][1], $cols.Count)
    for ($c = 0; $c -lt $cols.Count; $c++) {
        $t = [BarSlicer]::Tight($cols[$c][0], $rows[$r][0], $cols[$c][1], $rows[$r][1], $CropThreshold)
        if ($null -eq $t) { continue }
        $name = "$($RowNames[$r][$c]).png"
        $outH = [int][Math]::Round($t[3] * $scale)
        $outW = [int][Math]::Round($t[2] * $scale)
        # The cap _draw_horizontal_slice should use is the rounded end's
        # radius, which on a capsule is half its height.
        Write-Host ("    {0,-16} {1}x{2}  ->  {3}x{4}   cap = {5}px (h/2)" -f $name, $t[2], $t[3], $outW, $outH, [int][Math]::Round($outH / 2.0))
        if ($Measure) { continue }
        [BarSlicer]::CropResize($t[0], $t[1], $t[2], $t[3], $outH, (Join-Path $outPath $name))
    }
}

if ($Measure) { Write-Host "`n(measure only - nothing written)" }
else { Write-Host "`ndone - let Godot reimport." }
