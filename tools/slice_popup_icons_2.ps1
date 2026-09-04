<#
.SYNOPSIS
    Cuts icon_popup_2.png into its individual icons.

.DESCRIPTION
    The sheet is two icons side by side: a green check and a blue padlock.
    Only the check is used today (the mode-select screen marks the chosen
    card with it); the lock is cut anyway, because leaving half a sheet uncut
    means the next person re-derives the split by hand.

    Two things about this source are not what they look like.

    First, it has NO transparency. Opening it shows a checkerboard, but that
    is the viewer drawing its own transparency pattern over what is actually
    a solid white background — every pixel is alpha 255. So the alpha-band
    detection every other slicer here uses finds one icon spanning the whole
    sheet. The icons are separated by SATURATION instead: the circles are
    strongly coloured, the background is white, and the white check and
    padlock sit inside their circles rather than touching the background.

    Second, both icons are circles, so the cut-out is generated rather than
    copied: the mask gives a bounding box, the circle is fitted to it, and
    alpha comes from the distance to the centre with a soft rim. Keying out
    "everything near-white" instead would eat the white check mark.

    Output is baked down to ICON_SIZE rather than shipped at the sheet's
    ~790px, because it is drawn at roughly 40px. That is CLAUDE.md's "cut UI
    art at the size it is drawn" — a 20x minification at draw time needs
    mipmaps to not shimmer, and mipmapping a circle creeps its edge inward.
    The downscale premultiplies first, as every cut-out here must.

    -Measure reports the detected layout and writes nothing. Run it first.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/slice_popup_icons_2.ps1 -Measure

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/slice_popup_icons_2.ps1
#>
param(
    [switch]$Measure
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing   # Drawing2D lives in this assembly too

# Left to right on the sheet.
$Names = @('icon_check', 'icon_lock')

# A pixel belongs to an icon if it is this saturated. The background sits at
# 0.008 and the circles at 0.73, so anything in between separates them; 0.15
# is well clear of both.
$SatFloor = 0.15

# Drawn at ~40px on a 480-wide screen. 128 leaves room to grow and still
# minifies by a small enough factor that the linear filter is enough.
$IconSize = 128

# Transparent margin around the circle, in output pixels. The rim is
# anti-aliased into it, so without the margin the outermost ring of the
# circle is clipped by the texture edge and reads as a flat spot.
$Margin = 3

$repo = Split-Path -Parent $PSScriptRoot
$dir = [System.IO.Path]::Combine($repo, 'assets', 'ui_assets', 'popup')
$src = [System.IO.Path]::Combine($dir, 'icon_popup_2.png')
if (-not [System.IO.File]::Exists($src)) { throw "Source not found: $src" }

$sheet = [System.Drawing.Bitmap]::FromFile($src)
$w = $sheet.Width
$h = $sheet.Height
Write-Host ("sheet {0}  {1}x{2}" -f (Split-Path $src -Leaf), $w, $h)

# ---- saturation mask, one pass ----
$mask = New-Object 'bool[]' ($w * $h)
for ($y = 0; $y -lt $h; $y++) {
    $row = $y * $w
    for ($x = 0; $x -lt $w; $x++) {
        $c = $sheet.GetPixel($x, $y)
        $mx = [Math]::Max($c.R, [Math]::Max($c.G, $c.B))
        $mn = [Math]::Min($c.R, [Math]::Min($c.G, $c.B))
        $sat = 0.0
        if ($mx -gt 0) { $sat = ($mx - $mn) / $mx }
        $mask[$row + $x] = ($sat -ge $SatFloor)
    }
}

# ---- runs of occupied columns ----
$runs = New-Object System.Collections.ArrayList
$inRun = $false
$start = 0
for ($x = 0; $x -lt $w; $x++) {
    $hit = $false
    for ($y = 0; $y -lt $h; $y++) {
        if ($mask[$y * $w + $x]) { $hit = $true; break }
    }
    if ($hit -and -not $inRun) {
        $start = $x
        $inRun = $true
    }
    elseif (-not $hit -and $inRun) {
        $last = $x - 1
        [void]$runs.Add([pscustomobject]@{ Left = $start; Right = $last })
        $inRun = $false
    }
}
if ($inRun) {
    $last = $w - 1
    [void]$runs.Add([pscustomobject]@{ Left = $start; Right = $last })
}

Write-Host ("detected {0} icon(s) by saturation >= {1}:" -f $runs.Count, $SatFloor)

$pieces = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $runs.Count; $i++) {
    $r = $runs[$i]
    $top = $h
    $bottom = -1
    for ($y = 0; $y -lt $h; $y++) {
        for ($x = $r.Left; $x -le $r.Right; $x++) {
            if ($mask[$y * $w + $x]) {
                if ($y -lt $top) { $top = $y }
                if ($y -gt $bottom) { $bottom = $y }
                break
            }
        }
    }
    $pw = $r.Right - $r.Left + 1
    $ph = $bottom - $top + 1
    $name = if ($i -lt $Names.Count) { $Names[$i] } else { "icon_$i" }
    [void]$pieces.Add([pscustomobject]@{
        Name = $name; X = $r.Left; Y = $top; W = $pw; H = $ph
    })
    $ratio = [Math]::Round($pw / [double]$ph, 3)
    Write-Host ("  {0,-12} x {1,4}  y {2,4}  {3,4}x{4,-4}  w/h {5}" -f $name, $r.Left, $top, $pw, $ph, $ratio)
    if ([Math]::Abs($ratio - 1.0) -gt 0.06) {
        Write-Host ("    WARNING: not round (w/h {0}) — the circle fit below assumes it is." -f $ratio)
    }
}

