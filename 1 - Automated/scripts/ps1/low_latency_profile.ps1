# low_latency_profile.ps1 - Enable Windows Low Latency Profile / CPU boost
#
# Uses native Windows FeatureManagement registry overrides instead of ViVeTool.
# The current feature ID set is tied to the Windows 11 KB5089573 / June 2026
# Low Latency Profile rollout. Unsupported builds will keep the overrides stored
# but may ignore them until the matching feature payload exists.
#
# ViVeTool's default /enable path writes boot overrides at priority User (8)
# using obfuscated feature IDs:
#   HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\<obfuscated id>
# We mirror that boot-store registry layout directly and do not touch runtime
# state because that requires the Windows Feature Management API call.
#
# Rollback: restore\low_latency_profile.ps1 reads backup\low_latency_profile_state.json
# and restores the exact prior override values.

$ROOT = Split-Path (Split-Path $PSScriptRoot)
$BACKUP_DIR = Join-Path $ROOT 'backup'
$BACKUP_FILE = Join-Path $BACKUP_DIR 'low_latency_profile_state.json'
$FEATURE_PRIORITY = 8
$OVERRIDE_ROOT = "HKLM:\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\$FEATURE_PRIORITY"

$FEATURE_IDS = @(
    '58989092'
    '60716524'
    '48433719'
    '61391826'
)

function Get-FeatureOverrideState {
    param(
        [Parameter(Mandatory)][string]$FeatureId,
        [Parameter(Mandatory)][uint32]$ObfuscatedId
    )

    $path = Join-Path $OVERRIDE_ROOT $ObfuscatedId.ToString()
    $props = $null
    $keyExists = Test-Path $path
    if ($keyExists) {
        $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    }

    $enabledStateExisted = $false
    $enabledState = $null
    $enabledStateOptionsExisted = $false
    $enabledStateOptions = $null
    $variantExisted = $false
    $variant = $null
    $variantPayloadExisted = $false
    $variantPayload = $null
    $variantPayloadKindExisted = $false
    $variantPayloadKind = $null

    if ($props) {
        $enabledStateExisted = $props.PSObject.Properties.Name -contains 'EnabledState'
        if ($enabledStateExisted) { $enabledState = [int]$props.EnabledState }

        $enabledStateOptionsExisted = $props.PSObject.Properties.Name -contains 'EnabledStateOptions'
        if ($enabledStateOptionsExisted) { $enabledStateOptions = [int]$props.EnabledStateOptions }

        $variantExisted = $props.PSObject.Properties.Name -contains 'Variant'
        if ($variantExisted) { $variant = [int]$props.Variant }

        $variantPayloadExisted = $props.PSObject.Properties.Name -contains 'VariantPayload'
        if ($variantPayloadExisted) { $variantPayload = [int]$props.VariantPayload }

        $variantPayloadKindExisted = $props.PSObject.Properties.Name -contains 'VariantPayloadKind'
        if ($variantPayloadKindExisted) { $variantPayloadKind = [int]$props.VariantPayloadKind }
    }

    return [ordered]@{
        FeatureId                  = $FeatureId
        ObfuscatedId               = $ObfuscatedId.ToString()
        Priority                   = $FEATURE_PRIORITY
        Path                       = $path
        KeyExisted                 = [bool]$keyExists
        EnabledState               = $enabledState
        EnabledStateExisted        = [bool]$enabledStateExisted
        EnabledStateOptions        = $enabledStateOptions
        EnabledStateOptionsExisted = [bool]$enabledStateOptionsExisted
        Variant                    = $variant
        VariantExisted             = [bool]$variantExisted
        VariantPayload             = $variantPayload
        VariantPayloadExisted      = [bool]$variantPayloadExisted
        VariantPayloadKind         = $variantPayloadKind
        VariantPayloadKindExisted  = [bool]$variantPayloadKindExisted
    }
}

