<#
.SYNOPSIS
    Cuts assets/fx/fx_small_N.png - the sparkle contact sheet - into the 24
    individual sprites the character trail and the gate-pass burst load.

.DESCRIPTION
    The sheet is one 1536x1024 image holding the same six sparkle shapes
    painted four times over, once per colour:

        row 0  gold    row 1  green    row 2  blue    row 3  pink
        col 0-2  bare 4-point star, large / medium / small
        col 3-5  same star ringed with orbiting dots, large / medium / small

    The sprites are NOT on a tidy 256px grid - the large stars' spikes run
    well past their nominal cell - so this does not slice by arithmetic. It
    finds the four horizontal bands of non-transparent pixels, then the six
    vertical runs inside each band, which lands on the artwork's real
    boundaries whatever the sheet's internal spacing turns out to be.

    Each sprite is cropped to its own tight bounds plus -Pad px of margin,
    so the soft glow around a star is not clipped. The gaps between sprites
    (24px vertically at the tightest) are wider than twice the default pad,
    so no crop ever reaches into a neighbour.

    Output is assets/fx/tap/tap_<colour>_<1-6>.png, the flat naming
    _apply_mode's loader walks. Colours are baked into the art - the game
    never tints these at runtime - which is the whole reason the sheet
    ships four rows instead of one white one.

    Godot writes the .import sidecars itself the next time it opens the
    project; this tool only produces the PNGs.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/slice_tap_fx.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/slice_tap_fx.ps1 -Measure
#>
param(
    [string]$Source = "assets/fx/fx_small_N.png",
    [string]$OutDir = "assets/fx/tap",
    # Row order top-to-bottom. Renaming these renames the output files, and
    # must be matched by TAP_FLARE_COLORS_PER_MODE in Main.gd.
    [string[]]$RowNames = @("gold", "green", "blue", "pink"),
    # Transparent-pixel cutoff for finding the bands. Low enough to keep the
    # faint outer glow, high enough that the sheet's near-zero background
    # does not merge every sprite into one blob.
    [int]$Threshold = 8,
    [int]$Pad = 10,
    # Report the detected layout and write nothing.
    [switch]$Measure
)

$ErrorActionPreference = "Stop"

$sourcePath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Source))
if (-not (Test-Path $sourcePath)) { throw "Source sheet not found: $sourcePath" }
$outPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutDir))

$slicer = @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class TapFxSlicer {
    static byte[] px; static int W, H, stride;
    static int Alpha(int x, int y) { return px[y * stride + x * 4 + 3]; }

    static void Load(string path) {
        Bitmap bmp = (Bitmap)Bitmap.FromFile(path);
        W = bmp.Width; H = bmp.Height;
        BitmapData d = bmp.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        stride = d.Stride;
        px = new byte[stride * H];
        Marshal.Copy(d.Scan0, px, 0, px.Length);
        bmp.UnlockBits(d);
        bmp.Dispose();
    }

    // Runs of consecutive lines that hold at least one pixel above the
    // threshold. Used for rows first, then for columns inside each row.
    static List<int[]> Runs(bool vertical, int from, int to, int thr) {
        var runs = new List<int[]>();
        int start = -1;
        int limit = vertical ? W : H;
        for (int i = 0; i < limit; i++) {
            bool any = false;
            for (int j = from; j <= to && !any; j++) {
                if (vertical) { if (Alpha(i, j) > thr) any = true; }
                else { if (Alpha(j, i) > thr) any = true; }
            }
            if (any && start < 0) start = i;
            if (!any && start >= 0) { runs.Add(new int[] { start, i - 1 }); start = -1; }
        }
        if (start >= 0) runs.Add(new int[] { start, limit - 1 });
        return runs;
    }

    // rect = {x, y, w, h} tight bounds of the artwork inside the given box.
    static int[] Tight(int x0, int y0, int x1, int y1, int thr) {
        int minx = int.MaxValue, miny = int.MaxValue, maxx = -1, maxy = -1;
        for (int y = y0; y <= y1; y++)
            for (int x = x0; x <= x1; x++)
                if (Alpha(x, y) > thr) {
                    if (x < minx) minx = x; if (x > maxx) maxx = x;
                    if (y < miny) miny = y; if (y > maxy) maxy = y;
                }
        if (maxx < 0) return null;
        return new int[] { minx, miny, maxx - minx + 1, maxy - miny + 1 };
    }

    public static string Slice(string source, string outDir, string[] rowNames, int thr, int pad, bool measureOnly) {
        Load(source);
        var log = new System.Text.StringBuilder();
        log.AppendLine(String.Format("sheet {0}x{1}", W, H));

        var rows = Runs(false, 0, W - 1, thr);
        if (rows.Count != rowNames.Length)
            throw new Exception(String.Format("expected {0} colour rows, found {1}", rowNames.Length, rows.Count));

        if (!measureOnly && !System.IO.Directory.Exists(outDir)) System.IO.Directory.CreateDirectory(outDir);
        Bitmap sheet = measureOnly ? null : (Bitmap)Bitmap.FromFile(source);

        for (int r = 0; r < rows.Count; r++) {
            var cols = Runs(true, rows[r][0], rows[r][1], thr);
            log.AppendLine(String.Format("row {0} '{1}'  y {2}..{3}  {4} sprites", r, rowNames[r], rows[r][0], rows[r][1], cols.Count));
            if (cols.Count != 6)
                throw new Exception(String.Format("row {0} ('{1}'): expected 6 sprites, found {2}", r, rowNames[r], cols.Count));

            for (int c = 0; c < cols.Count; c++) {
                int[] t = Tight(cols[c][0], rows[r][0], cols[c][1], rows[r][1], thr);
                // Pad outward for the glow, clamped to the sheet. Neighbour
                // gaps are wider than 2*pad, so this cannot bite into one.
                int x = Math.Max(0, t[0] - pad);
                int y = Math.Max(0, t[1] - pad);
                int w = Math.Min(W - x, t[2] + pad * 2);
                int h = Math.Min(H - y, t[3] + pad * 2);
                string name = String.Format("tap_{0}_{1}.png", rowNames[r], c + 1);
                log.AppendLine(String.Format("    {0,-18} crop ({1},{2}) {3}x{4}", name, x, y, w, h));
                if (measureOnly) continue;

                Bitmap cut = new Bitmap(w, h, PixelFormat.Format32bppArgb);
                using (Graphics g = Graphics.FromImage(cut)) {
                    g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                    g.DrawImage(sheet, new Rectangle(0, 0, w, h), new Rectangle(x, y, w, h), GraphicsUnit.Pixel);
                }
                cut.Save(System.IO.Path.Combine(outDir, name), ImageFormat.Png);
                cut.Dispose();
            }
        }
        if (sheet != null) sheet.Dispose();
        return log.ToString();
    }
}
"@

Add-Type -TypeDefinition $slicer -ReferencedAssemblies System.Drawing

Write-Host "source : $sourcePath"
if (-not $Measure) { Write-Host "out    : $outPath" }
[TapFxSlicer]::Slice($sourcePath, $outPath, $RowNames, $Threshold, $Pad, [bool]$Measure)
if ($Measure) { Write-Host "(measure only - nothing written)" }
else { Write-Host "done - open the project in Godot once so it writes the .import files." }
