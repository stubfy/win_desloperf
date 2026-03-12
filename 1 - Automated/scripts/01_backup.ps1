# 01_backup.ps1 - System state backup before tweaks

$BACKUP_DIR = Join-Path (Split-Path $PSScriptRoot) "backup"
New-Item -ItemType Directory -Force -Path $BACKUP_DIR | Out-Null

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
$services = @(
    'SysMain','DPS','Spooler','TabletInputService','RmSvc',
    'DiagTrack','dmwappushservice','WSearch','DoSvc','WerSvc',
    'PhoneSvc','SCardSvr','ScDeviceEnum','SEMgrSvc','WpcMonSvc',
    'lfsvc','MapsBroker','RemoteRegistry','SharedAccess',
    # Added services (source: Chris Titus WinUtil)
    'CDPSvc','InventorySvc','PcaSvc','StorSvc','UsoSvc',
    'WpnService','camsvc','edgeupdate','edgeupdatem','BITS',
    'AssignedAccessManagerSvc','WSAIFabricSvc'
)
$serviceState = @{}
foreach ($svc in $services) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) { $serviceState[$svc] = $s.StartType.ToString() }
}
$serviceState | ConvertTo-Json | Set-Content "$BACKUP_DIR\services_state.json" -Encoding UTF8
Write-Host "    Service states saved -> backup\services_state.json"

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
