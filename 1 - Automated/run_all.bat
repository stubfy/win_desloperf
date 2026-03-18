@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
set "RUN_ALL_PS1=%~dp0scripts\ps1\run_all.ps1"
powershell -NoProfile -ExecutionPolicy RemoteSigned -Command "Unblock-File -LiteralPath '%RUN_ALL_PS1%' -ErrorAction SilentlyContinue; & '%RUN_ALL_PS1%'"
pause
