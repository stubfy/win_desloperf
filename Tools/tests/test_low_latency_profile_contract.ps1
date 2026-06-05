#Requires -Version 5.0

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$runAllPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\run_all.ps1'
$snapshotPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\snapshot.ps1'
$showDiffPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\show_diff.ps1'
$applyPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\low_latency_profile.ps1'
$applyBatPath = Join-Path $repoRoot '1 - Automated\scripts\low_latency_profile.bat'
$restoreAllPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\restore_all.ps1'
$restorePath = Join-Path $repoRoot '1 - Automated\restore\ps1\low_latency_profile.ps1'
$restoreBatPath = Join-Path $repoRoot '1 - Automated\restore\low_latency_profile.bat'
$readmePath = Join-Path $repoRoot 'README.md'

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

$runAll = Get-Content -Path $runAllPath -Raw
$snapshot = Get-Content -Path $snapshotPath -Raw
$showDiff = Get-Content -Path $showDiffPath -Raw
$apply = Get-Content -Path $applyPath -Raw
$applyBat = Get-Content -Path $applyBatPath -Raw
$restoreAll = Get-Content -Path $restoreAllPath -Raw
$restore = Get-Content -Path $restorePath -Raw
$restoreBat = Get-Content -Path $restoreBatPath -Raw
$readme = Get-Content -Path $readmePath -Raw

foreach ($featureId in @('58989092', '60716524', '48433719', '61391826')) {
    Assert-Contains $apply $featureId "low_latency_profile.ps1 must include feature ID $featureId."
}

Assert-Contains $apply '\$FEATURE_PRIORITY = 8' 'Low Latency Profile must use ViVeTool-compatible User priority 8 for boot-store overrides.'
Assert-Contains $apply 'ConvertTo-ObfuscatedFeatureId' 'Low Latency Profile must obfuscate FeatureManagement IDs instead of using raw IDs as subkeys.'
Assert-Contains $apply 'EnabledState'' -Value 2' 'Low Latency Profile must set EnabledState=2.'
Assert-Contains $apply 'EnabledStateOptions'' -Value 0' 'Low Latency Profile must set EnabledStateOptions=0.'
Assert-Contains $apply 'VariantPayloadKind'' -Value 0' 'Low Latency Profile must write ViVeTool-compatible variant defaults.'
Assert-Contains $apply 'low_latency_profile_state\.json' 'Low Latency Profile must save a rollback state file.'
Assert-Contains $applyBat 'ps1\\low_latency_profile\.ps1' 'Standalone Low Latency Profile .bat must call the apply script.'

Assert-Contains $restore 'VariantPayloadKind' 'Low Latency Profile restore must restore/remove variant values symmetrically.'
Assert-Contains $restoreBat 'ps1\\low_latency_profile\.ps1' 'Standalone Low Latency Profile restore .bat must call the restore script.'
Assert-Contains $restoreAll 'low_latency_profile\.ps1' 'restore_all.ps1 must call the Low Latency Profile restore script.'

Assert-Contains $runAll 'enableLowLatencyProfile = \$false' 'run_all default for Low Latency Profile must be No.'
Assert-Contains $runAll 'Enable Windows Low Latency Profile / CPU boost' 'run_all must expose the Low Latency Profile prompt.'
Assert-Contains $runAll 'low_latency_profile\.ps1' 'run_all must invoke low_latency_profile.ps1 when selected.'
Assert-Contains $runAll 'TrackLowLatencyProfile:\$enableLowLatencyProfile' 'run_all must include Low Latency Profile in the snapshot only when selected.'

Assert-Contains $snapshot '\[bool\]\$TrackLowLatencyProfile = \$false' 'snapshot.ps1 must support optional Low Latency Profile tracking.'
Assert-Contains $snapshot 'LowLatencyProfile' 'snapshot.ps1 must write LowLatencyProfile snapshot data.'
Assert-Contains $showDiff 'LowLatencyProfile' 'show_diff.ps1 must report LowLatencyProfile results.'

Assert-Contains $readme 'Enable Windows Low Latency Profile / CPU boost \| No' 'README must document Low Latency Profile as default No.'

Write-Host 'Low Latency Profile contract OK'
