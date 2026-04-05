# restore\performance.ps1 - Restore BCD, power plan, USB selective suspend,
# disk write cache policy, Memory Compression
# Combines: restore\bcdedit.ps1, restore\power.ps1, restore\usb.ps1
#
# Rollback: undoes performance.ps1 tweaks (disabledynamictick, power plan, USB
# suspend, disk write cache policy, memory compression)

$ROOT = Split-Path (Split-Path $PSScriptRoot)
$BACKUP_DIR = Join-Path $ROOT 'backup'
$DISK_CACHE_BACKUP_FILE = Join-Path $BACKUP_DIR 'disk_write_cache_state.json'

. (Join-Path $ROOT 'scripts\ps1\storage_write_cache_helpers.ps1')

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

# === SECTION: Restore boot configuration ===

bcdedit /deletevalue disabledynamictick 2>&1 | Out-Null
Write-Host '    disabledynamictick removed (dynamic tick re-enabled)'

bcdedit /set bootmenupolicy standard 2>&1 | Out-Null
Write-Host '    bootmenupolicy = standard (graphical recovery options restored)'

# === SECTION: Restore power plan ===

# Re-enable hibernation
powercfg -h on 2>&1 | Out-Null
Write-Host '    Hibernation re-enabled.'

# Activate the Balanced plan (built-in Windows GUID, always present)
powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null
Write-Host '    Balanced plan activated (381b4222-f694-41f0-9685-ff5bb260df2e)'

# Note: the Bitsum Highest Performance plan (5a39c962-...) is kept available in
# power options after restore. Duplicate "Ultimate Performance" plans were already
# cleaned up by performance.ps1 during the original run.
Write-Host '    Note: Bitsum Highest Performance plan (5a39c962-...) remains available in power options.' -ForegroundColor Gray
Write-Host '    Delete it manually if desired: powercfg -delete 5a39c962-8fb2-4c72-8843-936f1d325503' -ForegroundColor Gray

# === SECTION: Restore USB selective suspend ===

$activeLine = powercfg -getactivescheme 2>&1 | Out-String
$scheme     = [regex]::Match($activeLine, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value

if (-not $scheme) {
    Write-Host '    ERROR: unable to determine active plan GUID.' -ForegroundColor Red
} else {
    powercfg /setacvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>&1 | Out-Null
    powercfg /setdcvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>&1 | Out-Null
    powercfg /setactive $scheme 2>&1 | Out-Null
    Write-Host "    USB selective suspend re-enabled on: $scheme"
}

# === SECTION: Restore disk write cache policy ===

$restoredFromBackup = $false
if (Test-Path $DISK_CACHE_BACKUP_FILE) {
    try {
        $diskBackup = Get-Content -LiteralPath $DISK_CACHE_BACKUP_FILE -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $restored  = 0
        $skipped   = 0

        foreach ($entry in $diskBackup.PSObject.Properties) {
            $diskId = $entry.Name
            $state = $entry.Value
            $diskPath = if ($state.DiskParametersPath) {
                [string]$state.DiskParametersPath
            } elseif ($state.DeviceParametersPath) {
                Join-Path ([string]$state.DeviceParametersPath) 'Disk'
            } else {
                "HKLM:\SYSTEM\CurrentControlSet\Enum\$diskId\Device Parameters\Disk"
            }

            $deviceParamsPath = Split-Path -Path $diskPath -Parent
            if (-not (Test-Path $deviceParamsPath)) {
                Write-Host "    Disk write cache restore: '$diskId' registry path not found, skipping"
                $skipped++
                continue
            }

            $deviceRestored = 0
            $diskKeyNeeded = ($state.UserWriteCacheSettingExisted -and $null -ne $state.UserWriteCacheSetting) -or
                             ($state.CacheIsPowerProtectedExisted -and $null -ne $state.CacheIsPowerProtected)
            if ($diskKeyNeeded -and -not (Test-Path $diskPath)) {
                New-Item -Path $diskPath -Force | Out-Null
            }

            if ($state.UserWriteCacheSettingExisted -and $null -ne $state.UserWriteCacheSetting) {
                New-ItemProperty -Path $diskPath -Name 'UserWriteCacheSetting' -Value ([int]$state.UserWriteCacheSetting) -PropertyType DWord -Force | Out-Null
                $deviceRestored++
            } elseif (Test-Path $diskPath) {
                Remove-ItemProperty -Path $diskPath -Name 'UserWriteCacheSetting' -ErrorAction SilentlyContinue
            }

            if ($state.CacheIsPowerProtectedExisted -and $null -ne $state.CacheIsPowerProtected) {
                New-ItemProperty -Path $diskPath -Name 'CacheIsPowerProtected' -Value ([int]$state.CacheIsPowerProtected) -PropertyType DWord -Force | Out-Null
                $deviceRestored++
            } elseif (Test-Path $diskPath) {
                Remove-ItemProperty -Path $diskPath -Name 'CacheIsPowerProtected' -ErrorAction SilentlyContinue
            }

            if (-not $state.DiskKeyExisted -and (Test-Path $diskPath)) {
                $remainingChildren = @(Get-ChildItem -Path $diskPath -ErrorAction SilentlyContinue)
                $remainingValueCount = Get-RemainingRegistryValueCount -Path $diskPath
                if ($remainingChildren.Count -eq 0 -and $remainingValueCount -eq 0) {
                    Remove-Item -Path $diskPath -Force -ErrorAction SilentlyContinue
                }
            }

            if ($deviceRestored -gt 0 -or -not $state.DiskKeyExisted) {
                $label = if ($state.FriendlyName) { [string]$state.FriendlyName } else { $diskId }
                Write-Host "    Disk write cache restored: $label"
                $restored++
            }
        }

        Write-Host "    Disk write cache restore: $restored disk(s) restored, $skipped skipped"
        $restoredFromBackup = $true
    } catch {
        Write-Host "    [WARNING] Could not read disk write-cache backup: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (-not $restoredFromBackup) {
    Write-Host '    Disk write cache restore: no usable backup found, forcing safe defaults (fallback)'
    $targets = @(Get-StorageWriteCacheDiskTargets -InternalOnly)
    if ($targets.Count -eq 0) {
        Write-Host '    Disk write cache restore: no internal SSD/NVMe disk detected for fallback.'
    } else {
        $restored = 0
        foreach ($target in $targets) {
            $diskPath = $target.DiskParametersPath
            if (-not (Test-Path $diskPath)) {
                New-Item -Path $diskPath -Force | Out-Null
            }

            New-ItemProperty -Path $diskPath -Name 'UserWriteCacheSetting' -Value 0 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $diskPath -Name 'CacheIsPowerProtected' -Value 0 -PropertyType DWord -Force | Out-Null
            Write-Host "    Disk write cache fallback: $(Get-StorageWriteCacheDiskLabel -DiskTarget $target) -> UserWriteCacheSetting=0, CacheIsPowerProtected=0"
            $restored++
        }
        Write-Host "    Disk write cache restore: fallback applied to $restored disk(s)"
    }
}

# === SECTION: Restore Memory Compression ===

Enable-MMAgent -MemoryCompression
Write-Host '    Memory Compression re-enabled'
