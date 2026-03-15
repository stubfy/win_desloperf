# 02_registry.ps1 - Import consolidated registry tweaks
#
# Applies tweaks_consolidated.reg via regedit /s (silent import).
# All tweaks are documented inside the .reg file itself.
# This script is intentionally thin: the .reg file is the authoritative source
# so that the same file can be applied standalone without running the full pack.
#
# Rollback: restore\01_registry.ps1 imports tweaks_defaults.reg

$regFile = Join-Path $PSScriptRoot "tweaks_consolidated.reg"

if (-not (Test-Path $regFile)) {
    Write-Host "    ERROR: tweaks_consolidated.reg not found" -ForegroundColor Red
    exit 1
}

Start-Process "regedit.exe" -ArgumentList "/s `"$regFile`"" -Wait -Verb RunAs
Write-Host "    Registry tweaks imported from tweaks_consolidated.reg"
