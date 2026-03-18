#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$CalledFromRunAll,
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'
$PACK_ROOT = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$defenderBatch = Join-Path $PACK_ROOT '2 - Windows Defender\run_defender.bat'
$defenderScript = Join-Path $PSScriptRoot '1 - DisableDefender.ps1'

function Write-DefenderLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    if ([string]::IsNullOrWhiteSpace($LogFile)) {
        return
    }

    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

Write-DefenderLog 'Defender Safe Mode launcher opened.' 'INFO'

if (-not (Test-Path $defenderScript)) {
    Write-Host ''
    Write-Host '  ERROR: Defender script not found.' -ForegroundColor Red
    Write-Host "    Expected: $defenderScript" -ForegroundColor White
    Write-DefenderLog "Missing Defender script: $defenderScript" 'ERROR'
    throw 'Missing Defender script.'
}

if (-not (Test-Path $defenderBatch)) {
    Write-Host ''
    Write-Host '  ERROR: Defender batch launcher not found.' -ForegroundColor Red
    Write-Host "    Expected: $defenderBatch" -ForegroundColor White
    Write-DefenderLog "Missing Defender batch launcher: $defenderBatch" 'ERROR'
    throw 'Missing Defender batch launcher.'
}

if (-not $CalledFromRunAll) {
    Write-Host ''
    Write-Host '  WINDOWS DEFENDER SAFE MODE STEP' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  This will:' -ForegroundColor White
    Write-Host '    1. Configure Safe Mode (minimal)' -ForegroundColor White
    Write-Host '    2. Reboot into Safe Mode' -ForegroundColor White
    Write-Host '    3. In Safe Mode, run 2 - Windows Defender\run_defender.bat again' -ForegroundColor White
    Write-Host '    4. That static launcher disables Defender, removes Safe Boot and reboots to normal Windows' -ForegroundColor White
    Write-Host ''

    $answer = Read-Host 'Continue? (Y/N) [default: Y]'
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = 'Y' }
    if ($answer -notin @('Y', 'y')) {
        Write-Host '  Cancelled.' -ForegroundColor Yellow
        Write-DefenderLog 'Manual Defender Safe Mode step cancelled by user.' 'INFO'
        return
    }
}

Write-DefenderLog 'Configuring Safe Mode for Defender step.' 'INFO'
bcdedit /set '{current}' safeboot minimal | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-DefenderLog 'Failed to enable Safe Mode in BCD.' 'ERROR'
    throw 'Failed to enable Safe Mode in BCD.'
}

Write-Host ''
Write-Host '  Safe Mode is now configured.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  WHAT TO DO IN SAFE MODE:' -ForegroundColor Cyan
Write-Host '    Run this same launcher again from Safe Mode:' -ForegroundColor White
Write-Host "    $defenderBatch" -ForegroundColor White
Write-Host '    It will disable Defender, remove Safe Boot and reboot back to normal Windows.' -ForegroundColor DarkGray
Write-Host ''

if ($CalledFromRunAll) {
    Write-DefenderLog 'Safe Mode configured from run_all; caller will handle final reboot.' 'INFO'
    return
}

Read-Host '  Press Enter to reboot into Safe Mode'
Write-DefenderLog 'Rebooting into Safe Mode for Defender step.' 'INFO'
Restart-Computer -Force
