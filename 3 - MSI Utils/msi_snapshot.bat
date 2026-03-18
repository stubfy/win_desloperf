@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0..\1 - Automated\scripts\ps1\msi_snapshot.ps1" -DataDir "%~dp0" -StateFile "%~dp0..\1 - Automated\backup\msi_state.json"
pause
