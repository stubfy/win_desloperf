#Requires -RunAsAdministrator
# restore\11_windows_update.ps1 - Restore Windows Update to maximum mode (pack baseline)

Write-Host "    Restoring Windows Update -> maximum mode (baseline)..."

$PACK_ROOT = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$WU_STEP   = Join-Path $PACK_ROOT "8 - Windows Update\ps1\set_windows_update.ps1"
& $WU_STEP -Profil 1
