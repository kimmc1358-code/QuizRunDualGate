<#
.SYNOPSIS
    Builds the Android launcher icons and the Play Store icon from a
    character sprite.

.DESCRIPTION
    Android wants three things and they are not the same picture, and the
    difference is entirely about **who crops them**.

    ADAPTIVE ICON (API 26+, which is every device this ships to). Two layers,
    432x432 each, that the launcher composites and then masks to whatever
    shape it likes — circle, squircle, teardrop. Only the middle 66% of the
    canvas is guaranteed to survive that mask, so the character is fitted
    into a 264px safe circle rather than the full 432. Art that fills the
    canvas gets its edges eaten.

    LEGACY ICON (192) and PLAY STORE ICON (512) are **never masked**, so the
    safe-circle margin is dead space in them. Sized off the adaptive canvas
    they came out with the character at 52% of the frame — visibly small and
    weak next to other icons in a store listing. They get their own
    composite at $FlatFill instead.

    The Play Store icon must be 32-bit PNG with NO transparency and square
    corners, because Google applies its own rounding. It is written outside
    res:// behind a .gdignore — it is a store listing asset, not something
    the game loads, and there is no reason to ship it inside the APK.

    The character is trimmed to its own opaque bounds first. The sprites sit
    in a 256x256 cell with a lot of empty space, and centring the cell rather
    than the drawing leaves the icon looking off-centre and small.

    Premultiplied before every resize, as every cut-out in this project must
    be — see CLAUDE.md. Without it the transparent pixels' colour bleeds in
    as a dark fringe around the character.

    Enlarging is done as an integer nearest-neighbour step first and only
    then resampled down to the exact size. The sources are pixel art; a
    straight 1.7x bicubic turns every hard pixel edge into a gradient, which
    at icon size reads as a blurry sticker.

    -Measure reports what it would produce and writes nothing.

.PARAMETER Character
    Which mode's sprite to use: bird, dragon, shark or unicorn. Default bird
    — SKY is the first mode, the one on the splash, and the red reads best
    against the blue background.

.PARAMETER Pose
    fly (the in-game motion sheet, default), happy or sad. The happy/sad
    faces are single 256x256 frames; fly is a spritesheet and needs -Frame.

.PARAMETER Frame
    Which cell of the motion sheet, row-major from 0. Default 2 — for the
    bird that is the wings-up pose, which has the most silhouette to read at
    48px. Ignored for happy/sad.

