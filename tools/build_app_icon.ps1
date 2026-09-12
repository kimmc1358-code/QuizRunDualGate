<#
.SYNOPSIS
    Builds the Android launcher icons and the Play Store icon: a character
    flying through its mode's gate ring.

.DESCRIPTION
    Android wants three things and they are not the same picture, and the
    difference is entirely about **who crops them**.

    ADAPTIVE ICON (API 26+, which is every device this ships to). Two layers,
    432x432 each, that the launcher composites and then masks to whatever
    shape it likes — circle, squircle, teardrop. What a launcher shows is the
    middle 72dp of the 108dp layer (288px), and only a 66dp circle (264px) is
    guaranteed to survive every mask shape. The composition is sized against
    that safe circle. Art that fills the canvas gets its edges eaten.

    LEGACY ICON (192) and PLAY STORE ICON (512) are **never masked**, so the
    whole square plays the part of the launcher's 72dp viewport. The same
    composition is scaled by Store/Viewport for them, so the store icon looks
    like what a launcher shows rather than like the raw 108dp layer with its
    margins.

    The Play Store icon must be 32-bit PNG with NO transparency and square
    corners, because Google applies its own rounding. It is written outside
    res:// behind a .gdignore — it is a store listing asset, not something
    the game loads, and there is no reason to ship it inside the APK.

    THE GATE. The gate is the game's signature, so the icon shows the
    character passing through one, with the same trick the game uses: the
    ring is two halves (tools/fit_gate_ring.ps1 cuts them), the right one
    drawn behind the character and the left one in front. That is what makes
    the character read as being inside the ring instead of pasted over it.
    Each character gets its own mode's ring.

    The layout was picked from three candidates rendered at launcher sizes
    and masked like a launcher does: the ring filling the safe circle with
    the character in its hole (this one, $GateFill 1.00 and
    $GatedCharacterFill 0.56), a larger character bursting out of a smaller
    ring, and the ring blown up into the icon's rim. The price of this one is
    the character: about half the size it had alone. -NoGate builds the old
    character-only icon.

    MONOCHROME LAYER. Android 13+ "themed icons" replace the icon with a
    single-colour silhouette tinted to the wallpaper, taken from a third
    adaptive layer. Left unset, Godot fills that layer with its own logo, so
    a themed launcher showed a Godot robot until this was added. It keeps the
    ring but uses a smaller character than the colour icon
    ($MonoCharacterFill 0.42 against 0.56). A silhouette loses what makes
    the bird a bird - the red, the eye, the beak - and at the colour icon's
    size it fills the ring's hole, so the two melted into one egg shape
    with a hairline through it. With sky between them the ring reads as a
    ring again. A gap of $MonoGap px is still cut where they overlap, the
    front half of the ring into the character and the character into the
    back half. Four variants were compared tinted like a themed launcher
    (full-size bird with a 6px or 14px gap, the small bird, the bird
    alone); none reads as clearly as the colour icon, and this one is the
    only one where the gate is still recognisable.

    PROJECT ICON. icon.png at the project root is application/config/icon:
    the editor's project-list icon and the desktop window icon, 256px from
    the store composite. Left alone it was Godot's default logo.

    The character is trimmed to its own opaque bounds first. The sprites sit
    in a 256x256 cell with a lot of empty space, and centring the cell rather
    than the drawing leaves the icon looking off-centre and small.

    Everything is composited in premultiplied alpha (Format32bppPArgb, which
    GDI+ resamples and blends premultiplied), as every cut-out in this
    project must be — see CLAUDE.md. Without it the transparent pixels'
    colour bleeds in as a dark fringe around the character and the ring.

    Enlarging is done as an integer nearest-neighbour step first and only
    then resampled down to the exact size. The sources are pixel art; a
    straight 1.7x bicubic turns every hard pixel edge into a gradient, which
    at icon size reads as a blurry sticker.

    -Measure reports what it would produce, including how far the drawing
    reaches against the safe circle, and writes nothing.

.PARAMETER Character
    Which mode's sprite (and gate) to use: bird, dragon, shark or unicorn.
    Default bird — SKY is the first mode, the one on the splash, and the red
    reads best against the blue background.

.PARAMETER Pose
    fly (the in-game motion sheet, default), happy or sad. The happy/sad
    faces are single 256x256 frames; fly is a spritesheet and needs -Frame.

