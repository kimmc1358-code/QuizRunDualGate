<#
.SYNOPSIS
    Builds the Android launcher icons and the Play Store icon from a
    character sprite.

.DESCRIPTION
    Android wants three things and they are not the same picture.

    ADAPTIVE ICON (API 26+, which is every device this ships to). Two layers,
    432x432 each, that the launcher composites and then masks to whatever
    shape it likes — circle, squircle, teardrop. Only the middle 66% of the
    canvas is guaranteed to survive that mask, so the character is fitted
    into a 264px safe circle rather than the full 432. Art that fills the
    canvas gets its edges eaten.

    LEGACY ICON, for the launcher entry and anywhere the adaptive pair is not
    used. One flat 192x192 square with the two layers already composited.

    PLAY STORE ICON, 512x512. Google requires 32-bit PNG with NO
    transparency and applies its own rounding, so this one is fully opaque
    and square-cornered. It is written outside res:// behind a .gdignore —
    it is a store listing asset, not something the game loads, and there is
    no reason to ship it inside the APK.

    The character is trimmed to its own opaque bounds first. The sprites sit
    in a 256x256 cell with a lot of empty space, and centring the cell rather
    than the drawing leaves the icon looking off-centre and small.

    Premultiplied before every resize, as every cut-out in this project must
    be — see CLAUDE.md. Without it the transparent pixels' colour bleeds in
    as a dark fringe around the character.

    -Measure reports what it would produce and writes nothing.

