# backup.ps1 - System state backup before tweaks
#
# Creates multiple backup layers to support rollback:
#
#   1. System Restore Point (Checkpoint-Computer):
#      Creates a "MODIFY_SETTINGS" restore point via Volume Shadow Copy Service.
#      This is the safest rollback method as it snapshots the full system state.
#      Windows may refuse to create a restore point if one was created within the
#      last 24 hours on some builds; the error is non-fatal and logged as a warning.
#      The system drive must have System Protection enabled (ComputerRestore -Drive C:\).
#
#   2. Service state export (backup\services_state.json):
#      Records the pre-tweak startup type of every service tracked by services.ps1.
#      restore\services.ps1 reads this file to restore each service precisely to
#      its original startup type, including the DelayedAutoStart distinction.
#
#   3. Firewall profile state export (backup\firewall_state.json):
#      Records the Enabled/Disabled state of each firewall profile (Domain, Private,
#      Public) before 1 - Automated\scripts\ps1\firewall.ps1 disables them. restore\firewall.ps1 uses
#      this to restore the exact original state rather than blindly re-enabling all
#      profiles (which would be wrong if a profile was already disabled before the pack ran).
#
#   4. Registry key exports (backup\backup_*.reg):
#      Exports the full registry subtrees that tweaks_consolidated.reg modifies.
#      Provides a human-readable fallback for manual recovery.
#      Exported subtrees: HKLM\Control, HKCU\Desktop, HKCU\Mouse, HKCU\Keyboard,
#      HKLM\SystemProfile (MMCSS), HKLM\GraphicsDrivers (HAGS),
#      HKLM\DeviceGuard (VBS), HKLM\PrefetchParameters (Prefetcher).
#
#   5. Automatic daily registry backup (EnablePeriodicBackup=1, BackupCount=2):
#      Instructs the Configuration Manager to save a copy of the registry hives
#      to RegBack every 24 hours, retaining the last 2 copies. Provides an
#      additional safety net independent of VSS.

$BACKUP_DIR = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "backup"
New-Item -ItemType Directory -Force -Path $BACKUP_DIR | Out-Null
$serviceCatalog = & (Join-Path $PSScriptRoot 'services.ps1') -ExportCatalogOnly

. (Join-Path $PSScriptRoot 'affinity_helpers.ps1')

function Get-ExactServiceStartupType {
    param([Parameter(Mandatory)][string]$Name)

    $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    try {
        $props = Get-ItemProperty -Path $serviceKey -ErrorAction Stop
    } catch {
        return $null
    }

    $delayedAutoStart = ($props.PSObject.Properties.Name -contains 'DelayedAutoStart' -and $props.DelayedAutoStart -eq 1)
    switch ([int]$props.Start) {
        2 { if ($delayedAutoStart) { return 'AutomaticDelayedStart' } else { return 'Automatic' } }
        3 { return 'Manual' }
        4 { return 'Disabled' }
        default { return $null }
    }
}

function Resolve-TrackedServiceNames {
    param([Parameter(Mandatory)][string]$Name)

    $resolved = @(Get-Service -Name $Name, "${Name}_*" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name -Unique)

    if ($resolved.Count -gt 0) {
        return @($resolved | Sort-Object -Unique)
    }

    return @($Name)
}

