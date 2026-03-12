#Requires -RunAsAdministrator
# restore\15_windows_update.ps1 - Restore Windows Update to maximum mode (Windows default)

Write-Host "    Restoring Windows Update -> maximum mode (default)..."

$SCRIPTS = Join-Path (Split-Path $PSScriptRoot) "scripts"
& "$SCRIPTS\15_windows_update.ps1" -Profil 1