.PARAMETER Character
    Which sprite to use: bird, dragon, shark or unicorn. Default bird — SKY
    is the first mode, the one on the splash, and the red reads best against
    the blue background.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/build_app_icon.ps1 -Measure

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/build_app_icon.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/build_app_icon.ps1 -Character unicorn
#>
param(
    [ValidateSet('bird', 'dragon', 'shark', 'unicorn')]
    [string]$Character = 'bird',
    [switch]$Measure
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing   # Drawing2D lives in this assembly too

$Sources = @{
    bird    = 'characters\bird_v2\bird_happy.png'
    dragon  = 'characters\dragon_green\dragon_happy.png'
    shark   = 'characters\shark_blue\shark_happy.png'
    unicorn = 'characters\unicorn_dream\unicorn_happy.png'
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

# Vertical gradient, sampled from the game's own sky (COLOR_SKY_TOP and
# COLOR_SKY_MID in Main.gd). The bottom stop of that ramp is nearly white and
# washes out at icon size, so this stops at the mid tone.
$TopColor = [System.Drawing.Color]::FromArgb(255, 5, 110, 253)
$BottomColor = [System.Drawing.Color]::FromArgb(255, 94, 202, 252)

$repo = Split-Path -Parent $PSScriptRoot
$src = [System.IO.Path]::Combine($repo, 'assets', $Sources[$Character])
if (-not [System.IO.File]::Exists($src)) { throw "Source not found: $src" }

$outDir = [System.IO.Path]::Combine($repo, 'assets', 'ui_assets', 'icon')
$storeDir = [System.IO.Path]::Combine($repo, 'store')

$sheet = [System.Drawing.Bitmap]::FromFile($src)
Write-Host ("source  {0}  {1}x{2}" -f $Sources[$Character], $sheet.Width, $sheet.Height)

# ---- trim to opaque bounds ----
$minX = $sheet.Width; $minY = $sheet.Height; $maxX = -1; $maxY = -1
for ($y = 0; $y -lt $sheet.Height; $y++) {
    for ($x = 0; $x -lt $sheet.Width; $x++) {
        if ($sheet.GetPixel($x, $y).A -gt 8) {
            if ($x -lt $minX) { $minX = $x }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
}
if ($maxX -lt 0) { throw "Source is fully transparent: $src" }
$trimW = $maxX - $minX + 1
$trimH = $maxY - $minY + 1
Write-Host ("trimmed to {0},{1} {2}x{3}  (cell was {4}x{5})" -f $minX, $minY, $trimW, $trimH, $sheet.Width, $sheet.Height)

$safe = $Adaptive * $SafeFrac
$target = $safe * $CharacterFill
$scale = $target / [Math]::Max($trimW, $trimH)
$drawW = [int][Math]::Round($trimW * $scale)
$drawH = [int][Math]::Round($trimH * $scale)
Write-Host ("adaptive {0}x{0}, safe circle {1:N0}px, character drawn {2}x{3}" -f $Adaptive, $safe, $drawW, $drawH)
Write-Host ("legacy   {0}x{0}   store {1}x{1}" -f $Legacy, $Store)

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

# 캐릭터를 premultiply 한 뒤 크기를 맞춰 투명 캔버스 가운데에 놓는다.
function New-Foreground([int]$size, [int]$w, [int]$h) {
    $pre = New-Object System.Drawing.Bitmap($trimW, $trimH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt $trimH; $y++) {
        for ($x = 0; $x -lt $trimW; $x++) {
            $c = $sheet.GetPixel($minX + $x, $minY + $y)
            $a = $c.A / 255.0
            $pre.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(
                $c.A,
                [int][Math]::Round($c.R * $a),
                [int][Math]::Round($c.G * $a),
                [int][Math]::Round($c.B * $a)))
        }
    }
    $out = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
    $dst = New-Object System.Drawing.Rectangle(
        [int](($size - $w) / 2), [int](($size - $h) / 2), $w, $h)
    $srcR = New-Object System.Drawing.Rectangle(0, 0, $trimW, $trimH)
    $g.DrawImage($pre, $dst, $srcR, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose(); $pre.Dispose()

    # un-premultiply
    for ($y = 0; $y -lt $size; $y++) {
        for ($x = 0; $x -lt $size; $x++) {
            $c = $out.GetPixel($x, $y)
            if ($c.A -eq 0) { continue }
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

$fg = New-Foreground $Adaptive $drawW $drawH
$fgPath = [System.IO.Path]::Combine($outDir, 'icon_foreground_432.png')
$fg.Save($fgPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("wrote {0}" -f $fgPath)

# ---- flat composites ----
# 적응형 두 장을 합친 뒤 목표 크기로 줄인다. 목표 크기에서 바로 합성하면
# 캐릭터가 작은 캔버스에서 리샘플되어 뭉갠다.
function New-Composite([int]$size, [bool]$opaque) {
    $flat = New-Object System.Drawing.Bitmap($Adaptive, $Adaptive, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($flat)
    $g.DrawImage($bg, 0, 0, $Adaptive, $Adaptive)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($fg, 0, 0, $Adaptive, $Adaptive)
    $g.Dispose()

    $out = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g2 = [System.Drawing.Graphics]::FromImage($out)
    $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g2.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g2.DrawImage($flat, 0, 0, $size, $size)
    $g2.Dispose(); $flat.Dispose()

    if ($opaque) {
        for ($y = 0; $y -lt $size; $y++) {
            for ($x = 0; $x -lt $size; $x++) {
                $c = $out.GetPixel($x, $y)
                if ($c.A -ne 255) {
                    $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $c.R, $c.G, $c.B))
                }
            }
        }
    }
    return $out
}

$legacyBmp = New-Composite $Legacy $true
$legacyPath = [System.IO.Path]::Combine($outDir, 'icon_legacy_192.png')
$legacyBmp.Save($legacyPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("wrote {0}" -f $legacyPath)
$legacyBmp.Dispose()

$storeBmp = New-Composite $Store $true
$storePath = [System.IO.Path]::Combine($storeDir, 'play_store_icon_512.png')
$storeBmp.Save($storePath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("wrote {0}  (스토어 등록용 — APK 에는 안 들어간다)" -f $storePath)
$storeBmp.Dispose()

$fg.Dispose(); $bg.Dispose(); $sheet.Dispose()
