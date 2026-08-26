<#
.SYNOPSIS
    Fits a whole-ring gate painting onto the 512x512 canvas the game expects,
    and cuts it into the left/right halves Main.gd draws either side of the
    character.

.DESCRIPTION
    Main.gd derives the passable zone from the ring's inner opening measured
    in canvas units - GATE_RING_INNER_TOP/BOTTOM_LOCAL_Y, shared by every
    mode. So a new ring cannot just be dropped in at whatever size it was
    painted: it has to be scaled and placed so its own hole lands on those
    same numbers, or the visible opening and the hit test drift apart.

    This measures the source's hole, solves for the scale and offset that
    put it at the target, and renders it onto 512x512. Then it cuts the
    result at the canvas centre into gate_ring_left.png (drawn in FRONT of
    the character) and gate_ring_right.png (drawn BEHIND it), which is what
    makes the character look like it passes through the ring. The halves
    overlap by a few pixels, matching the existing art, so no seam shows
    where they meet.

    It does not produce gate_ring_base.png - the pedestal is separate art.
    A mode without one simply draws no pedestal (see _draw_gate_base).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/fit_gate_ring.ps1 -Source assets/gates/gate_ring_dream/gate_ring_dream.png -OutDir assets/gates/gate_ring_dream

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/fit_gate_ring.ps1 -Measure assets/gates/gate_ring_ocean
#>
param(
    [string]$Source,
    [string]$OutDir,
    [string]$Measure,
    # Targets below are the canvas-unit numbers in Main.gd; change only
    # alongside GATE_RING_INNER_TOP/BOTTOM_LOCAL_Y.
    [double]$Canvas = 512.0,
    [double]$HoleTop = 128.0,
    [double]$HoleBottom = 395.0,
    [double]$SplitX = 256.0,
    [double]$SplitOverlap = 6.0,
    # For art exported flattened onto a solid backdrop instead of with alpha.
    [switch]$KeyMatte,
    [int]$KeyThreshold = 24
)

$ErrorActionPreference = 'Stop'

# PowerShell cannot Set-Location into this repo's path (the [GGG] segment is
# read as a wildcard), so its working directory is wherever the host left
# it. Relative arguments are resolved against the repo instead of the cwd.
$repo = Split-Path -Parent $PSScriptRoot
function Resolve-RepoPath([string] $p) {
    if ([System.IO.Path]::IsPathRooted($p)) { return $p }
    return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repo, $p))
}
Add-Type -AssemblyName System.Drawing

