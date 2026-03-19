@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
for %%I in ("%SCRIPT_DIR%\..") do set "PACK_ROOT=%%~fI"
set "MSI_RESTORE_PS1=%PACK_ROOT%\1 - Automated\scripts\ps1\msi_restore.ps1"
set "MSI_DEFAULT_STATE_FILE=%PACK_ROOT%\1 - Automated\backup\msi_state_default.json"
set "MSI_LOG=%PACK_ROOT%\1 - Automated\backup\msi_restore_last.log"

net session >nul 2>&1
if %errorlevel% neq 0 (
    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -WorkingDirectory '%SCRIPT_DIR%' -Verb RunAs"
    exit /b
)

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%MSI_RESTORE_PS1%" -StateFile "%MSI_DEFAULT_STATE_FILE%" > "%MSI_LOG%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"
if exist "%MSI_LOG%" type "%MSI_LOG%"
if not "%EXIT_CODE%"=="0" (
    echo.
    echo PowerShell exited with code %EXIT_CODE%.
    echo Log: "%MSI_LOG%"
)
pause
