# 01_backup.ps1 - Sauvegarde de l'etat du systeme avant tweaks

$BACKUP_DIR = Join-Path (Split-Path $PSScriptRoot) "backup"
New-Item -ItemType Directory -Force -Path $BACKUP_DIR | Out-Null

# Point de restauration systeme
Write-Host "    Creation point de restauration... " -NoNewline
try {
    Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
    Checkpoint-Computer `
        -Description "OptiPack - Avant tweaks $(Get-Date -Format 'yyyy-MM-dd HH:mm')" `
        -RestorePointType MODIFY_SETTINGS `
        -ErrorAction Stop
    Write-Host "[OK]" -ForegroundColor Green
} catch {
    Write-Host "[AVERTISSEMENT: $($_.Exception.Message)]" -ForegroundColor Yellow
    Write-Host "    Le point de restauration peut echouer si un autre a ete cree recemment."
}

# Export etat des services (pour restauration precise)
$services = @(
    'SysMain','DPS','Spooler','TabletInputService','RmSvc',
    'DiagTrack','dmwappushservice','WSearch','DoSvc','WerSvc'
)
$serviceState = @{}
foreach ($svc in $services) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) { $serviceState[$svc] = $s.StartType.ToString() }
}
$serviceState | ConvertTo-Json | Set-Content "$BACKUP_DIR\services_state.json" -Encoding UTF8
Write-Host "    Etat des services sauvegarde -> backup\services_state.json"

# Export des cles de registre modifiees
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
Write-Host "    Cles registre exportees -> backup\"

Write-Host "    Sauvegarde complete : $BACKUP_DIR"
