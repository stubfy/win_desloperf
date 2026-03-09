# 10_timer.ps1 - Install SetTimerResolution to AppData and add to Windows startup

$ROOT     = Split-Path $PSScriptRoot
$timerSrc = Join-Path $ROOT "tools\SetTimerResolution.exe"

if (-not (Test-Path $timerSrc)) {
    Write-Host "    SetTimerResolution.exe not found: $timerSrc" -ForegroundColor Yellow
    return
}

# Install to %APPDATA%\win_deslopper\
$installDir = Join-Path $env:APPDATA "win_deslopper"
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}
$timerExe = Join-Path $installDir "SetTimerResolution.exe"
Copy-Item -Path $timerSrc -Destination $timerExe -Force
Write-Host "    Installed to   : $timerExe"

$startupDir   = [System.Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDir "SetTimerResolution.lnk"

$wsh      = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath       = $timerExe
$shortcut.Arguments        = "--resolution 5200 --no-console"
$shortcut.WorkingDirectory = $installDir
$shortcut.Description      = "SetTimerResolution - Opti Pack"
$shortcut.Save()

Write-Host "    Shortcut created: $shortcutPath"
Write-Host "    Arguments      : --resolution 5200 --no-console"
Write-Host "    Tip            : use MeasureSleep.exe to verify the actual resolution"
Write-Host "                     (adjust value if needed: 5000, 5100, 5200...)"
