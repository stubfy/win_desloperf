@echo off
fltmc >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set "RUN_DEFENDER_PS1=%~dp0..\1 - Automated\scripts\ps1\run_defender.ps1"
set "DISABLE_DEFENDER_PS1=%~dp0..\1 - Automated\scripts\ps1\1 - DisableDefender.ps1"

if not exist "%RUN_DEFENDER_PS1%" (
    echo.
    echo  ERROR: missing launcher script:
    echo    %RUN_DEFENDER_PS1%
    echo.
    pause
    exit /b 1
)

if defined SAFEBOOT_OPTION goto safe_mode

powershell -NoProfile -ExecutionPolicy RemoteSigned -Command "Unblock-File -LiteralPath '%RUN_DEFENDER_PS1%' -ErrorAction SilentlyContinue; & '%RUN_DEFENDER_PS1%'"
pause
exit /b

:safe_mode
if not exist "%DISABLE_DEFENDER_PS1%" (
    echo.
    echo  ERROR: missing Defender disable script:
    echo    %DISABLE_DEFENDER_PS1%
    echo.
    pause
    exit /b 1
)

echo.
echo  =========================================================
echo   win_desloperf -- Disable Defender and Return to Normal Mode
echo  =========================================================
echo.
echo  Safe Mode detected.
echo  This will:
echo    1. Disable Windows Defender (6 services set to Start=4)
echo    2. Remove Safe Boot flag
echo    3. Reboot to normal Windows
echo.
pause
powershell -NoProfile -ExecutionPolicy RemoteSigned -Command "Unblock-File -LiteralPath '%DISABLE_DEFENDER_PS1%' -ErrorAction SilentlyContinue; & '%DISABLE_DEFENDER_PS1%'"
if errorlevel 1 (
    echo.
    echo  Defender script failed. Safe Boot was kept enabled.
    echo  Review the PowerShell error, then run this launcher again.
    echo.
    pause
    exit /b 1
)
bcdedit /deletevalue {current} safeboot >nul 2>&1
echo.
echo  Safe Boot removed. Rebooting to normal Windows...
shutdown /r /t 0
