#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$CalledFromRunAll,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'
$helperPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Disable Defender and Return to Normal Mode.bat'
$defenderScript = Join-Path $PSScriptRoot '1 - DisableDefender.ps1'

function Write-DefenderLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    if ([string]::IsNullOrWhiteSpace($LogFile)) {
        return
    }

    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

Write-DefenderLog "Defender Safe Mode launcher opened." 'INFO'

if (-not (Test-Path $defenderScript)) {
    Write-Host ""
    Write-Host "  ERROR: Defender script not found." -ForegroundColor Red
    Write-Host "    Expected: $defenderScript" -ForegroundColor White
    Write-DefenderLog "Missing Defender script: $defenderScript" 'ERROR'
    throw "Missing Defender script."
}

if (-not $CalledFromRunAll) {
    Write-Host ""
    Write-Host "  WINDOWS DEFENDER SAFE MODE STEP" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  This will:" -ForegroundColor White
    Write-Host "    1. Configure Safe Mode (minimal)" -ForegroundColor White
    Write-Host "    2. Create a Desktop helper: 'Disable Defender and Return to Normal Mode.bat'" -ForegroundColor White
    Write-Host "    3. Reboot into Safe Mode" -ForegroundColor White
    Write-Host ""
    Write-Host "  In Safe Mode, run the Desktop helper. It disables Defender," -ForegroundColor DarkGray
    Write-Host "  removes Safe Boot, and reboots back to normal Windows." -ForegroundColor DarkGray
    Write-Host ""

    $answer = Read-Host "Continue? (Y/N) [default: Y]"
    if ($answer -eq '') {
        $answer = 'Y'
    }

    if ($answer -notin @('Y', 'y')) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        Write-DefenderLog "Manual Defender Safe Mode step cancelled by user." 'INFO'
        return
    }
}

Write-DefenderLog "Configuring Safe Mode for Defender step." 'INFO'
bcdedit /set '{current}' safeboot minimal | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-DefenderLog "Failed to enable Safe Mode in BCD." 'ERROR'
    throw "Failed to enable Safe Mode in BCD."
}

@"
@echo off
fltmc >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
set "DEFENDER_SCRIPT=$defenderScript"
echo.
echo  =========================================================
echo   win_deslopper -- Disable Defender and Return to Normal Mode
echo  =========================================================
echo.
echo  This will:
echo    1. Disable Windows Defender (6 services set to Start=4)
echo    2. Remove Safe Boot flag
echo    3. Reboot to normal Windows
echo.
if not exist "%DEFENDER_SCRIPT%" (
echo  ERROR: missing Defender script:
echo    %DEFENDER_SCRIPT%
echo.
pause
exit /b 1
)
pause
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%DEFENDER_SCRIPT%"
if errorlevel 1 (
echo.
echo  Defender script failed. Safe Boot was kept enabled.
echo  Review the PowerShell error, then run this helper again.
echo.
pause
exit /b 1
)
bcdedit /deletevalue {current} safeboot >nul 2>&1
shutdown /r /t 0
"@ | Set-Content -Path $helperPath -Encoding ASCII

Write-DefenderLog "Desktop helper created at $helperPath" 'INFO'
Write-Host ""
Write-Host "  Safe Mode is now configured." -ForegroundColor Yellow
Write-Host ""
Write-Host "  WHAT TO DO IN SAFE MODE:" -ForegroundColor Cyan
Write-Host "    Run the shortcut on your Desktop: 'Disable Defender and Return to Normal Mode.bat'" -ForegroundColor White
Write-Host "    (disables Defender, removes Safe Boot, reboots automatically)" -ForegroundColor DarkGray
Write-Host ""
Read-Host "  Press Enter to reboot into Safe Mode"
Write-DefenderLog "Rebooting into Safe Mode for Defender step." 'INFO'
Restart-Computer -Force