# System restore point
Write-Host "    Creating restore point... " -NoNewline
$restorePointCreated = $false
try {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    Checkpoint-Computer `
        -Description "OptiPack - Before tweaks $(Get-Date -Format 'yyyy-MM-dd HH:mm')" `
        -RestorePointType MODIFY_SETTINGS `
        -ErrorAction Stop
    $restorePointCreated = $true
    Write-Host "[OK]" -ForegroundColor Green
} catch {
    $message = $_.Exception.Message
    if ($message -match 'already been created within the past 1440 minutes') {
        Write-Host "[SKIPPED]" -ForegroundColor Yellow
        Write-Host "    Restore point not created: Windows already has one from the last 24 hours."
    } else {
        Write-Host "[WARNING]" -ForegroundColor Yellow
        Write-Host "    Restore point failed: $message" -ForegroundColor Yellow
    }
}

# Export service states (for precise rollback)
$serviceState = @{}
foreach ($svc in $serviceCatalog.Tracked) {
    foreach ($resolvedSvc in (Resolve-TrackedServiceNames -Name $svc)) {
        $startupType = Get-ExactServiceStartupType -Name $resolvedSvc
        if ($startupType) { $serviceState[$resolvedSvc] = $startupType }
    }
}
$serviceState | ConvertTo-Json | Set-Content "$BACKUP_DIR\services_state.json" -Encoding UTF8
Write-Host "    Service states saved -> backup\services_state.json"

# Export firewall profile states (for precise rollback)
$firewallState = @{}
try {
    foreach ($profile in Get-NetFirewallProfile -ErrorAction Stop) {
        $firewallState[$profile.Name] = [bool]$profile.Enabled
    }
    $firewallState | ConvertTo-Json | Set-Content "$BACKUP_DIR\firewall_state.json" -Encoding UTF8
    Write-Host "    Firewall states saved -> backup\firewall_state.json"
} catch {
    Write-Host "    [WARNING] Unable to save firewall profile states." -ForegroundColor Yellow
}

# Export NIC power saving state (for precise rollback)
$nicPowerState = @{}
try {
    $powerKeywords = @('EEE','EnergyEfficientEthernet','GreenEthernet','GigabitLite',
        'WakeOnMagicPacket','WakeOnPattern','*PMARPOffload','*PMNSOffload',
        'PowerSavingMode','ReduceSpeedOnPowerDown','WolShutdownLinkSpeed',
        'AutoPowerSaveModeEnabled','EnablePME','AdaptivePowerManagement')
    $powerDisplayNames = @('Energy-Efficient Ethernet','Green Ethernet','Gigabit Lite',
        'Wake on Magic Packet','Wake on Pattern Match','Power Saving Mode','Reduce Speed On Power Down')

    foreach ($adapter in @(Get-NetAdapter -Physical -Status Up -ErrorAction SilentlyContinue)) {
        $adapterState = @{
            PnpDeviceID        = $adapter.PnpDeviceID
            AdvancedProperties = @{}
        }

        $allAdvanced = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue
        foreach ($prop in $allAdvanced) {
            if ($prop.RegistryKeyword -in $powerKeywords -or $prop.DisplayName -in $powerDisplayNames) {
                $adapterState.AdvancedProperties[$prop.RegistryKeyword] = @{
                    DisplayName   = $prop.DisplayName
                    DisplayValue  = $prop.DisplayValue
                    RegistryValue = $prop.RegistryValue
                }
            }
        }

        $devParamsPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($adapter.PnpDeviceID)\Device Parameters"
        $adapterState['PnpCapabilitiesPath'] = $devParamsPath
        try {
            $adapterState['PnpCapabilities']      = (Get-ItemProperty -Path $devParamsPath -Name 'PnpCapabilities' -ErrorAction Stop).PnpCapabilities
            $adapterState['PnpCapabilitiesExisted'] = $true
        } catch {
            $adapterState['PnpCapabilities']      = $null
            $adapterState['PnpCapabilitiesExisted'] = $false
        }

        $powerPath = Join-Path $devParamsPath 'Power'
        $adapterState['WakeEnabledPath'] = $powerPath
        try {
            $adapterState['WakeEnabled']       = (Get-ItemProperty -Path $powerPath -Name 'WakeEnabled' -ErrorAction Stop).WakeEnabled
            $adapterState['WakeEnabledExisted'] = $true
        } catch {
            $adapterState['WakeEnabled']       = $null
            $adapterState['WakeEnabledExisted'] = $false
        }

        $nicPowerState[$adapter.Name] = $adapterState
    }
    $nicPowerState | ConvertTo-Json -Depth 4 | Set-Content "$BACKUP_DIR\nic_power_state.json" -Encoding UTF8
    Write-Host "    NIC power states saved -> backup\nic_power_state.json"
} catch {
    Write-Host "    [WARNING] Unable to save NIC power states." -ForegroundColor Yellow
}

# Export USB device power management state (for precise rollback)
# Only written once: if the file exists (re-run of run_all), original states are preserved.
$usbBackupFile = "$BACKUP_DIR\usb_power_state.json"
if (-not (Test-Path $usbBackupFile)) {
    try {
        $usbPowerState = [ordered]@{}
        $usbDevices = @(
            Get-PnpDevice -Class 'USB'       -Status OK -ErrorAction SilentlyContinue
            Get-PnpDevice -Class 'HIDClass'  -Status OK -ErrorAction SilentlyContinue
            Get-PnpDevice -Class 'USBDevice' -Status OK -ErrorAction SilentlyContinue
        ) | Where-Object { $_.InstanceId -match '^(USB|HID)\\' } |
            Sort-Object InstanceId -Unique

        foreach ($device in $usbDevices) {
            $id           = $device.InstanceId
            $devParamsPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$id\Device Parameters"
            if (-not (Test-Path $devParamsPath)) { continue }

            $state = [ordered]@{
                FriendlyName             = $device.FriendlyName
                DevParamsPath            = $devParamsPath
                PnpCapabilities          = $null
                PnpCapabilitiesExisted   = $false
                WakeEnabledPath          = (Join-Path $devParamsPath 'Power')
                WakeEnabled              = $null
                WakeEnabledExisted       = $false
                EnhancedPMEnabled        = $null
                EnhancedPMEnabledExisted = $false
                AllowIdleIrpInD3         = $null
                AllowIdleIrpInD3Existed  = $false
                SelectiveSuspendEnabled  = $null
                SelectiveSuspendExisted  = $false
            }

            try {
                $state.PnpCapabilities        = (Get-ItemProperty -Path $devParamsPath -Name PnpCapabilities -ErrorAction Stop).PnpCapabilities
                $state.PnpCapabilitiesExisted = $true
            } catch {}

            $powerPath = Join-Path $devParamsPath 'Power'
            if (Test-Path $powerPath) {
                try {
                    $state.WakeEnabled        = (Get-ItemProperty -Path $powerPath -Name WakeEnabled -ErrorAction Stop).WakeEnabled
                    $state.WakeEnabledExisted = $true
                } catch {}
            }

            foreach ($pair in @(
                @{ Key = 'EnhancedPowerManagementEnabled'; StateKey = 'EnhancedPMEnabled';       ExistedKey = 'EnhancedPMEnabledExisted'  }
                @{ Key = 'AllowIdleIrpInD3';               StateKey = 'AllowIdleIrpInD3';        ExistedKey = 'AllowIdleIrpInD3Existed'   }
                @{ Key = 'SelectiveSuspendEnabled';         StateKey = 'SelectiveSuspendEnabled'; ExistedKey = 'SelectiveSuspendExisted'   }
            )) {
                try {
                    $state[$pair.StateKey]   = (Get-ItemProperty -Path $devParamsPath -Name $pair.Key -ErrorAction Stop).($pair.Key)
                    $state[$pair.ExistedKey] = $true
                } catch {
                    $state[$pair.ExistedKey] = $false
                }
            }

            $usbPowerState[$id] = $state
        }
        $usbPowerState | ConvertTo-Json -Depth 5 | Set-Content $usbBackupFile -Encoding UTF8
        Write-Host "    USB power states saved -> backup\usb_power_state.json ($($usbPowerState.Count) devices)"
    } catch {
        Write-Host "    [WARNING] Unable to save USB power states." -ForegroundColor Yellow
    }
} else {
    Write-Host "    USB power states already backed up -> backup\usb_power_state.json (skipped)"
}

# Export interrupt affinity state (GPU + mouse if config present, for rollback)
try {
    $affinityChains = @()

    # GPU chains (all PCI display devices)
    $gpus = Get-PnpDevice -Class Display -Status OK -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match '^PCI\\' }
    foreach ($gpu in $gpus) {
        $chain = Get-PciChainFromDevice -InstanceId $gpu.InstanceId -StartLabel 'GPU' -Quiet
        if ($chain.Count -gt 0) { $affinityChains += , $chain }
    }

    # Mouse chain from saved config (if present)
    $affinityConfigPath = Join-Path $BACKUP_DIR 'affinity_config.json'
    $affinityConfig = Read-AffinityConfig -ConfigPath $affinityConfigPath
    if ($affinityConfig) {
        foreach ($g in $affinityConfig.groups | Where-Object { $_.type -eq 'mouse' }) {
            $chain = Get-PciChainFromDevice -InstanceId $g.instanceId -StartLabel 'USB Controller' -Quiet
            if ($chain.Count -gt 0) { $affinityChains += , $chain }
        }
    }

    $affinityState = Get-AffinityStateForChains -Chains $affinityChains
    $affinityState | ConvertTo-Json -Depth 3 |
        Set-Content "$BACKUP_DIR\affinity_state.json" -Encoding UTF8
    Write-Host "    Affinity states saved -> backup\affinity_state.json"
} catch {
    Write-Host "    [WARNING] Unable to save affinity states." -ForegroundColor Yellow
}

# Export modified registry keys
$regExports = @{
    'HKLM_Control'           = 'HKLM\SYSTEM\CurrentControlSet\Control'
    'HKCU_Desktop'           = 'HKCU\Control Panel\Desktop'
    'HKCU_Mouse'             = 'HKCU\Control Panel\Mouse'
    'HKCU_Keyboard'          = 'HKCU\Control Panel\Keyboard'
    'HKLM_SystemProfile'     = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    'HKLM_GraphicsDrivers'   = 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    'HKLM_DeviceGuard'       = 'HKLM\System\CurrentControlSet\Control\DeviceGuard'
    'HKLM_PrefetchParameters'= 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'
}
foreach ($name in $regExports.Keys) {
    $outFile = "$BACKUP_DIR\backup_$name.reg"
    reg export $regExports[$name] $outFile /y 2>$null | Out-Null
}
Write-Host "    Registry keys exported -> backup\"

# Enable automatic daily registry backup (00:30, 2 copies)
$cmPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'
Set-ItemProperty -Path $cmPath -Name 'EnablePeriodicBackup' -Value 1 -Type DWord -Force
Set-ItemProperty -Path $cmPath -Name 'BackupCount'          -Value 2 -Type DWord -Force
Write-Host "    Automatic daily registry backup enabled (2 copies)"

Write-Host "    Backup complete: $BACKUP_DIR"