# 01_backup.ps1 - System state backup before tweaks
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
#      Records the pre-tweak startup type of every service tracked by 03_services.ps1.
#      restore\02_services.ps1 reads this file to restore each service precisely to
#      its original startup type, including the DelayedAutoStart distinction.
#
#   3. Firewall profile state export (backup\firewall_state.json):
#      Records the Enabled/Disabled state of each firewall profile (Domain, Private,
#      Public) before 18_firewall.ps1 disables them. restore\18_firewall.ps1 uses
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

$BACKUP_DIR = Join-Path (Split-Path $PSScriptRoot) "backup"
New-Item -ItemType Directory -Force -Path $BACKUP_DIR | Out-Null
$serviceCatalog = & (Join-Path $PSScriptRoot '03_services.ps1') -ExportCatalogOnly

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

# System restore point
Write-Host "    Creating restore point... " -NoNewline
try {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    Checkpoint-Computer `
        -Description "OptiPack - Before tweaks $(Get-Date -Format 'yyyy-MM-dd HH:mm')" `
        -RestorePointType MODIFY_SETTINGS `
        -ErrorAction Stop
    Write-Host "[OK]" -ForegroundColor Green
} catch {
    Write-Host "[WARNING: $($_.Exception.Message)]" -ForegroundColor Yellow
    Write-Host "    Restore point may fail if another was created recently."
}

# Export service states (for precise rollback)
$serviceState = @{}
foreach ($svc in $serviceCatalog.Tracked) {
    $startupType = Get-ExactServiceStartupType -Name $svc
    if ($startupType) { $serviceState[$svc] = $startupType }
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
