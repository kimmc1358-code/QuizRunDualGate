<#
.SYNOPSIS
    Turns a music track that ends on a final chord into one that loops
    seamlessly.

.DESCRIPTION
    Setting a stream to loop only removes the technical gap at the wrap; it
    cannot help a track that was written with an ending. These tracks play at
    full level and then decay to silence over the last second or two, so the
    loop reads as "music, fade to nothing, sudden restart".

    Two edits fix that, both on the audio rather than in the game:

      1. Trim the outro, so the file no longer ends in a decay. Use -Analyze
         to find where the decay starts.
      2. Crossfade the new tail into the head, so the wrap point is a blend
         of the two rather than a cut between them.

    Concretely, for a source of usable length S and crossfade D, the result
    is S - D long, and its first D seconds are the original opening faded up
    over the original ending faded down. Playing that end-to-start is then
    continuous. Equal-power (qsin) curves keep the blend from dipping in the
    middle the way a linear fade does.

    This cannot invent a musical transition — if the last bar does not lead
    back into the first, the loop will still be noticeable as a change, just
    not as a stop. That part is composition.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/make_bgm_loop.ps1 -Analyze assets/audio/bgm_main.ogg

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/make_bgm_loop.ps1 -Source assets/audio/bgm_main.ogg -TrimEnd 1.3 -Crossfade 2.5
#>
param(
    [string]$Source,
    [string]$Analyze,
    # Seconds to drop from the end — the outro decay.
    [double]$TrimEnd = 0.0,
    # Length of the tail/head blend at the loop point.
    [double]$Crossfade = 2.5,
    [string]$Out,
    [int]$Quality = 5,
    [string]$FFmpeg
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
function Resolve-RepoPath([string] $p) {
    if ([System.IO.Path]::IsPathRooted($p)) { return $p }
    return [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repo, $p))
}

function Find-FFmpeg {
    if ($FFmpeg) { return $FFmpeg }
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # winget puts it here and only adds it to PATH for new shells.
    $root = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Microsoft', 'WinGet', 'Packages')
    if ([System.IO.Directory]::Exists($root)) {
        $hit = [System.IO.Directory]::GetFiles($root, 'ffmpeg.exe', [System.IO.SearchOption]::AllDirectories)
        if ($hit.Count -gt 0) { return $hit[0] }
    }
    throw "ffmpeg not found. Pass -FFmpeg <path>, or install it (winget install Gyan.FFmpeg)."
}

$ff = Find-FFmpeg

# ffmpeg reports everything on stderr. Windows PowerShell turns a native
# command's stderr into error records, which $ErrorActionPreference='Stop'
# then treats as fatal — so reading its output means relaxing that for the
# duration of the call.
function Invoke-FFText([string[]] $ffArgs) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        return (& $ff @ffArgs 2>&1 | Out-String)
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Get-Duration([string] $path) {
    $out = Invoke-FFText @('-hide_banner', '-i', $path)
    if ($out -match 'Duration:\s*(\d+):(\d+):([\d.]+)') {
        return [double]$Matches[1] * 3600 + [double]$Matches[2] * 60 + [double]$Matches[3]
    }
    throw "could not read the duration of $path"
}

function Get-MeanDb([string] $path, [string[]] $seekArgs) {
    $out = Invoke-FFText (@('-hide_banner') + $seekArgs + @('-i', $path, '-af', 'volumedetect', '-f', 'null', '-'))
    if ($out -match 'mean_volume:\s*(-?[\d.]+) dB') { return [double]$Matches[1] }
    return [double]::NaN
}

if ($Analyze) {
    $path = Resolve-RepoPath $Analyze
    $len = Get-Duration $path
    Write-Host ("{0}   length {1:N2}s" -f (Split-Path $path -Leaf), $len)
    Write-Host ("  opening 3s          mean {0,7:N1} dB" -f (Get-MeanDb $path @('-t', '3')))
    Write-Host "  half-second windows measured back from the end:"
    foreach ($off in 6.0, 5.0, 4.0, 3.0, 2.5, 2.0, 1.5, 1.0, 0.5) {
        $db = Get-MeanDb $path @('-sseof', "-$off", '-t', '0.5')
        Write-Host ("    -{0,4:N1}s   {1,7:N1} dB" -f $off, $db)
    }
    Write-Host "  Trim from wherever the level starts falling away and never recovers."
    return
}

if (-not $Source) { throw "Pass -Source <track> (with -TrimEnd/-Crossfade), or -Analyze <track>." }

$src = Resolve-RepoPath $Source
$len = Get-Duration $src
$usable = $len - $TrimEnd
$loopLen = $usable - $Crossfade
if ($loopLen -le $Crossfade) {
    throw ("crossfade {0}s is too long for {1:N2}s of usable audio" -f $Crossfade, $usable)
}

if (-not $Out) {
    $dir = Split-Path $src -Parent
    $base = [System.IO.Path]::GetFileNameWithoutExtension($src)
    $Out = [System.IO.Path]::Combine($dir, $base + '_loop' + [System.IO.Path]::GetExtension($src))
} else {
    $Out = Resolve-RepoPath $Out
}

Write-Host ("source {0:N2}s  ->  trim {1:N2}s outro, {2:N2}s crossfade  ->  loop {3:N2}s" -f `
    $len, $TrimEnd, $Crossfade, $loopLen)

# head  = the opening, faded up
# tail  = the last Crossfade seconds of the usable audio, faded down
# blend = the two summed: this becomes the new opening, and is what the end
#         of the file now runs into when the stream wraps
# rest  = everything between
$filter = @(
    "[0:a]atrim=0:$Crossfade,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=${Crossfade}:curve=qsin[head]",
    "[0:a]atrim=${loopLen}:${usable},asetpts=PTS-STARTPTS,afade=t=out:st=0:d=${Crossfade}:curve=qsin[tail]",
    "[head][tail]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0[blend]",
    "[0:a]atrim=${Crossfade}:${loopLen},asetpts=PTS-STARTPTS[rest]",
    "[blend][rest]concat=n=2:v=0:a=1[out]"
) -join ';'

& $ff -hide_banner -loglevel error -y -i $src -filter_complex $filter -map '[out]' -c:a libvorbis -q:a $Quality $Out
if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed with exit code $LASTEXITCODE" }

$outLen = Get-Duration $Out
$headDb = Get-MeanDb $Out @('-t', '0.5')
$tailDb = Get-MeanDb $Out @('-sseof', '-0.5')
Write-Host ("wrote {0}   {1:N2}s" -f (Split-Path $Out -Leaf), $outLen)
Write-Host ("  level at the wrap:  last 0.5s {0,6:N1} dB   first 0.5s {1,6:N1} dB   gap {2,5:N1} dB" -f `
    $tailDb, $headDb, [math]::Abs($tailDb - $headDb))
Write-Host "  A small gap here means the two sides meet at a similar loudness, which is"
Write-Host "  what stops the wrap from sounding like a stop and a restart."
