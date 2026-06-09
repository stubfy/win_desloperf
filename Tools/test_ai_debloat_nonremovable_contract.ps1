#Requires -Version 5.0

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot
$aiDebloatPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\ai_debloat.ps1'
$aiDebloat = Get-Content -Path $aiDebloatPath -Raw

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

Assert-Contains $aiDebloat 'function Test-AiAppxPackageIsPinnedSystemStub' 'ai_debloat.ps1 must classify non-removable inbox AppX stubs before removal.'
Assert-Contains $aiDebloat 'function Enable-AiAppxRemovalPolicy' 'ai_debloat.ps1 must try the supported non-removable AppX policy path before skipping system stubs.'
Assert-Contains $aiDebloat 'Set-NonRemovableAppsPolicy\s+-Online\s+-PackageFamilyName' 'ai_debloat.ps1 must use the documented Set-NonRemovableAppsPolicy cmdlet instead of only registry or file cleanup.'
Assert-Contains $aiDebloat '\$removalTargets' 'ai_debloat.ps1 must remove only filtered AppX targets.'
Assert-Contains $aiDebloat 'Skipping non-removable AI AppX system stub' 'ai_debloat.ps1 must log non-removable system stubs as skipped, not failed removals.'
Assert-Contains $aiDebloat 'Only non-removable AI AppX system stubs remain' 'ai_debloat.ps1 summary must not warn when only pinned system stubs remain.'

Write-Host 'AI debloat non-removable AppX contract OK'
