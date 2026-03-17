$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$target = Join-Path $repoRoot '2 - Windows Defender\ps1\1 - DisableDefender.ps1'

if (-not (Test-Path $target)) {
    throw "Compatibility shim failed: missing $target"
}

& $target @args
