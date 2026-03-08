# 02_registry.ps1 - Importe les tweaks registre consolides

$regFile = Join-Path $PSScriptRoot "tweaks_consolidated.reg"

if (-not (Test-Path $regFile)) {
    Write-Host "    ERREUR: tweaks_consolidated.reg introuvable" -ForegroundColor Red
    exit 1
}

Start-Process "regedit.exe" -ArgumentList "/s `"$regFile`"" -Wait -Verb RunAs
Write-Host "    Tweaks registre importes depuis tweaks_consolidated.reg"
