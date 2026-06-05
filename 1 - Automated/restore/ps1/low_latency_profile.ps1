# restore\low_latency_profile.ps1 - Restore Windows Low Latency Profile / CPU boost overrides

$ROOT = Split-Path (Split-Path $PSScriptRoot)
$BACKUP_DIR = Join-Path $ROOT 'backup'
$BACKUP_FILE = Join-Path $BACKUP_DIR 'low_latency_profile_state.json'

function Get-RemainingRegistryValueCount {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        return 0
    }

    $noise = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
    $props = (Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue).PSObject.Properties |
        Where-Object { $noise -notcontains $_.Name }
    return @($props).Count
}

if (-not (Test-Path $BACKUP_FILE)) {
    Write-Host '    Low Latency Profile restore: no backup found, skipping.'
    return
}

try {
    $backup = Get-Content -LiteralPath $BACKUP_FILE -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Host "    [WARNING] Could not read Low Latency Profile backup: $($_.Exception.Message)" -ForegroundColor Yellow
    return
}

if (-not $backup.features) {
    Write-Host '    Low Latency Profile restore: backup has no feature entries, skipping.'
    return
}

$restored = 0
$removed = 0
$skipped = 0

foreach ($entry in $backup.features.PSObject.Properties) {
    $featureId = $entry.Name
    $state = $entry.Value
    $path = [string]$state.Path

    if ([string]::IsNullOrWhiteSpace($path)) {
        $skipped++
        continue
    }

    if ($state.KeyExisted -and -not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    if (Test-Path $path) {
        if ($state.EnabledStateExisted -and $null -ne $state.EnabledState) {
            New-ItemProperty -Path $path -Name 'EnabledState' -Value ([int]$state.EnabledState) -PropertyType DWord -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $path -Name 'EnabledState' -ErrorAction SilentlyContinue
        }

        if ($state.EnabledStateOptionsExisted -and $null -ne $state.EnabledStateOptions) {
            New-ItemProperty -Path $path -Name 'EnabledStateOptions' -Value ([int]$state.EnabledStateOptions) -PropertyType DWord -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $path -Name 'EnabledStateOptions' -ErrorAction SilentlyContinue
        }

        if ($state.VariantExisted -and $null -ne $state.Variant) {
            New-ItemProperty -Path $path -Name 'Variant' -Value ([int]$state.Variant) -PropertyType DWord -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $path -Name 'Variant' -ErrorAction SilentlyContinue
        }

        if ($state.VariantPayloadExisted -and $null -ne $state.VariantPayload) {
            New-ItemProperty -Path $path -Name 'VariantPayload' -Value ([int]$state.VariantPayload) -PropertyType DWord -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $path -Name 'VariantPayload' -ErrorAction SilentlyContinue
        }

        if ($state.VariantPayloadKindExisted -and $null -ne $state.VariantPayloadKind) {
            New-ItemProperty -Path $path -Name 'VariantPayloadKind' -Value ([int]$state.VariantPayloadKind) -PropertyType DWord -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $path -Name 'VariantPayloadKind' -ErrorAction SilentlyContinue
        }

        if (-not $state.KeyExisted) {
            $remainingChildren = @(Get-ChildItem -Path $path -ErrorAction SilentlyContinue)
            $remainingValueCount = Get-RemainingRegistryValueCount -Path $path
            if ($remainingChildren.Count -eq 0 -and $remainingValueCount -eq 0) {
                Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
                $removed++
            }
        }

        $restored++
        Write-Host "    Low Latency Profile restored: $featureId"
    } else {
        $skipped++
        Write-Host "    Low Latency Profile restore: $featureId path missing, skipping"
    }
}

Write-Host "    Low Latency Profile restore: $restored feature(s) restored, $removed override key(s) removed, $skipped skipped"
Write-Host '    Restart required for Windows FeatureManagement changes to fully apply.'
