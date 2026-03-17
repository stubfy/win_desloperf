# 07_oosu10.ps1 - Run O&O ShutUp10++ in silent mode with the configured profile
#
# O&O ShutUp10++ (OOSU10.exe) applies a comprehensive set of Windows privacy
# and telemetry settings via its own registry/policy engine. The pack ships a
# pre-configured ooshutup10.cfg that enables the recommended settings from the
# OOSU10 "Recommended and somewhat recommended" preset.
#
# Running OOSU10 in /quiet mode applies the .cfg file without any UI interaction.
# Settings applied by OOSU10 overlap with some tweaks already in
# tweaks_consolidated.reg and uwt_tweaks.reg; the redundancy is intentional --
# OOSU10 covers additional undocumented keys not tracked by the pack's reg files,
# and applying in sequence ensures no gap is left.
#
# To review or adjust the OOSU10 config: open OOSU10.exe without /quiet and
# modify settings interactively; save the new config to tools\ooshutup10.cfg.
#
# Rollback: OOSU10 has no built-in undo; the system restore point created by
# 01_backup.ps1 is the recommended rollback path for OOSU10 changes.

$ROOT    = Split-Path (Split-Path $PSScriptRoot)
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
