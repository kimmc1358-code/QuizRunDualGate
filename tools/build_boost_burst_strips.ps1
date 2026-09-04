<#
.SYNOPSIS
    Assembles assets/fx/boost_burst/frames/boost_<colour>_1..5.png into the
    per-mode horizontal animation strips the game loads, softening every
    edge on the way out.

.DESCRIPTION
    The opposite direction to every other tool in here: this art arrived as
    five separate frames per mode rather than as one sheet, and Main.gd cuts
    strips at load time with _slice_spritesheet. So the strip is the derived
    file and the loose frames are the source. Both are committed — the
    frames behind a .gdignore so Godot never imports twenty PNGs the game
    does not open.

        boost_red     -> SKY        boost_blue    -> OCEAN
        boost_green   -> JUNGLE     boost_rainbow -> DREAM

    No detection: five frames, one row, source cells all 300x256 already
    registered against each other (frame 1 is a stub at the right edge and
    the flame grows leftward out of it, which is what keeps the head still
    while the tail lengthens). Cells are copied at their full canvas size
    rather than trimmed, because that registration IS the animation — trim
    each frame to its own bounds and the head jitters.

    Two things are baked in, because this project has no runtime shader for
    either:

    -AlphaFloor strips the export halo. Every source frame carries a wide
    field of alpha 1..8 spanning most of the canvas (6000+ px on the peak
    frames) that is invisible on its own but is not nothing once it is
    blurred — it would smear a faint coloured fog out to the cell border and
    then tile visibly against the neighbouring cell. Cut first, blur second.

    -Sigma is the soft edge. Done in PREMULTIPLIED space and over all four
    channels, for the reason spelled out in slice_ambient_sheet.ps1: colour
    alone leaves the silhouette hard, alpha without premultiplying drags the
    transparent pixels' colour inward as a dark fringe.

    Sigma is in SOURCE pixels, and the game draws a 300px cell at about
    108px (boost_burst_size_scale 1.08 of PLAYER_VISUAL_SIZE.x), so it lands
    on screen at roughly a third of its nominal value — 3.0 here is about
    1.1px of softness where the player sees it. Much past that and the white
    chevrons inside the flame start to dissolve along with the outline.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/build_boost_burst_strips.ps1 -Measure

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/build_boost_burst_strips.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/build_boost_burst_strips.ps1 -Sigma 4.5
#>
param(
    [string]$FrameDir = "assets/fx/boost_burst/frames",
    [string]$OutDir = "assets/fx/boost_burst",
    # Alpha at or below this is forced to 0 before anything else. See the
    # .DESCRIPTION — the sources carry an invisible full-canvas halo.
    [int]$AlphaFloor = 8,
    # Edge softness, in source pixels. This is the value the committed
    # strips were built at; change it and rebuild, do not hand-edit a strip.
    [double]$Sigma = 3.0,
    # Report the frames, their content bounds and the resulting strip size,
    # and write nothing.
    [switch]$Measure
)

$ErrorActionPreference = "Stop"

$frameDirPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $FrameDir))
if (-not (Test-Path $frameDirPath)) { throw "Frame folder not found: $frameDirPath" }
$outDirPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutDir))

# Colour name in the source filenames -> the strip Main.gd loads for that
# mode. Order matches the Mode enum only by coincidence of the table below;
# BOOST_BURST_FILE_PER_MODE is what actually binds them.
$Targets = @(
    @{ Colour = "red";     Out = "boost_effect_sky.png"    },
    @{ Colour = "green";   Out = "boost_effect_jungle.png" },
    @{ Colour = "blue";    Out = "boost_effect_ocean.png"  },
    @{ Colour = "rainbow"; Out = "boost_effect_dream.png"  }
)
$FrameCount = 5

