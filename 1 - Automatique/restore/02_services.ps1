# restore\02_services.ps1 - Remet les services dans leur etat d'origine

$BACKUP_DIR = Join-Path (Split-Path $PSScriptRoot) "backup"
$stateFile  = Join-Path $BACKUP_DIR "services_state.json"

# Valeurs par defaut Windows si pas de sauvegarde
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
}

# Charger l'etat sauvegarde si disponible
if (Test-Path $stateFile) {
    $saved = Get-Content $stateFile | ConvertFrom-Json
    foreach ($prop in $saved.PSObject.Properties) {
        $defaults[$prop.Name] = $prop.Value
    }
    Write-Host "    Etat sauvegarde charge depuis : $stateFile"
} else {
    Write-Host "    Pas de sauvegarde trouvee, utilisation des valeurs par defaut Windows." -ForegroundColor Gray
}

foreach ($svc in $defaults.Keys) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) {
        Set-Service $svc -StartupType $defaults[$svc] -ErrorAction SilentlyContinue
        Start-Service $svc -ErrorAction SilentlyContinue
        Write-Host "    [RESTAURE] $svc -> $($defaults[$svc])"
    } else {
        Write-Host "    [ABSENT]   $svc" -ForegroundColor Gray
    }
}
