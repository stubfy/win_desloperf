# restore\02_services.ps1 - Restore services to their original state

$BACKUP_DIR = Join-Path (Split-Path $PSScriptRoot) "backup"
$stateFile  = Join-Path $BACKUP_DIR "services_state.json"

# Windows default values if no backup available
$defaults = [ordered]@{
    'SysMain'            = 'Automatic'
    'DPS'                = 'Automatic'
    'Spooler'            = 'Automatic'
    'TabletInputService' = 'Manual'
    'RmSvc'              = 'Manual'
    'DiagTrack'          = 'Automatic'
    'dmwappushservice'   = 'Manual'
    'WSearch'            = 'Automatic'
    'WerSvc'             = 'Manual'
    'DoSvc'              = 'Automatic'
    'PhoneSvc'           = 'Manual'
    'SCardSvr'           = 'Manual'
    'ScDeviceEnum'       = 'Manual'
    'SEMgrSvc'           = 'Manual'
    'WpcMonSvc'          = 'Disabled'
    'lfsvc'              = 'Manual'
    'MapsBroker'         = 'Automatic'
    'RetailDemo'         = 'Disabled'
    'RemoteRegistry'     = 'Disabled'
    'SharedAccess'       = 'Disabled'
    # Added services (source: Chris Titus WinUtil) - Windows default values
    'CDPSvc'                   = 'Automatic'
    'InventorySvc'             = 'Automatic'
    'PcaSvc'                   = 'Automatic'
    'StorSvc'                  = 'Automatic'
    'UsoSvc'                   = 'Automatic'
    'WpnService'               = 'Automatic'
    'camsvc'                   = 'Automatic'
    'edgeupdate'               = 'Automatic'
    'edgeupdatem'              = 'Manual'
    'BITS'                     = 'Automatic'
    'AssignedAccessManagerSvc' = 'Manual'
    'WSAIFabricSvc'            = 'Automatic'
}

# Load saved state if available
if (Test-Path $stateFile) {
    $saved = Get-Content $stateFile | ConvertFrom-Json
    foreach ($prop in $saved.PSObject.Properties) {
        $defaults[$prop.Name] = $prop.Value
    }
    Write-Host "    Saved state loaded from: $stateFile"
} else {
    Write-Host "    No backup found, using Windows default values." -ForegroundColor Gray
}

foreach ($svc in $defaults.Keys) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) {
        Set-Service $svc -StartupType $defaults[$svc] -ErrorAction SilentlyContinue
        Start-Service $svc -ErrorAction SilentlyContinue
        Write-Host "    [RESTORED]  $svc -> $($defaults[$svc])"
    } else {
        Write-Host "    [NOT FOUND] $svc" -ForegroundColor Gray
    }
}
