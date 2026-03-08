#Requires -RunAsAdministrator
# restore\15_windows_update.ps1 - Restaure Windows Update en mode maximum (defaut Windows)

Write-Host "    Restauration Windows Update -> mode maximum (defaut)..."

$SCRIPTS = Join-Path (Split-Path $PSScriptRoot) "scripts"
& "$SCRIPTS\15_windows_update.ps1" -Profil 1
