#Requires -RunAsAdministrator
# restore\usb_power.ps1 - Restore USB device power management
#
# Reads backup\usb_power_state.json and restores each device to its original state.
# If no backup is found, removes the PnpCapabilities override on all connected USB
# devices as a safe fallback (lets Windows re-enable its default behavior).

$BACKUP_DIR = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "backup"
$backupFile  = Join-Path $BACKUP_DIR "usb_power_state.json"

if (Test-Path $backupFile) {
    $usbBackup = Get-Content $backupFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $restored  = 0
    $skipped   = 0

    foreach ($entry in $usbBackup.PSObject.Properties) {
        $id    = $entry.Name
        $state = $entry.Value

        $devParamsPath = $state.DevParamsPath
        if (-not $devParamsPath -or -not (Test-Path $devParamsPath)) {
            Write-Host "    USB power restore: '$id' registry path not found, skipping"
            $skipped++
            continue
        }

        $deviceRestored = 0

        # Restore PnpCapabilities
        if ($state.PnpCapabilitiesExisted -and $null -ne $state.PnpCapabilities) {
            Set-ItemProperty -Path $devParamsPath -Name PnpCapabilities -Value ([int]$state.PnpCapabilities) -Type DWord -Force -ErrorAction SilentlyContinue
            $deviceRestored++
        } elseif (-not $state.PnpCapabilitiesExisted) {
            Remove-ItemProperty -Path $devParamsPath -Name PnpCapabilities -ErrorAction SilentlyContinue
            $deviceRestored++
        }

        # Restore WakeEnabled
        $powerPath = $state.WakeEnabledPath
        if ($powerPath -and (Test-Path $powerPath)) {
            if ($state.WakeEnabledExisted -and $null -ne $state.WakeEnabled) {
                Set-ItemProperty -Path $powerPath -Name WakeEnabled -Value ([int]$state.WakeEnabled) -Type DWord -Force -ErrorAction SilentlyContinue
                $deviceRestored++
            } elseif (-not $state.WakeEnabledExisted) {
                Remove-ItemProperty -Path $powerPath -Name WakeEnabled -ErrorAction SilentlyContinue
            }
        }

        # Restore USB selective suspend / enhanced PM keys
        foreach ($pair in @(
            @{ RegKey = 'EnhancedPowerManagementEnabled'; StateKey = 'EnhancedPMEnabled';       ExistedKey = 'EnhancedPMEnabledExisted'   }
            @{ RegKey = 'AllowIdleIrpInD3';               StateKey = 'AllowIdleIrpInD3';        ExistedKey = 'AllowIdleIrpInD3Existed'    }
            @{ RegKey = 'SelectiveSuspendEnabled';         StateKey = 'SelectiveSuspendEnabled'; ExistedKey = 'SelectiveSuspendExisted'    }
        )) {
            if ($state.($pair.ExistedKey) -and $null -ne $state.($pair.StateKey)) {
                Set-ItemProperty -Path $devParamsPath -Name $pair.RegKey -Value ([int]$state.($pair.StateKey)) -Type DWord -Force -ErrorAction SilentlyContinue
                $deviceRestored++
            } elseif (-not $state.($pair.ExistedKey)) {
                Remove-ItemProperty -Path $devParamsPath -Name $pair.RegKey -ErrorAction SilentlyContinue
            }
        }

        if ($deviceRestored -gt 0) {
            $name = if ($state.FriendlyName) { $state.FriendlyName } else { $id }
            Write-Host "    USB power restored: $name ($deviceRestored keys)"
            $restored++
        }
    }

    Write-Host "    USB power restore: $restored device(s) restored, $skipped skipped"

} else {
    Write-Host "    USB power restore: no backup found, removing PnpCapabilities override (fallback)"
    $removed = 0
    $usbDevices = @(
        Get-PnpDevice -Class 'USB'       -Status OK -ErrorAction SilentlyContinue
        Get-PnpDevice -Class 'HIDClass'  -Status OK -ErrorAction SilentlyContinue
        Get-PnpDevice -Class 'USBDevice' -Status OK -ErrorAction SilentlyContinue
    ) | Where-Object { $_.InstanceId -match '^(USB|HID)\\' } |
        Sort-Object InstanceId -Unique

    foreach ($device in $usbDevices) {
        $devParamsPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($device.InstanceId)\Device Parameters"
        if (Test-Path $devParamsPath) {
            Remove-ItemProperty -Path $devParamsPath -Name PnpCapabilities   -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $devParamsPath -Name SelectiveSuspendEnabled -ErrorAction SilentlyContinue
            $removed++
        }
    }
    Write-Host "    USB power restore: PnpCapabilities removed on $removed device(s) (fallback)"
}
