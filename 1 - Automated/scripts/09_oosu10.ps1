# 09_oosu10.ps1 - Run O&O ShutUp10++ in silent mode with the configured profile

$ROOT    = Split-Path $PSScriptRoot
$oosuExe = Join-Path $ROOT "tools\OOSU10.exe"
$oosuCfg = Join-Path $ROOT "tools\ooshutup10.cfg"

if (-not (Test-Path $oosuExe)) {
    Write-Host "    OOSU10.exe not found: $oosuExe" -ForegroundColor Yellow
    return
}

if (-not (Test-Path $oosuCfg)) {
    Write-Host "    ooshutup10.cfg not found." -ForegroundColor Red
    return
}

Start-Process $oosuExe -ArgumentList "`"$oosuCfg`" /quiet" -Wait -Verb RunAs
Write-Host "    O&O ShutUp10++ applied: $oosuCfg"
