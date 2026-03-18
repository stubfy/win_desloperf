@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
set "DEFENDER_DISABLE_PS1=%~dp0ps1\defender_disable.ps1"
powershell -NoProfile -ExecutionPolicy RemoteSigned -Command "Unblock-File -LiteralPath '%DEFENDER_DISABLE_PS1%' -ErrorAction SilentlyContinue; & '%DEFENDER_DISABLE_PS1%'"
pause
