#Requires -RunAsAdministrator
# usb_power.ps1 - Disable USB device power management
#
# Disables "Allow the computer to turn off this device to save power" and
# "Allow this device to wake the computer" for all connected USB and HID devices.
#
# Re-run after plugging new USB peripherals via 8 - USB Power\set_usb_power.bat.
#
# Backup: merges new device states into backup\usb_power_state.json.
# Existing entries (original pre-tweak states) are never overwritten, so the
# restore script always recovers to the true original state even after re-runs.

$BACKUP_DIR = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "backup"
$backupFile  = Join-Path $BACKUP_DIR "usb_power_state.json"

. (Join-Path $PSScriptRoot 'usb_power_helpers.ps1')

# ── Enumerate connected USB and HID devices ────────────────────────────────────
$rawDevices = @(Get-UsbPowerTargetDevices) | Where-Object { $_.InstanceId -match '^(USB|HID)\\' } |
    Sort-Object InstanceId -Unique

$powerDeviceEnableInstances = @(Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceName -match '^(USB|HID)\\' })
$powerDeviceWakeEnableInstances = @(Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceWakeEnable -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceName -match '^(USB|HID)\\' })

# ── Backup (merge: add new devices, never overwrite original states) ───────────
$existingBackup = [ordered]@{}
if (Test-Path $backupFile) {
    try {
        $loaded = Get-Content $backupFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $loaded.PSObject.Properties) {
            $existingBackup[$prop.Name] = $prop.Value
        }
    } catch {
        Write-Host "    [WARNING] Could not read existing USB backup, will overwrite." -ForegroundColor Yellow
    }
}

$mergedBackup = [ordered]@{}
$newEntries   = 0

foreach ($device in $rawDevices) {
    $id           = $device.InstanceId
    $devParamsPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$id\Device Parameters"

    if ($existingBackup.Contains($id)) {
        $state = $existingBackup[$id]
        Add-UsbPowerWmiBackupState `
            -State $state `
            -InstanceId $id `
            -PowerDeviceEnableInstances $powerDeviceEnableInstances `
            -PowerDeviceWakeEnableInstances $powerDeviceWakeEnableInstances
        $mergedBackup[$id] = $state
        continue
    }

    if (-not (Test-Path $devParamsPath)) { continue }

    $state = [ordered]@{
        FriendlyName              = $device.FriendlyName
        DevParamsPath             = $devParamsPath
        PnpCapabilities           = $null
        PnpCapabilitiesExisted    = $false
        WakeEnabledPath           = (Join-Path $devParamsPath 'Power')
        WakeEnabled               = $null
        WakeEnabledExisted        = $false
        EnhancedPMEnabled         = $null
        EnhancedPMEnabledExisted  = $false
        AllowIdleIrpInD3          = $null
        AllowIdleIrpInD3Existed   = $false
        SelectiveSuspendEnabled   = $null
        SelectiveSuspendExisted   = $false
    }

    try {
        $state.PnpCapabilities        = (Get-ItemProperty -Path $devParamsPath -Name PnpCapabilities -ErrorAction Stop).PnpCapabilities
        $state.PnpCapabilitiesExisted = $true
    } catch {}

    $powerPath = Join-Path $devParamsPath 'Power'
    if (Test-Path $powerPath) {
        try {
            $state.WakeEnabled       = (Get-ItemProperty -Path $powerPath -Name WakeEnabled -ErrorAction Stop).WakeEnabled
            $state.WakeEnabledExisted = $true
        } catch {}
    }

    foreach ($pair in @(
        @{ Key = 'EnhancedPowerManagementEnabled'; StateKey = 'EnhancedPMEnabled'; ExistedKey = 'EnhancedPMEnabledExisted' }
        @{ Key = 'AllowIdleIrpInD3';               StateKey = 'AllowIdleIrpInD3';  ExistedKey = 'AllowIdleIrpInD3Existed'  }
        @{ Key = 'SelectiveSuspendEnabled';         StateKey = 'SelectiveSuspendEnabled'; ExistedKey = 'SelectiveSuspendExisted' }
    )) {
        try {
            $state[$pair.StateKey]   = (Get-ItemProperty -Path $devParamsPath -Name $pair.Key -ErrorAction Stop).($pair.Key)
            $state[$pair.ExistedKey] = $true
        } catch {
            $state[$pair.ExistedKey] = $false
        }
    }

    Add-UsbPowerWmiBackupState `
        -State $state `
        -InstanceId $id `
        -PowerDeviceEnableInstances $powerDeviceEnableInstances `
        -PowerDeviceWakeEnableInstances $powerDeviceWakeEnableInstances

    $mergedBackup[$id] = $state
    $newEntries++
}