$csharp = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class BurstStrip {
    // One loaded frame, already floored and premultiplied.
    public class Frame {
        public int W, H;
        public float[] R, G, B, A;
    }

    public static Frame Load(string path, int alphaFloor) {
        Bitmap bmp = (Bitmap)Bitmap.FromFile(path);
        int w = bmp.Width, h = bmp.Height;
        BitmapData d = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        byte[] px = new byte[d.Stride * h];
        Marshal.Copy(d.Scan0, px, 0, px.Length);
        int stride = d.Stride;
        bmp.UnlockBits(d); bmp.Dispose();

        Frame f = new Frame();
        f.W = w; f.H = h;
        f.R = new float[w * h]; f.G = new float[w * h];
        f.B = new float[w * h]; f.A = new float[w * h];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int o = y * stride + x * 4;
                int a = px[o + 3];
                if (a <= alphaFloor) a = 0;
                float af = a / 255f;
                int k = y * w + x;
                f.B[k] = px[o] * af; f.G[k] = px[o + 1] * af; f.R[k] = px[o + 2] * af;
                f.A[k] = a;
            }
        }
        return f;
    }

    // Tight bounds of pixels above thr, as {x0, y0, x1, y1}, or null.
    public static int[] Bounds(Frame f, int thr) {
        int minx = int.MaxValue, miny = int.MaxValue, maxx = -1, maxy = -1;
        for (int y = 0; y < f.H; y++)
            for (int x = 0; x < f.W; x++)
                if (f.A[y * f.W + x] > thr) {
                    if (x < minx) minx = x; if (x > maxx) maxx = x;
                    if (y < miny) miny = y; if (y > maxy) maxy = y;
                }
        if (maxx < 0) return null;
        return new int[] { minx, miny, maxx, maxy };
    }

    public static void Soften(Frame f, double sigma) {
        if (sigma <= 0) return;
        int r = (int)Math.Ceiling(sigma * 3.0);
        double[] kern = new double[2 * r + 1];
        double sum = 0;
        for (int i = -r; i <= r; i++) { kern[i + r] = Math.Exp(-(i * i) / (2.0 * sigma * sigma)); sum += kern[i + r]; }
        for (int i = 0; i < kern.Length; i++) kern[i] /= sum;
        f.R = Blur(f.R, f.W, f.H, kern, r); f.G = Blur(f.G, f.W, f.H, kern, r);
        f.B = Blur(f.B, f.W, f.H, kern, r); f.A = Blur(f.A, f.W, f.H, kern, r);
    }

    // Lays the frames left to right at their full cell size and writes the
    // strip. Un-premultiplies on the way out.
    public static void Save(Frame[] frames, string outPath) {
        int cw = frames[0].W, ch = frames[0].H;
        int w = cw * frames.Length, h = ch;
        Bitmap dst = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        BitmapData dd = dst.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        byte[] outBuf = new byte[dd.Stride * h];
        for (int c = 0; c < frames.Length; c++) {
            Frame f = frames[c];
            for (int y = 0; y < ch; y++) {
                for (int x = 0; x < cw; x++) {
                    int k = y * cw + x;
                    float a = f.A[k];
                    int o = y * dd.Stride + (c * cw + x) * 4;
                    outBuf[o + 3] = Clamp(a);
                    // Below ~1/255 the colour is meaningless and dividing by
                    // it only amplifies noise.
                    float inv = a > 0.5f ? 255f / a : 0f;
                    outBuf[o] = Clamp(f.B[k] * inv);
                    outBuf[o + 1] = Clamp(f.G[k] * inv);
                    outBuf[o + 2] = Clamp(f.R[k] * inv);
                }
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

foreach ($t in $Targets) {
    $frames = New-Object 'System.Object[]' $FrameCount
    $cellW = 0; $cellH = 0
    for ($i = 1; $i -le $FrameCount; $i++) {
        $path = Join-Path $frameDirPath "boost_$($t.Colour)_$i.png"
        if (-not (Test-Path $path)) { throw "Missing frame: $path" }
        $f = [BurstStrip]::Load($path, $AlphaFloor)
        if ($cellW -eq 0) { $cellW = $f.W; $cellH = $f.H }
        elseif ($f.W -ne $cellW -or $f.H -ne $cellH) {
            # _slice_spritesheet divides the strip into equal cells, so a
            # frame of a different size would silently shift every frame
            # after it.
            throw "boost_$($t.Colour)_$i.png is $($f.W)x$($f.H), expected $($cellW)x$($cellH)"
        }
        if ($Measure) {
            $raw = [BurstStrip]::Bounds($f, 0)
            $solid = [BurstStrip]::Bounds($f, 127)
            $rawText = if ($null -eq $raw) { "empty" } else { "x $($raw[0])..$($raw[2])  y $($raw[1])..$($raw[3])" }
            $solidText = if ($null -eq $solid) { "empty" } else { "x $($solid[0])..$($solid[2])  y $($solid[1])..$($solid[3])" }
            "  frame {0}  {1}x{2}   above floor: {3}   solid (a>127): {4}" -f $i, $f.W, $f.H, $rawText, $solidText
        }
        [BurstStrip]::Soften($f, $Sigma)
        $frames[$i - 1] = $f
    }
    $outPath = Join-Path $outDirPath $t.Out
    if ($Measure) {
        "{0} -> {1}  strip {2}x{3} ({4} cells, sigma {5}, alpha floor {6})" -f $t.Colour, $t.Out, ($cellW * $FrameCount), $cellH, $FrameCount, $Sigma, $AlphaFloor
        ""
        continue
    }
    [BurstStrip]::Save([BurstStrip+Frame[]]$frames, $outPath)
    "wrote {0}  ({1}x{2})" -f $t.Out, ($cellW * $FrameCount), $cellH
}