.PARAMETER Frame
    Which cell of the motion sheet, row-major from 0. Default 2 — for the
    bird that is the wings-up pose, which has the most silhouette to read at
    48px. Ignored for happy/sad.

.PARAMETER NoGate
    Character alone on the gradient, the icon before the gate was added.

.PARAMETER GateFill
    The ring's longer side as a fraction of the safe circle. 1.00 fills it —
    the ring is taller than wide and its bounding-box corners are empty, so
    it still clears a circular mask.

.PARAMETER GatedCharacterFill
    The character's longer side as a fraction of the safe circle, when there
    is a gate. 0.56 fits it to the ring's hole; much larger and it spills
    over the ring into the other candidate's layout.

.PARAMETER OutRoot
    Write under this directory instead of the repo, keeping the same
    subpaths. For trying candidates without touching what is committed.

.PARAMETER TopRgb
    "r,g,b" for the top of the background gradient instead of the game's
    sky. -BottomRgb is the bottom stop. Used for the per-mode leaderboard
    icons, which take each mode card's colours.

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
    [switch]$NoGate,
    [double]$GateFill = 1.00,
    [double]$GatedCharacterFill = 0.56,
    [double]$MonoCharacterFill = 0.42,
    [int]$MonoGap = 6,
    [switch]$MonoNoGate,
    [string]$OutRoot = '',
    [string]$TopRgb = '',
    [string]$BottomRgb = '',
    [switch]$Measure
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing   # Drawing2D lives in this assembly too
$PA = [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb

# Mirrors MODE_CHARACTER_* in Main.gd. The motion sheets are cell grids read
# left-to-right then top-to-bottom, same as _slice_spritesheet.
$Sources = @{
    bird    = @{ dir = 'characters\bird_v2';      fly = 'bird_fly.png';     grid = @(2, 2); happy = 'bird_happy.png';    sad = 'bird_sad.png' }
    dragon  = @{ dir = 'characters\dragon_green'; fly = 'dragon_fly.png';   grid = @(2, 2); happy = 'dragon_happy.png';  sad = 'dragon_sad.png' }
    shark   = @{ dir = 'characters\shark_blue';   fly = 'shark_swim.png';   grid = @(2, 2); happy = 'shark_happy.png';   sad = 'shark_sad.png' }
    unicorn = @{ dir = 'characters\unicorn_dream'; fly = 'unicorn_run.png'; grid = @(3, 2); happy = 'unicorn_happy.png'; sad = 'unicorn_sad.png' }
}
# Mirrors MODE_GATE_DIR in Main.gd: each character flies through its own mode's ring.
$Gates = @{
    bird    = 'gates\gate_ring'
    dragon  = 'gates\gate_ring_jungle'
    shark   = 'gates\gate_ring_ocean'
    unicorn = 'gates\gate_ring_dream'
}
# Centre of the ring's hole on its 512 canvas. fit_gate_ring.ps1 places every
# mode's hole at GATE_RING_INNER_TOP/BOTTOM_LOCAL_Y (128..395) and splits the
# halves at x 256, so one pair of numbers serves all four rings.
$HoleX = 256.0
$HoleY = (128.0 + 395.0) / 2.0

$Adaptive = 432
$Viewport = 288   # 72dp of the 108dp layer: what a launcher actually shows
$Safe = 264       # 66dp: the circle no mask shape cuts into
# NoGate only. A little inside the safe circle — filling it exactly leaves the
# character touching the mask edge on a circular launcher.
$CharacterFill = 0.86

$Legacy = 192
$Store = 512
# NoGate only: the character alone, as a fraction of the whole square.
$FlatFill = 0.80
# Composite the flat pair at store size and downscale from there. Compositing
# straight into 192 resamples the art on a canvas too small to hold its detail.
$FlatWork = $Store

# Vertical gradient, sampled from the game's own sky (COLOR_SKY_TOP and
# COLOR_SKY_MID in Main.gd). The bottom stop of that ramp is nearly white and
# washes out at icon size, so this stops at the mid tone.
$TopColor = [System.Drawing.Color]::FromArgb(255, 5, 110, 253)
$BottomColor = [System.Drawing.Color]::FromArgb(255, 94, 202, 252)
# -TopRgb / -BottomRgb "r,g,b" swap the gradient, for the per-mode leaderboard
# icons: four of them sit in one list, and the mode cards' own colours
# (CARD_FILL_TOP/BOTTOM in ModeSelectScreen.gd) tell them apart at a glance.
function ConvertTo-Color([string]$rgb) {
    $c = $rgb.Split(',') | ForEach-Object { [int]$_.Trim() }
    if ($c.Count -ne 3) { throw "expected r,g,b but got '$rgb'" }
    return [System.Drawing.Color]::FromArgb(255, $c[0], $c[1], $c[2])
}
if ($TopRgb) { $TopColor = ConvertTo-Color $TopRgb }
if ($BottomRgb) { $BottomColor = ConvertTo-Color $BottomRgb }

$repo = Split-Path -Parent $PSScriptRoot
$info = $Sources[$Character]
$file = if ($Pose -eq 'fly') { $info.fly } elseif ($Pose -eq 'happy') { $info.happy } else { $info.sad }
$src = [System.IO.Path]::Combine($repo, 'assets', $info.dir, $file)
if (-not [System.IO.File]::Exists($src)) { throw "Source not found: $src" }

$dest = if ($OutRoot -ne '') { $OutRoot } else { $repo }
$outDir = [System.IO.Path]::Combine($dest, 'assets', 'ui_assets', 'icon')
$storeDir = [System.IO.Path]::Combine($dest, 'store')

function Load-P([string]$path) {
    $b = [System.Drawing.Bitmap]::FromFile($path)
    $r = New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height)
    $p = $b.Clone($r, $PA)
    $b.Dispose()
    return $p
}