if ($runs.Count -ne $Names.Count) {
    Write-Host ""
    Write-Host ("WARNING: expected {0} icons, found {1}." -f $Names.Count, $runs.Count)
}

if ($Measure) {
    $sheet.Dispose()
    Write-Host ""
    Write-Host "-Measure: nothing written."
    return
}

foreach ($p in $pieces) {
    # ---- full-resolution RGBA cut, alpha from the fitted circle ----
    $side = [Math]::Min($p.W, $p.H)
    $cx = $p.X + $p.W / 2.0
    $cy = $p.Y + $p.H / 2.0
    $radius = $side / 2.0
    $big = New-Object System.Drawing.Bitmap($side, $side, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($oy = 0; $oy -lt $side; $oy++) {
        $sy = $cy - $radius + $oy + 0.5
        for ($ox = 0; $ox -lt $side; $ox++) {
            $sx = $cx - $radius + $ox + 0.5
            $dx = $sx - $cx
            $dy = $sy - $cy
            $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
            # 1.5px of soft rim, so the circle does not come out with a
            # staircase edge that the downscale would then preserve.
            $a = ($radius - $d) / 1.5
            if ($a -gt 1.0) { $a = 1.0 }
            if ($a -lt 0.0) { $a = 0.0 }
            $ix = [int]$sx
            $iy = [int]$sy
            if ($ix -lt 0) { $ix = 0 }
            if ($iy -lt 0) { $iy = 0 }
            if ($ix -ge $w) { $ix = $w - 1 }
            if ($iy -ge $h) { $iy = $h - 1 }
            $c = $sheet.GetPixel($ix, $iy)
            $av = [int][Math]::Round($a * 255.0)
            # Premultiplied here, divided back out after the resize below.
            $big.SetPixel($ox, $oy, [System.Drawing.Color]::FromArgb(
                $av,
                [int][Math]::Round($c.R * $a),
                [int][Math]::Round($c.G * $a),
                [int][Math]::Round($c.B * $a)))
        }
    }

    # ---- resize (still premultiplied) ----
    $inner = $IconSize - $Margin * 2
    $out = New-Object System.Drawing.Bitmap($IconSize, $IconSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
    $dst = New-Object System.Drawing.Rectangle($Margin, $Margin, $inner, $inner)
    $srcRect = New-Object System.Drawing.Rectangle(0, 0, $side, $side)
    $g.DrawImage($big, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $big.Dispose()

    # ---- un-premultiply ----
    for ($y = 0; $y -lt $IconSize; $y++) {
        for ($x = 0; $x -lt $IconSize; $x++) {
            $c = $out.GetPixel($x, $y)
            if ($c.A -eq 0) { continue }
            $f = 255.0 / $c.A
            $r = [int][Math]::Min(255, [Math]::Round($c.R * $f))
            $gg = [int][Math]::Min(255, [Math]::Round($c.G * $f))
            $bb = [int][Math]::Min(255, [Math]::Round($c.B * $f))
            $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($c.A, $r, $gg, $bb))
        }
    }

    $path = [System.IO.Path]::Combine($dir, ($p.Name + '.png'))
    $out.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $out.Dispose()
    Write-Host ("wrote {0}  {1}x{2}  (from {3}x{3})" -f $path, $IconSize, $IconSize, $side)
}

$sheet.Dispose()
