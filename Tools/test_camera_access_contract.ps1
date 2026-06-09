#Requires -Version 5.0

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot
$privacyPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\privacy.ps1'
$servicesPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\services.ps1'

function Assert-Contains {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Content -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Content -match $Pattern) {
        throw $Message
    }
}

$privacy = Get-Content -Path $privacyPath -Raw
$services = Get-Content -Path $servicesPath -Raw

$manualStart = $services.IndexOf('$manual = @(')
$automaticStart = $services.IndexOf('$automatic = @(')
$automaticDelayedStart = $services.IndexOf('$automaticDelayedStart = @(')
if ($manualStart -lt 0 -or $automaticStart -lt 0 -or $automaticDelayedStart -lt 0) {
    throw 'services.ps1 catalog blocks could not be located.'
}

$manualBlock = $services.Substring($manualStart, $automaticStart - $manualStart)
$automaticBlock = $services.Substring($automaticStart, $automaticDelayedStart - $automaticStart)

Assert-Contains $privacy 'Set-CameraAccessUserControlled' 'privacy.ps1 must keep camera access user-controlled.'
Assert-Contains $privacy "Set-Service -Name 'camsvc' -StartupType Automatic" 'privacy.ps1 must set camsvc Automatic when camera access is kept enabled.'
Assert-NotContains $manualBlock "'camsvc'" 'services.ps1 must not expect camsvc Manual when privacy.ps1 forces it Automatic.'
Assert-Contains $automaticBlock "'camsvc'" 'services.ps1 must track camsvc as Automatic so show_diff does not report a false failure.'

Write-Host 'Camera access contract OK'
