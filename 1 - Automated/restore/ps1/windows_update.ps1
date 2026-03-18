# restore\windows_update.ps1 - Restore Windows Update to maximum mode (pack baseline)

Write-Host "    Restoring Windows Update -> maximum mode (baseline)..."

$PACK_ROOT = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$WU_STEP   = Join-Path $PACK_ROOT "1 - Automated\scripts\ps1\set_windows_update.ps1"

if (-not (Test-Path $WU_STEP)) {
    throw "Windows Update restore helper not found: $WU_STEP"
}

& $WU_STEP -Profil 1