function Get-BitmapMask($b) {
    $d = $b.LockBits((New-Object System.Drawing.Rectangle 0, 0, $b.Width, $b.Height), [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $buf = [byte[]]::new($d.Stride * $b.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $buf, 0, $buf.Length)
    $o = @{ buf = $buf; w = $b.Width; h = $b.Height; stride = $d.Stride }
    $b.UnlockBits($d)
    return $o
}

function Get-Mask($path) {
    $b = [System.Drawing.Bitmap]::FromFile($path)
    $o = Get-BitmapMask $b
    $b.Dispose()
    return $o
}

# Outer bounds, plus the inner opening taken as the longest clear run down
# the ring's own centre column.
function Get-RingGeometry($m) {
    $x0 = $m.w; $x1 = -1; $y0 = $m.h; $y1 = -1
    for ($y = 0; $y -lt $m.h; $y++) {
        for ($x = 0; $x -lt $m.w; $x++) {
            if ($m.buf[$y * $m.stride + $x * 4 + 3] -gt 8) {
                if ($x -lt $x0) { $x0 = $x }
                if ($x -gt $x1) { $x1 = $x }
                if ($y -lt $y0) { $y0 = $y }
                if ($y -gt $y1) { $y1 = $y }
            }
        }
    }
    if ($x1 -lt 0) { throw "image is fully transparent: nothing to fit" }
    $cx = [int](($x0 + $x1) / 2)
    $top = -1; $bot = -1; $best = 0; $rs = -1
    for ($y = $y0; $y -le $y1 + 1; $y++) {
        $clear = ($y -le $y1) -and ($m.buf[$y * $m.stride + $cx * 4 + 3] -le 8)
        if ($clear) {
            if ($rs -lt 0) { $rs = $y }
        } elseif ($rs -ge 0) {
            $len = $y - $rs
            if ($len -gt $best) { $best = $len; $top = $rs; $bot = $y - 1 }
            $rs = -1
        }
    }
    if ($top -lt 0) { throw "no inner opening found down the ring's centre column" }
    return @{ x0 = $x0; x1 = $x1; y0 = $y0; y1 = $y1; cx = $cx; holeTop = $top; holeBottom = $bot }
}

function Save-Half($src, $path, [double]$keepFrom, [double]$keepTo) {
    $w = [int]$Canvas
    $h = [int]$Canvas
    $out = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $x = [int][math]::Max(0, [math]::Floor($keepFrom))
    $wid = [int][math]::Min($w - $x, [math]::Ceiling($keepTo - $x))
    $rect = New-Object System.Drawing.Rectangle $x, 0, $wid, $h
    $g.DrawImage($src, $rect, $rect, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $out.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $out.Dispose()
    Write-Host ("  wrote {0}  (kept x {1}..{2})" -f (Split-Path $path -Leaf), $x, ($x + $wid - 1))
}

if ($Measure) {
    $dir = Resolve-RepoPath $Measure
    $lp = [System.IO.Path]::Combine($dir, 'gate_ring_left.png')
    $rp = [System.IO.Path]::Combine($dir, 'gate_ring_right.png')
    if (-not ([System.IO.File]::Exists($lp) -and [System.IO.File]::Exists($rp))) {
        throw "need both gate_ring_left.png and gate_ring_right.png in $dir"
    }
    $l = Get-Mask $lp
    $r = Get-Mask $rp
    $w = $l.w; $h = $l.h
    $x0 = $w; $x1 = -1; $y0 = $h; $y1 = -1
    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            $o = $y * $l.stride + $x * 4
            if ($l.buf[$o + 3] -gt 8 -or $r.buf[$o + 3] -gt 8) {
                if ($x -lt $x0) { $x0 = $x }
                if ($x -gt $x1) { $x1 = $x }
                if ($y -lt $y0) { $y0 = $y }
                if ($y -gt $y1) { $y1 = $y }
            }
        }
    }
    $cx = [int](($x0 + $x1) / 2)
    $top = -1; $bot = -1; $best = 0; $rs = -1
    for ($y = $y0; $y -le $y1 + 1; $y++) {
        $o = $y * $l.stride + $cx * 4
        $clear = ($y -le $y1) -and ($l.buf[$o + 3] -le 8 -and $r.buf[$o + 3] -le 8)
        if ($clear) {
            if ($rs -lt 0) { $rs = $y }
        } elseif ($rs -ge 0) {
            $len = $y - $rs
            if ($len -gt $best) { $best = $len; $top = $rs; $bot = $y - 1 }
            $rs = -1
        }
    }
    Write-Host ("{0}  canvas {1}x{2}" -f (Split-Path $dir -Leaf), $w, $h)
    Write-Host ("  combined outer  x {0}..{1}   y {2}..{3}" -f $x0, $x1, $y0, $y1)
    Write-Host ("  inner hole      y {0}..{1}      (target {2}..{3})" -f $top, $bot, $HoleTop, $HoleBottom)
    return
}

if (-not $Source -or -not $OutDir) { throw "Pass -Source <ring.png> -OutDir <folder>, or -Measure <folder>." }

$srcPath = Resolve-RepoPath $Source
$outPath = Resolve-RepoPath $OutDir

# A ring exported without an alpha channel arrives sitting on a flat matte.
# Keying it by colour alone would also punch holes in the art's own dark
# outlines, so instead flood the matte inward from the borders and outward
# from the centre of the hole: only background actually connected to those
# seeds is cleared, and dark pixels enclosed by the art survive.
$srcBitmap = [System.Drawing.Bitmap]::FromFile($srcPath)
if ($KeyMatte) {
    $w = $srcBitmap.Width; $h = $srcBitmap.Height
    $d = $srcBitmap.LockBits((New-Object System.Drawing.Rectangle 0, 0, $w, $h), [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $buf = [byte[]]::new($d.Stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $buf, 0, $buf.Length)
    $stride = $d.Stride
    $seen = [bool[]]::new($w * $h)
    $queue = [System.Collections.Generic.Queue[int]]::new()
    function Test-Matte([int] $idx) {
        $o = [int][math]::Floor($idx / $w) * $stride + ($idx % $w) * 4
        return ($buf[$o] -le $KeyThreshold -and $buf[$o + 1] -le $KeyThreshold -and $buf[$o + 2] -le $KeyThreshold)
    }
    $seeds = New-Object System.Collections.Generic.List[int]
    for ($x = 0; $x -lt $w; $x++) { $seeds.Add($x); $seeds.Add(($h - 1) * $w + $x) }
    for ($y = 0; $y -lt $h; $y++) { $seeds.Add($y * $w); $seeds.Add($y * $w + $w - 1) }
    $seeds.Add([int][math]::Floor($h / 2) * $w + [int][math]::Floor($w / 2))   # inside the ring's hole
    foreach ($s0 in $seeds) {
        if (-not $seen[$s0] -and (Test-Matte $s0)) { $seen[$s0] = $true; $queue.Enqueue($s0) }
    }
    $cleared = 0
    while ($queue.Count -gt 0) {
        $i = $queue.Dequeue()
        $cleared++
        $x = $i % $w; $y = [int][math]::Floor($i / $w)
        $buf[$y * $stride + $x * 4 + 3] = 0
        foreach ($n in @(($i - 1), ($i + 1), ($i - $w), ($i + $w))) {
            if ($n -lt 0 -or $n -ge $w * $h) { continue }
            if ($n -eq $i - 1 -and $x -eq 0) { continue }
            if ($n -eq $i + 1 -and $x -eq $w - 1) { continue }
            if (-not $seen[$n] -and (Test-Matte $n)) { $seen[$n] = $true; $queue.Enqueue($n) }
        }
    }
    [System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $d.Scan0, $buf.Length)
    $srcBitmap.UnlockBits($d)
    Write-Host ("keyed matte: cleared {0} px ({1:P1} of the image) at threshold {2}" -f $cleared, ($cleared / ($w * $h)), $KeyThreshold)
}

$mask = Get-BitmapMask $srcBitmap
$geo = Get-RingGeometry $mask

$scale = ($HoleBottom - $HoleTop) / ($geo.holeBottom - $geo.holeTop)
$ringW = ($geo.x1 - $geo.x0 + 1) * $scale
$ringH = ($geo.y1 - $geo.y0 + 1) * $scale
# Hole on target vertically; ring's outer box centred horizontally.
$dstX = ($Canvas - $ringW) / 2.0
$dstY = $HoleTop - ($geo.holeTop - $geo.y0) * $scale

Write-Host ("source {0}x{1}   ring x {2}..{3} y {4}..{5}   hole y {6}..{7}" -f `
    $mask.w, $mask.h, $geo.x0, $geo.x1, $geo.y0, $geo.y1, $geo.holeTop, $geo.holeBottom)
Write-Host ("scale {0:N4}  ->  ring lands at x {1:N1}..{2:N1}   y {3:N1}..{4:N1}" -f `
    $scale, $dstX, ($dstX + $ringW), $dstY, ($dstY + $ringH))
if ($dstY -lt 0 -or ($dstY + $ringH) -gt $Canvas -or $dstX -lt 0 -or ($dstX + $ringW) -gt $Canvas) {
    Write-Host "  WARNING: the ring overflows the canvas at this scale - it will be clipped."
}

$src = $srcBitmap
$fitted = New-Object System.Drawing.Bitmap ([int]$Canvas), ([int]$Canvas), ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($fitted)
$g.Clear([System.Drawing.Color]::Transparent)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$srcRect = New-Object System.Drawing.RectangleF $geo.x0, $geo.y0, ($geo.x1 - $geo.x0 + 1), ($geo.y1 - $geo.y0 + 1)
$dstRect = New-Object System.Drawing.RectangleF $dstX, $dstY, $ringW, $ringH
$g.DrawImage($src, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$src.Dispose()

Save-Half $fitted ([System.IO.Path]::Combine($outPath, 'gate_ring_left.png')) 0 ($SplitX + $SplitOverlap)
Save-Half $fitted ([System.IO.Path]::Combine($outPath, 'gate_ring_right.png')) ($SplitX - $SplitOverlap) $Canvas
$fitted.Dispose()