.PARAMETER OutRoot
    Write under this directory instead of the repo, keeping the same
    subpaths. For trying candidates without touching what is committed.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/build_app_icon.ps1 -Measure

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/build_app_icon.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/build_app_icon.ps1 -Character unicorn -Frame 0
#>
param(
    [ValidateSet('bird', 'dragon', 'shark', 'unicorn')]
    [string]$Character = 'bird',
    [ValidateSet('fly', 'happy', 'sad')]
    [string]$Pose = 'fly',
    [int]$Frame = 2,
    [string]$OutRoot = '',
    [switch]$Measure
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing   # Drawing2D lives in this assembly too

# Mirrors MODE_CHARACTER_* in Main.gd. The motion sheets are cell grids read
# left-to-right then top-to-bottom, same as _slice_spritesheet.
$Sources = @{
    bird    = @{ dir = 'characters\bird_v2';      fly = 'bird_fly.png';     grid = @(2, 2); happy = 'bird_happy.png';    sad = 'bird_sad.png' }
    dragon  = @{ dir = 'characters\dragon_green'; fly = 'dragon_fly.png';   grid = @(2, 2); happy = 'dragon_happy.png';  sad = 'dragon_sad.png' }
    shark   = @{ dir = 'characters\shark_blue';   fly = 'shark_swim.png';   grid = @(2, 2); happy = 'shark_happy.png';   sad = 'shark_sad.png' }
    unicorn = @{ dir = 'characters\unicorn_dream'; fly = 'unicorn_run.png'; grid = @(3, 2); happy = 'unicorn_happy.png'; sad = 'unicorn_sad.png' }
}

# Adaptive layers are 432x432 and the launcher masks away everything outside
# the middle 66% — 108dp canvas, 72dp guaranteed visible.
$Adaptive = 432
$SafeFrac = 66.0 / 108.0
# A little inside the safe circle. Filling it exactly leaves the character
# touching the mask edge on a circular launcher.
$CharacterFill = 0.86

$Legacy = 192
$Store = 512
# Nothing masks these two, so the fraction is of the whole square. 0.80
# leaves a margin that reads as deliberate without wasting the frame; the
# adaptive pair works out to an effective 0.86 of what the launcher shows,
# so the three land close enough to look like the same icon.
$FlatFill = 0.80
# Composite the flat pair at store size and downscale from there. Compositing
# straight into 192 resamples the character on a canvas too small to hold its
# detail.
$FlatWork = $Store

# Vertical gradient, sampled from the game's own sky (COLOR_SKY_TOP and
# COLOR_SKY_MID in Main.gd). The bottom stop of that ramp is nearly white and
# washes out at icon size, so this stops at the mid tone.
$TopColor = [System.Drawing.Color]::FromArgb(255, 5, 110, 253)
$BottomColor = [System.Drawing.Color]::FromArgb(255, 94, 202, 252)

$repo = Split-Path -Parent $PSScriptRoot
$info = $Sources[$Character]
$file = if ($Pose -eq 'fly') { $info.fly } elseif ($Pose -eq 'happy') { $info.happy } else { $info.sad }
$src = [System.IO.Path]::Combine($repo, 'assets', $info.dir, $file)
if (-not [System.IO.File]::Exists($src)) { throw "Source not found: $src" }

$dest = if ($OutRoot -ne '') { $OutRoot } else { $repo }
$outDir = [System.IO.Path]::Combine($dest, 'assets', 'ui_assets', 'icon')
$storeDir = [System.IO.Path]::Combine($dest, 'store')

$sheet = [System.Drawing.Bitmap]::FromFile($src)
Write-Host ("source  {0}\{1}  {2}x{3}" -f $info.dir, $file, $sheet.Width, $sheet.Height)

# ---- pick the cell ----
if ($Pose -eq 'fly') {
    $cols = $info.grid[0]; $rows = $info.grid[1]
    if ($Frame -lt 0 -or $Frame -ge $cols * $rows) {
        throw "-Frame $Frame is outside the ${cols}x${rows} sheet (0..$($cols * $rows - 1))"
    }
    $cw = [int]($sheet.Width / $cols)
    $ch = [int]($sheet.Height / $rows)
    $cellX = ($Frame % $cols) * $cw
    $cellY = [int][Math]::Floor($Frame / $cols) * $ch
    Write-Host ("pose    fly frame {0} of {1}x{2}, cell {3}x{4} at {5},{6}" -f $Frame, $cols, $rows, $cw, $ch, $cellX, $cellY)
} else {
    $cw = $sheet.Width; $ch = $sheet.Height; $cellX = 0; $cellY = 0
    Write-Host ("pose    {0}, single frame" -f $Pose)
}

# ---- trim to opaque bounds within that cell ----
$minX = $cw; $minY = $ch; $maxX = -1; $maxY = -1
for ($y = 0; $y -lt $ch; $y++) {
    for ($x = 0; $x -lt $cw; $x++) {
        if ($sheet.GetPixel($cellX + $x, $cellY + $y).A -gt 8) {
            if ($x -lt $minX) { $minX = $x }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
}
if ($maxX -lt 0) { throw "That cell is fully transparent: $src frame $Frame" }
$trimW = $maxX - $minX + 1
$trimH = $maxY - $minY + 1
Write-Host ("trimmed to {0},{1} {2}x{3}  (cell was {4}x{5})" -f $minX, $minY, $trimW, $trimH, $cw, $ch)

$safe = $Adaptive * $SafeFrac
$adaptiveMax = $safe * $CharacterFill
$flatMax = $FlatWork * $FlatFill
Write-Host ("adaptive {0}x{0}, safe circle {1:N0}px, character {2:N0}px ({3:P0} of the visible area)" -f `
        $Adaptive, $safe, $adaptiveMax, ($adaptiveMax / $safe))
Write-Host ("flat     store {0}x{0} + legacy {1}x{1}, character {2:P0} of the square" -f $Store, $Legacy, $FlatFill)

if ($Measure) {
    $sheet.Dispose()
    Write-Host ""
    Write-Host "-Measure: nothing written."
    return
}

foreach ($d in @($outDir, $storeDir)) {
    if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Force -Path $d) }
}

function New-Gradient([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect, $TopColor, $BottomColor, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillRectangle($brush, $rect)
    $brush.Dispose(); $g.Dispose()
    return $bmp
}

# 잘라낸 캐릭터를 premultiply 해 둔다. 크기를 바꾸는 모든 곳이 이걸 쓴다.
$pre = New-Object System.Drawing.Bitmap($trimW, $trimH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $trimH; $y++) {
    for ($x = 0; $x -lt $trimW; $x++) {
        $c = $sheet.GetPixel($cellX + $minX + $x, $cellY + $minY + $y)
        $a = $c.A / 255.0
        $pre.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(
                $c.A,
                [int][Math]::Round($c.R * $a),
                [int][Math]::Round($c.G * $a),
                [int][Math]::Round($c.B * $a)))
    }
}

# 확대할 때는 정수배 nearest 를 먼저 밟는다. 픽셀아트를 곧장 bicubic 으로 늘리면
# 픽셀 경계가 전부 그라디언트가 되어 아이콘 크기에서 흐릿한 스티커처럼 보인다.
function New-Scaled([int]$w, [int]$h) {
    $srcBmp = $pre
    $temp = $null
    if ($w -gt $trimW) {
        $mult = [int][Math]::Ceiling($w / [double]$trimW)
        $temp = New-Object System.Drawing.Bitmap(($trimW * $mult), ($trimH * $mult), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gt = [System.Drawing.Graphics]::FromImage($temp)
        $gt.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $gt.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $gt.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $gt.DrawImage($pre, 0, 0, ($trimW * $mult), ($trimH * $mult))
        $gt.Dispose()
        $srcBmp = $temp
    }
    $out = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($srcBmp, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)),
        (New-Object System.Drawing.Rectangle(0, 0, $srcBmp.Width, $srcBmp.Height)),
        [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    if ($temp -ne $null) { $temp.Dispose() }
    return $out
}

# 투명 캔버스 한가운데에 캐릭터를 놓은 전경 레이어. maxDim 은 긴 변 기준.
function New-Foreground([int]$size, [double]$maxDim) {
    $scale = $maxDim / [Math]::Max($trimW, $trimH)
    $w = [int][Math]::Round($trimW * $scale)
    $h = [int][Math]::Round($trimH * $scale)
    $scaled = New-Scaled $w $h

    $out = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
    $g.DrawImage($scaled, [int](($size - $w) / 2), [int](($size - $h) / 2), $w, $h)
    $g.Dispose(); $scaled.Dispose()

    # un-premultiply
    for ($y = 0; $y -lt $size; $y++) {
        for ($x = 0; $x -lt $size; $x++) {
            $c = $out.GetPixel($x, $y)
            if ($c.A -eq 0 -or $c.A -eq 255) { continue }
            $f = 255.0 / $c.A
            $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($c.A,
                    [int][Math]::Min(255, [Math]::Round($c.R * $f)),
                    [int][Math]::Min(255, [Math]::Round($c.G * $f)),
                    [int][Math]::Min(255, [Math]::Round($c.B * $f))))
        }
    }
    return $out
}

# ---- adaptive pair ----
$bg = New-Gradient $Adaptive
$bgPath = [System.IO.Path]::Combine($outDir, 'icon_background_432.png')
$bg.Save($bgPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("wrote {0}" -f $bgPath)

$fg = New-Foreground $Adaptive $adaptiveMax
$fgPath = [System.IO.Path]::Combine($outDir, 'icon_foreground_432.png')
$fg.Save($fgPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("wrote {0}" -f $fgPath)
$fg.Dispose(); $bg.Dispose()

# ---- flat composites: legacy and store ----
# 마스킹이 없으니 안전원 여백을 뺀 별도 합성이다.
$flatBg = New-Gradient $FlatWork
$flatFg = New-Foreground $FlatWork $flatMax
$flat = New-Object System.Drawing.Bitmap($FlatWork, $FlatWork, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($flat)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($flatBg, 0, 0, $FlatWork, $FlatWork)
$g.DrawImage($flatFg, 0, 0, $FlatWork, $FlatWork)
$g.Dispose()
$flatBg.Dispose(); $flatFg.Dispose()

# 스토어 아이콘은 완전 불투명이어야 한다. 리샘플 가장자리에 반투명이 남을 수
# 있어 마지막에 알파를 못박는다.
function Set-Opaque([System.Drawing.Bitmap]$bmp) {
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.A -ne 255) { $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $c.R, $c.G, $c.B)) }
        }
    }
}

function New-Downscale([System.Drawing.Bitmap]$from, [int]$size) {
    $out = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g2 = [System.Drawing.Graphics]::FromImage($out)
    $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g2.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g2.DrawImage($from, 0, 0, $size, $size)
    $g2.Dispose()
    return $out
}

$legacyBmp = New-Downscale $flat $Legacy
Set-Opaque $legacyBmp
$legacyPath = [System.IO.Path]::Combine($outDir, 'icon_legacy_192.png')
$legacyBmp.Save($legacyPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("wrote {0}" -f $legacyPath)
$legacyBmp.Dispose()

$storeBmp = if ($Store -eq $FlatWork) { $flat } else { New-Downscale $flat $Store }
Set-Opaque $storeBmp
$storePath = [System.IO.Path]::Combine($storeDir, 'play_store_icon_512.png')
$storeBmp.Save($storePath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("wrote {0}  (스토어 등록용 — APK 에는 안 들어간다)" -f $storePath)

$storeBmp.Dispose()
if ($Store -ne $FlatWork) { $flat.Dispose() }
$pre.Dispose(); $sheet.Dispose()