# Opaque bounds (alpha > 8) within a region, sampling every $step pixels.
function Get-Bounds($bmp, [int]$x0, [int]$y0, [int]$w, [int]$h, [int]$step) {
    $minX = $w; $minY = $h; $maxX = -1; $maxY = -1
    for ($y = 0; $y -lt $h; $y += $step) {
        for ($x = 0; $x -lt $w; $x += $step) {
            if ($bmp.GetPixel($x0 + $x, $y0 + $y).A -gt 8) {
                if ($x -lt $minX) { $minX = $x }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    return @($minX, $minY, $maxX, $maxY)
}

# 확대할 때는 정수배 nearest 를 먼저 밟는다. 픽셀아트를 곧장 bicubic 으로 늘리면
# 픽셀 경계가 전부 그라디언트가 되어 아이콘 크기에서 흐릿한 스티커처럼 보인다.
function New-Scaled($source, [int]$w, [int]$h) {
    $s = $source; $tmp = $null
    if ($w -gt $source.Width -or $h -gt $source.Height) {
        $mult = [int][Math]::Ceiling([Math]::Max($w / [double]$source.Width, $h / [double]$source.Height))
        $tmp = New-Object System.Drawing.Bitmap(($source.Width * $mult), ($source.Height * $mult), $PA)
        $gt = [System.Drawing.Graphics]::FromImage($tmp)
        $gt.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $gt.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $gt.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
        $gt.DrawImage($source, 0, 0, $tmp.Width, $tmp.Height)
        $gt.Dispose()
        $s = $tmp
    }
    $out = New-Object System.Drawing.Bitmap($w, $h, $PA)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($s, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)),
        (New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)),
        [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    if ($tmp -ne $null) { $tmp.Dispose() }
    return $out
}

function New-Gradient([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, $PA)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect, $TopColor, $BottomColor, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillRectangle($brush, $rect)
    $brush.Dispose(); $g.Dispose()
    return $bmp
}

function New-Transparent([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, $PA)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
    $g.Dispose()
    return $bmp
}

$sheet = Load-P $src
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
$bb = Get-Bounds $sheet $cellX $cellY $cw $ch 1
if ($bb[2] -lt 0) { throw "That cell is fully transparent: $src frame $Frame" }
$trimW = $bb[2] - $bb[0] + 1
$trimH = $bb[3] - $bb[1] + 1
$charTrim = $sheet.Clone((New-Object System.Drawing.Rectangle(($cellX + $bb[0]), ($cellY + $bb[1]), $trimW, $trimH)), $PA)
Write-Host ("trimmed to {0},{1} {2}x{3}  (cell was {4}x{5})" -f $bb[0], $bb[1], $trimW, $trimH, $cw, $ch)

# ---- the gate ----
if (-not $NoGate) {
    $gateDir = [System.IO.Path]::Combine($repo, 'assets', $Gates[$Character])
    $ringFront = Load-P ([System.IO.Path]::Combine($gateDir, 'gate_ring_left.png'))    # in front of the character
    $ringBack = Load-P ([System.IO.Path]::Combine($gateDir, 'gate_ring_right.png'))    # behind it
    # Every second pixel: the bounds only place and size the ring, and a
    # 1px error on the 512 canvas is far below what survives the downscale.
    $fb = Get-Bounds $ringFront 0 0 $ringFront.Width $ringFront.Height 2
    $kb = Get-Bounds $ringBack 0 0 $ringBack.Width $ringBack.Height 2
    $rx0 = [Math]::Min($fb[0], $kb[0]); $ry0 = [Math]::Min($fb[1], $kb[1])
    $rx1 = [Math]::Max($fb[2], $kb[2]); $ry1 = [Math]::Max($fb[3], $kb[3])
    $ringW = $rx1 - $rx0 + 1; $ringH = $ry1 - $ry0 + 1
    $ringCX = ($rx0 + $rx1) / 2.0; $ringCY = ($ry0 + $ry1) / 2.0
    Write-Host ("gate    {0}  ring {1}x{2}, centred {3},{4}; hole centre {5},{6}" -f $Gates[$Character], $ringW, $ringH, $ringCX, $ringCY, $HoleX, $HoleY)
}

# Where each piece goes on one canvas, with the pieces already scaled. $unit
# is the safe circle for the adaptive layer and Store * Safe / Viewport for
# the flat pair, so both hold the same picture. The foreground stacks the
# pieces; the monochrome layer needs them apart. One function places them for
# both, so the two layers cannot drift out of register.
function Get-Placement([int]$size, [double]$unit, [double]$charFill, [bool]$gate) {
    if (-not $gate) {
        $maxDim = if ($size -eq $Adaptive) { $Safe * $CharacterFill } else { $FlatWork * $FlatFill }
        $s = $maxDim / [Math]::Max($trimW, $trimH)
        $w = [int][Math]::Round($trimW * $s); $h = [int][Math]::Round($trimH * $s)
        return @{ gate = $false; char = (New-Scaled $charTrim $w $h); w = $w; h = $h;
            cx = [int](($size - $w) / 2); cy = [int](($size - $h) / 2) }
    }
    # The ring is centred by its own bounds; the character by the hole.
    $k = ($GateFill * $unit) / [Math]::Max($ringW, $ringH)
    $cs = [int][Math]::Round($ringFront.Width * $k)
    $ox = [int][Math]::Round($size / 2.0 - $ringCX * $k)
    $oy = [int][Math]::Round($size / 2.0 - $ringCY * $k)
    $s = ($charFill * $unit) / [Math]::Max($trimW, $trimH)
    $w = [int][Math]::Round($trimW * $s); $h = [int][Math]::Round($trimH * $s)
    $hx = $ox + $HoleX * $k
    $hy = $oy + $HoleY * $k
    return @{ gate = $true;
        back = (New-Scaled $ringBack $cs $cs); front = (New-Scaled $ringFront $cs $cs);
        ox = $ox; oy = $oy; cs = $cs;
        char = (New-Scaled $charTrim $w $h); w = $w; h = $h;
        cx = [int][Math]::Round($hx - $w / 2.0); cy = [int][Math]::Round($hy - $h / 2.0) }
}

function Remove-Placement($p) {
    $p.char.Dispose()
    if ($p.gate) { $p.back.Dispose(); $p.front.Dispose() }
}

function New-Foreground([int]$size, [double]$unit) {
    $p = Get-Placement $size $unit $GatedCharacterFill (-not $NoGate)
    $out = New-Transparent $size
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    if ($p.gate) { $g.DrawImage($p.back, $p.ox, $p.oy, $p.cs, $p.cs) }
    $g.DrawImage($p.char, $p.cx, $p.cy, $p.w, $p.h)
    if ($p.gate) { $g.DrawImage($p.front, $p.ox, $p.oy, $p.cs, $p.cs) }
    $g.Dispose()
    Remove-Placement $p
    return $out
}

# ---- monochrome layer ----
# Gap between overlapping pieces, in pixels of the 432 canvas. A launcher
# shows the 288px viewport at 48px, so 6px lands at about one pixel there —
# any thinner and the pieces fuse at the size most people see the icon.
# The gap itself is the -MonoGap parameter.

function New-Placed([int]$size, $img, [int]$x, [int]$y, [int]$w, [int]$h) {
    $c = New-Transparent $size
    $g = [System.Drawing.Graphics]::FromImage($c)
    $g.DrawImage($img, $x, $y, $w, $h)
    $g.Dispose()
    return $c
}

# The piece grown outward by $r px: drawn again at every offset on rings
# 1..$r, which for a silhouette is a dilation.
function New-Dilated([int]$size, $img, [int]$x, [int]$y, [int]$w, [int]$h, [int]$r) {
    $c = New-Transparent $size
    $g = [System.Drawing.Graphics]::FromImage($c)
    $g.DrawImage($img, $x, $y, $w, $h)
    for ($rr = 1; $rr -le $r; $rr++) {
        $n = 8 * $rr
        for ($i = 0; $i -lt $n; $i++) {
            $a = 2.0 * [Math]::PI * $i / $n
            $dx = [int][Math]::Round([Math]::Cos($a) * $rr)
            $dy = [int][Math]::Round([Math]::Sin($a) * $rr)
            $g.DrawImage($img, $x + $dx, $y + $dy, $w, $h)
        }
    }
    $g.Dispose()
    return $c
}

function Get-Alpha([System.Drawing.Bitmap]$bmp) {
    $rect = New-Object System.Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $PA)
    $bytes = New-Object byte[] ($data.Stride * $bmp.Height)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $bmp.UnlockBits($data)
    $n = $bmp.Width * $bmp.Height
    $alpha = New-Object byte[] $n
    for ($i = 0; $i -lt $n; $i++) { $alpha[$i] = $bytes[$i * 4 + 3] }
    return ,$alpha
}

function New-Monochrome([int]$size, [double]$unit) {
    $fill = if ($MonoCharacterFill -gt 0) { $MonoCharacterFill } else { $GatedCharacterFill }
    $p = Get-Placement $size $unit $fill ((-not $NoGate) -and (-not $MonoNoGate))
    $n = $size * $size
    $mono = New-Object byte[] $n
    $charC = New-Placed $size $p.char $p.cx $p.cy $p.w $p.h
    $aChar = Get-Alpha $charC
    $charC.Dispose()
    if (-not $p.gate) {
        $mono = $aChar
    } else {
        $frontC = New-Placed $size $p.front $p.ox $p.oy $p.cs $p.cs
        $backC = New-Placed $size $p.back $p.ox $p.oy $p.cs $p.cs
        $frontD = New-Dilated $size $p.front $p.ox $p.oy $p.cs $p.cs $MonoGap
        $charD = New-Dilated $size $p.char $p.cx $p.cy $p.w $p.h $MonoGap
        $aFront = Get-Alpha $frontC; $aBack = Get-Alpha $backC
        $dFront = Get-Alpha $frontD; $dChar = Get-Alpha $charD
        $frontC.Dispose(); $backC.Dispose(); $frontD.Dispose(); $charD.Dispose()
        for ($i = 0; $i -lt $n; $i++) {
            # Front ring whole; character minus a gap round the front ring;
            # back ring minus a gap round the character.
            $m = [int]$aFront[$i]
            $c = [int]([int]$aChar[$i] * (255 - [int]$dFront[$i]) / 255)
            $b = [int]([int]$aBack[$i] * (255 - [int]$dChar[$i]) / 255)
            if ($c -gt $m) { $m = $c }
            if ($b -gt $m) { $m = $b }
            $mono[$i] = [byte]$m
        }
    }
    Remove-Placement $p
    # White, premultiplied: blue = green = red = alpha. Only the alpha matters,
    # since the launcher tints the layer, but white keeps it visible in a viewer.
    $out = New-Object System.Drawing.Bitmap($size, $size, $PA)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $data = $out.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $PA)
    $bytes = New-Object byte[] ($n * 4)
    for ($i = 0; $i -lt $n; $i++) {
        $v = $mono[$i]; $j = $i * 4
        $bytes[$j] = $v; $bytes[$j + 1] = $v; $bytes[$j + 2] = $v; $bytes[$j + 3] = $v
    }
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    $out.UnlockBits($data)
    return $out
}

