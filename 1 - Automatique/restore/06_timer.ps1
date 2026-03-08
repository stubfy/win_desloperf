# restore\06_timer.ps1 - Supprime SetTimerResolution du demarrage automatique

$startupDir   = [System.Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDir "SetTimerResolution.lnk"

if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
    Write-Host "    Raccourci SetTimerResolution supprime du demarrage."
} else {
    Write-Host "    Raccourci non trouve (deja supprime ou jamais cree)." -ForegroundColor Gray
}
