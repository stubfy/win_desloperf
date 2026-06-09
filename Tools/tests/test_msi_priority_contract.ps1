#Requires -Version 5.0

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$snapshotPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\msi_snapshot.ps1'
$applyPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\msi_apply.ps1'
$restorePath = Join-Path $repoRoot '1 - Automated\scripts\ps1\msi_restore.ps1'

function Assert-Contains {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Message
    )

    if ($Content -notmatch $Pattern) {
        throw $Message
    }
}

$snapshot = Get-Content -Path $snapshotPath -Raw
$apply = Get-Content -Path $applyPath -Raw
$restore = Get-Content -Path $restorePath -Raw

foreach ($script in @($snapshot, $apply, $restore)) {
    Assert-Contains $script 'Affinity Policy' 'MSI scripts must read/write the Interrupt Management\Affinity Policy registry key.'
    Assert-Contains $script 'DevicePriority' 'MSI scripts must preserve the interrupt priority DevicePriority value.'
    Assert-Contains $script 'DevicePriorityExists' 'MSI scripts must track whether DevicePriority existed so undefined priority can be restored.'
}

Assert-Contains $apply 'Remove-ItemProperty[\s\S]*DevicePriority' 'msi_apply.ps1 must remove DevicePriority when the saved state had undefined priority.'
Assert-Contains $restore 'Remove-ItemProperty[\s\S]*DevicePriority' 'msi_restore.ps1 must remove DevicePriority when the default backup had undefined priority.'

Write-Host 'MSI priority contract OK'
