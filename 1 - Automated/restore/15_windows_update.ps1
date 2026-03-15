#Requires -RunAsAdministrator
# restore\15_windows_update.ps1 - Restore Windows Update to maximum mode (pack baseline)

Write-Host "    Restoring Windows Update -> maximum mode (baseline)..."

$SCRIPTS = Join-Path (Split-Path $PSScriptRoot) "scripts"
& "$SCRIPTS\15_windows_update.ps1" -Profil 1
