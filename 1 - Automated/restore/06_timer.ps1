# restore\06_timer.ps1 - Remove SetTimerResolution from automatic startup

$startupDir   = [System.Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDir "SetTimerResolution.lnk"

if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
    Write-Host "    SetTimerResolution shortcut removed from startup."
} else {
    Write-Host "    Shortcut not found (already removed or never created)." -ForegroundColor Gray
}