# How far the drawing reaches from the centre, in pixels of that canvas.
function Get-Reach($bmp) {
    $cx = ($bmp.Width - 1) / 2.0; $cy = ($bmp.Height - 1) / 2.0
    $best = 0.0
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) {
            if ($bmp.GetPixel($x, $y).A -gt 8) {
                $d = [Math]::Sqrt(($x - $cx) * ($x - $cx) + ($y - $cy) * ($y - $cy))
                if ($d -gt $best) { $best = $d }
            }
        }
    }
    return $best
}

$flatUnit = $Store * ($Safe / [double]$Viewport)
$fg = New-Foreground $Adaptive $Safe
$reach = Get-Reach $fg
Write-Host ("adaptive {0}x{0}: drawing reaches {1:N1}px from the centre — safe circle {2}px, launcher viewport {3}px" -f `
        $Adaptive, $reach, ($Safe / 2), ($Viewport / 2))
# 1px of tolerance: the reach is taken at alpha > 8, so it lands on the
# anti-aliased fringe. The committed ring's gem tips sit on the safe circle
# with half a pixel of that fringe past it, which no mask visibly cuts.
if ($reach -gt $Safe / 2.0 + 1.0) {
    Write-Warning ("the drawing passes the safe circle by {0:N1}px — some launcher masks will cut it" -f ($reach - $Safe / 2.0))
}

if ($Measure) {
    $fg.Dispose(); $charTrim.Dispose(); $sheet.Dispose()
    Write-Host ""
    Write-Host "-Measure: nothing written."
    return
}

foreach ($d in @($outDir, $storeDir)) {
    if (-not (Test-Path $d)) { [void](New-Item -ItemType Directory -Force -Path $d) }
}

# ---- adaptive pair ----
$bg = New-Gradient $Adaptive
$bgPath = [System.IO.Path]::Combine($outDir, 'icon_background_432.png')
$bg.Save($bgPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("wrote {0}" -f $bgPath)
$fgPath = [System.IO.Path]::Combine($outDir, 'icon_foreground_432.png')
$fg.Save($fgPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("wrote {0}" -f $fgPath)
$mono = New-Monochrome $Adaptive $Safe
$monoPath = [System.IO.Path]::Combine($outDir, 'icon_monochrome_432.png')
$mono.Save($monoPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("wrote {0}" -f $monoPath)
$mono.Dispose()
$fg.Dispose(); $bg.Dispose()

# ---- flat composites: legacy and store ----
$flat = New-Gradient $FlatWork
$flatFg = New-Foreground $FlatWork $flatUnit
$g = [System.Drawing.Graphics]::FromImage($flat)
$g.DrawImage($flatFg, 0, 0, $FlatWork, $FlatWork)
$g.Dispose()
$flatFg.Dispose()

# 스토어 아이콘은 완전 불투명이어야 한다. 불투명한 그라데이션 위에 그렸으니
# 이미 그렇겠지만, 리샘플 가장자리에 반투명이 남는 경우를 막으려 알파를 못박는다.
function Set-Opaque([System.Drawing.Bitmap]$bmp) {
    for ($y = 0; $y -lt $bmp.Height; $y++) {
        for ($x = 0; $x -lt $bmp.Width; $x++) {
            $c = $bmp.GetPixel($x, $y)
            if ($c.A -ne 255) { $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $c.R, $c.G, $c.B)) }
        }
    }
}

function New-Downscale([System.Drawing.Bitmap]$from, [int]$size) {
    $out = New-Object System.Drawing.Bitmap($size, $size, $PA)
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

# 프로젝트 아이콘(application/config/icon). 에디터 프로젝트 목록과 PC 창
# 아이콘에 쓰인다 — 폰 아이콘은 위의 런처 아이콘이다.
$projBmp = New-Downscale $flat 256
Set-Opaque $projBmp
$projPath = [System.IO.Path]::Combine($dest, 'icon.png')
$projBmp.Save($projPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host ("wrote {0}" -f $projPath)
$projBmp.Dispose()

$storeBmp.Dispose()
if ($Store -ne $FlatWork) { $flat.Dispose() }
$charTrim.Dispose(); $sheet.Dispose()
if (-not $NoGate) { $ringFront.Dispose(); $ringBack.Dispose() }
