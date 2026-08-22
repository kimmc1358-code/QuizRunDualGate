# Validates assets/flags/flags_data.json against the actual image files on
# disk: checks record count, unique codes, unique names, ISO alpha-2 code
# shape, that every referenced image file exists and is a real non-empty
# PNG at the unified 256x171 (3:2) frame size, and flags any image files on
# disk that aren't referenced by any record. Run from anywhere; paths are
# resolved relative to this script's own location.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools/validate_flags_data.ps1

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DataPath = Join-Path $ProjectRoot "assets\flags\flags_data.json"
$ImageDir = Join-Path $ProjectRoot "assets\flags\256x171"
$ExpectedCount = 193
$ExpectedWidth = 256
$ExpectedHeight = 171

$problems = @()

if (-not (Test-Path -LiteralPath $DataPath)) {
    Write-Output "FAIL: flags_data.json not found at $DataPath"
    exit 1
}

$records = Get-Content -LiteralPath $DataPath -Raw | ConvertFrom-Json

if ($records.Count -ne $ExpectedCount) {
    $problems += "record count is $($records.Count), expected $ExpectedCount"
}

$seenCodes = @{}
$seenNames = @{}
$referencedFiles = @{}

foreach ($r in $records) {
    # --- code shape: exactly 2 uppercase letters (ISO 3166-1 alpha-2) ---
    if ($r.code -notmatch '^[A-Z]{2}$') {
        $problems += "[$($r.code)] code is not a valid 2-letter uppercase ISO alpha-2 code"
    }

    # --- duplicate code ---
    if ($seenCodes.ContainsKey($r.code)) {
        $problems += "[$($r.code)] duplicate country code (also used by '$($seenCodes[$r.code])' / '$($r.name)')"
    } else {
        $seenCodes[$r.code] = $r.name
    }

    # --- duplicate name ---
    if ($seenNames.ContainsKey($r.name)) {
        $problems += "[$($r.code)] duplicate country name '$($r.name)' (also used by code '$($seenNames[$r.name])')"
    } else {
        $seenNames[$r.name] = $r.code
    }

    # --- name non-empty ---
    if ([string]::IsNullOrWhiteSpace($r.name)) {
        $problems += "[$($r.code)] empty name"
    }

    # --- image path convention ---
    $expectedImage = "res://assets/flags/256x171/$($r.code).png"
    if ($r.image -ne $expectedImage) {
        $problems += "[$($r.code)] image path '$($r.image)' does not match expected '$expectedImage'"
    }

    # --- image file exists / valid / correct size ---
    $localPath = Join-Path $ImageDir "$($r.code).png"
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        $problems += "[$($r.code)] image file missing: $localPath"
    } else {
        $referencedFiles[$localPath.ToLower()] = $true
        $fileInfo = Get-Item -LiteralPath $localPath
        if ($fileInfo.Length -eq 0) {
            $problems += "[$($r.code)] image file is zero bytes: $localPath"
        } else {
            try {
                $img = [System.Drawing.Image]::FromFile($localPath)
                if ($img.Width -ne $ExpectedWidth -or $img.Height -ne $ExpectedHeight) {
                    $problems += "[$($r.code)] image is $($img.Width)x$($img.Height), expected ${ExpectedWidth}x${ExpectedHeight}"
                }
                $img.Dispose()
            } catch {
                $problems += "[$($r.code)] image file is not a valid/decodable image: $localPath"
            }
        }
    }
}

# --- orphan files on disk not referenced by any record ---
if (Test-Path -LiteralPath $ImageDir) {
    Get-ChildItem -LiteralPath $ImageDir -Filter "*.png" | ForEach-Object {
        if (-not $referencedFiles.ContainsKey($_.FullName.ToLower())) {
            $problems += "orphan image file not referenced by any record: $($_.FullName)"
        }
    }
}

Write-Output "Checked $($records.Count) records against $ImageDir"
if ($problems.Count -eq 0) {
    Write-Output "PASS: all $ExpectedCount records have a unique code, unique name, and a matching valid ${ExpectedWidth}x${ExpectedHeight} image file."
} else {
    Write-Output "FAIL: $($problems.Count) problem(s) found:"
    foreach ($p in $problems) { Write-Output "  - $p" }
    exit 1
}
