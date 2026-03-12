# 02_registry.ps1 - Import consolidated registry tweaks

$regFile = Join-Path $PSScriptRoot "tweaks_consolidated.reg"

if (-not (Test-Path $regFile)) {
    Write-Host "    ERROR: tweaks_consolidated.reg not found" -ForegroundColor Red
    exit 1
}

Start-Process "regedit.exe" -ArgumentList "/s `"$regFile`"" -Wait -Verb RunAs
Write-Host "    Registry tweaks imported from tweaks_consolidated.reg"
