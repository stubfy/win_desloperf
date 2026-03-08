# 10_timer.ps1 - Ajoute SetTimerResolution au demarrage de Windows (shell:startup)

$ROOT     = Split-Path $PSScriptRoot
$timerExe = Join-Path $ROOT "tools\SetTimerResolution.exe"

if (-not (Test-Path $timerExe)) {
    Write-Host "    SetTimerResolution.exe introuvable : $timerExe" -ForegroundColor Yellow
    return
}

$startupDir   = [System.Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDir "SetTimerResolution.lnk"

$wsh      = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath       = $timerExe
$shortcut.Arguments        = "--resolution 5200 --no-console"
$shortcut.WorkingDirectory = Split-Path $timerExe
$shortcut.Description      = "SetTimerResolution - Opti Pack"
$shortcut.Save()

Write-Host "    Raccourci cree : $shortcutPath"
Write-Host "    Arguments      : --resolution 5200 --no-console"
Write-Host "    Tip            : utiliser MeasureSleep.exe pour verifier la resolution effective"
Write-Host "                     (ajuster valeur si besoin : 5000, 5100, 5200...)"
