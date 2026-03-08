# 09_oosu10.ps1 - Lance O&O ShutUp10++ en mode silencieux avec le profil configure

$ROOT    = Split-Path $PSScriptRoot
$oosuExe = Join-Path $ROOT "tools\OOSU10.exe"
$oosuCfg = Join-Path $ROOT "tools\ooshutup10.cfg"

if (-not (Test-Path $oosuExe)) {
    Write-Host "    OOSU10.exe introuvable : $oosuExe" -ForegroundColor Yellow
    return
}

if (-not (Test-Path $oosuCfg)) {
    Write-Host "    ooshutup10.cfg introuvable." -ForegroundColor Red
    return
}

Start-Process $oosuExe -ArgumentList "`"$oosuCfg`" /quiet" -Wait -Verb RunAs
Write-Host "    O&O ShutUp10++ applique : $oosuCfg"