# Preserve entries for devices not currently connected (offline devices)
foreach ($id in $existingBackup.Keys) {
    if (-not $mergedBackup.Contains($id)) {
        $mergedBackup[$id] = $existingBackup[$id]
    }
}

try {
    if (-not (Test-Path $BACKUP_DIR)) { New-Item -Path $BACKUP_DIR -ItemType Directory -Force | Out-Null }
    $mergedBackup | ConvertTo-Json -Depth 5 | Set-Content $backupFile -Encoding UTF8
    $totalEntries = $mergedBackup.Count
    Write-Host "    USB power states saved -> backup\usb_power_state.json ($totalEntries total, $newEntries new)"
} catch {
    Write-Host "    [WARNING] Could not save USB power backup: $_" -ForegroundColor Yellow
}

# ── Apply: disable power management on all connected USB/HID devices ──────────
$modified = 0
$skipped  = 0

foreach ($device in $rawDevices) {
    $id           = $device.InstanceId
    $devParamsPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$id\Device Parameters"

    if (-not (Test-Path $devParamsPath)) {
        $skipped++
        continue
    }

    $deviceModified = 0

    # PnpCapabilities = 0x18: bit3=disable turn-off, bit4=disable wake
    try {
        $cur = (Get-ItemProperty -Path $devParamsPath -Name PnpCapabilities -ErrorAction Stop).PnpCapabilities
        if ($cur -ne 24) {
            Set-ItemProperty -Path $devParamsPath -Name PnpCapabilities -Value 24 -Type DWord -Force -ErrorAction SilentlyContinue
            $deviceModified++
        }
    } catch {
        # Key doesn't exist yet — create it
        Set-ItemProperty -Path $devParamsPath -Name PnpCapabilities -Value 24 -Type DWord -Force -ErrorAction SilentlyContinue
        $deviceModified++
    }

    # USB selective suspend / enhanced PM keys (only disable if the key already exists)
    foreach ($keyName in @('EnhancedPowerManagementEnabled', 'AllowIdleIrpInD3', 'SelectiveSuspendEnabled')) {
        try {
            $cur = (Get-ItemProperty -Path $devParamsPath -Name $keyName -ErrorAction Stop).$keyName
            if ($cur -ne 0) {
                Set-ItemProperty -Path $devParamsPath -Name $keyName -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                $deviceModified++
            }
        } catch {} # Key absent — nothing to disable
    }

    # WakeEnabled under Device Parameters\Power
    $powerPath = Join-Path $devParamsPath 'Power'
    if (Test-Path $powerPath) {
        try {
            $cur = (Get-ItemProperty -Path $powerPath -Name WakeEnabled -ErrorAction Stop).WakeEnabled
            if ($cur -ne 0) {
                Set-ItemProperty -Path $powerPath -Name WakeEnabled -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                $deviceModified++
            }
        } catch {} # Key absent — nothing to disable
    }

    $deviceModified += Disable-UsbPowerWmiInstances -InstanceId $id -Instances $powerDeviceEnableInstances
    $deviceModified += Disable-UsbPowerWmiInstances -InstanceId $id -Instances $powerDeviceWakeEnableInstances

    if ($deviceModified -gt 0) {
        $name = if ($device.FriendlyName) { $device.FriendlyName } else { $id }
        Write-Host "    USB power off: $name ($deviceModified change(s))"
        $modified++
    }
}

Write-Host "    USB power management: $modified device(s) modified, $skipped device(s) skipped (no Device Parameters)"