function ConvertTo-ObfuscatedFeatureId {
    param([Parameter(Mandatory)][uint32]$FeatureId)

    $mask = [uint64]4294967295
    $x = ([uint64]$FeatureId -bxor [uint64]1947605582) -band $mask
    $x = (($x -shr 16) -bor ($x -shl 16)) -band $mask
    $x = ((($x -band [uint64]4278255360) -shr 8) -bor (($x -band [uint64]16711935) -shl 8)) -band $mask
    $x = ($x -bxor [uint64]2410822991) -band $mask
    # ViVe's RotateRight32(value, -1) is equivalent to rotate-left by one bit.
    $x = ((($x -shl 1) -band $mask) -bor ($x -shr 31)) -band $mask
    $x = ($x -bxor [uint64]2201929983) -band $mask

    return [uint32]$x
}

function Read-LowLatencyBackup {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
}

if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
}

$existingBackup = $null
try {
    $existingBackup = Read-LowLatencyBackup -Path $BACKUP_FILE
} catch {
    Write-Host "    [WARNING] Could not read Low Latency Profile backup: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host '    Low Latency Profile skipped to avoid losing the original rollback state.' -ForegroundColor Yellow
    return
}

$mergedFeatureState = [ordered]@{}
if ($existingBackup -and $existingBackup.features) {
    foreach ($prop in $existingBackup.features.PSObject.Properties) {
        $mergedFeatureState[$prop.Name] = $prop.Value
    }
}

$newEntries = 0
foreach ($featureId in $FEATURE_IDS) {
    $obfuscatedId = ConvertTo-ObfuscatedFeatureId -FeatureId ([uint32]$featureId)
    if (-not $mergedFeatureState.Contains($featureId)) {
        $mergedFeatureState[$featureId] = Get-FeatureOverrideState -FeatureId $featureId -ObfuscatedId $obfuscatedId
        $newEntries++
    }
}

$backupPayload = [ordered]@{
    _meta = [ordered]@{
        schemaVersion = 1
        savedAt       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        overrideRoot  = $OVERRIDE_ROOT
        priority      = $FEATURE_PRIORITY
        note          = 'Original FeatureManagement override values preserved before enabling Low Latency Profile / CPU boost.'
    }
    features = $mergedFeatureState
}

try {
    $backupPayload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $BACKUP_FILE -Encoding UTF8
    Write-Host "    Low Latency Profile state saved -> backup\low_latency_profile_state.json ($($mergedFeatureState.Count) feature(s), $newEntries new)"
} catch {
    Write-Host "    [WARNING] Could not save Low Latency Profile backup: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host '    Low Latency Profile skipped to avoid losing the original rollback state.' -ForegroundColor Yellow
    return
}

$modified = 0
$already = 0
foreach ($featureId in $FEATURE_IDS) {
    $obfuscatedId = ConvertTo-ObfuscatedFeatureId -FeatureId ([uint32]$featureId)
    $path = Join-Path $OVERRIDE_ROOT $obfuscatedId.ToString()
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    $currentEnabledState = $null
    $currentEnabledStateOptions = $null
    try { $currentEnabledState = [int](Get-ItemProperty -Path $path -Name 'EnabledState' -ErrorAction Stop).EnabledState } catch {}
    try { $currentEnabledStateOptions = [int](Get-ItemProperty -Path $path -Name 'EnabledStateOptions' -ErrorAction Stop).EnabledStateOptions } catch {}

    New-ItemProperty -Path $path -Name 'EnabledState' -Value 2 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $path -Name 'EnabledStateOptions' -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $path -Name 'Variant' -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $path -Name 'VariantPayload' -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $path -Name 'VariantPayloadKind' -Value 0 -PropertyType DWord -Force | Out-Null

    if ($currentEnabledState -eq 2 -and $currentEnabledStateOptions -eq 0) {
        $already++
    } else {
        $modified++
    }

    Write-Host "    FeatureManagement override enabled: $featureId -> priority $FEATURE_PRIORITY / key $obfuscatedId"
}

Write-Host "    Low Latency Profile / CPU boost: $modified feature override(s) changed, $already already enabled"
Write-Host '    Restart required for Windows FeatureManagement changes to fully apply.'
