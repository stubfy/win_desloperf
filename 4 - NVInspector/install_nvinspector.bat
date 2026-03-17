@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\1 - Automated\scripts\ps1\install_nvinspector.ps1 -SourceRoot "%~dp0""
pause
