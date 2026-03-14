# restore\02_services.ps1 - Restore services to their original state

$BACKUP_DIR = Join-Path (Split-Path $PSScriptRoot) "backup"
$stateFile  = Join-Path $BACKUP_DIR "services_state.json"
$serviceCatalog = & (Join-Path (Join-Path (Split-Path $PSScriptRoot) 'scripts') '03_services.ps1') -ExportCatalogOnly

# Windows default values if no backup available
$defaults = [ordered]@{}
foreach ($svc in $serviceCatalog.Defaults.Keys) {
    $defaults[$svc] = $serviceCatalog.Defaults[$svc]
}

# Load saved state if available
if (Test-Path $stateFile) {
    $saved = Get-Content $stateFile -Encoding UTF8 | ConvertFrom-Json
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
        $startupType = $defaults[$svc]
        Set-Service $svc -StartupType $startupType -ErrorAction SilentlyContinue
        if ($startupType -in @('Automatic', 'AutomaticDelayedStart')) {
            Start-Service $svc -ErrorAction SilentlyContinue
        }
        Write-Host "    [RESTORED]  $svc -> $($defaults[$svc])"
    } else {
        Write-Host "    [NOT FOUND] $svc" -ForegroundColor Gray
    }
}

# --- DoSvc — restore registry Start value after TriggerInfo removal ---
$doSvc = Get-Service 'DoSvc' -ErrorAction SilentlyContinue
if ($doSvc -and $defaults.Contains('DoSvc')) {
    $desired = $defaults['DoSvc']
    $startValueMap = @{
        'Automatic'              = 2
        'AutomaticDelayedStart'  = 2
        'Manual'                 = 3
        'Disabled'               = 4
    }

    if ($startValueMap.ContainsKey($desired)) {
        Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc' -Name Start -Value $startValueMap[$desired] -ErrorAction SilentlyContinue
        if ($desired -in @('Automatic', 'AutomaticDelayedStart')) {
            Start-Service 'DoSvc' -ErrorAction SilentlyContinue
        }
        Write-Host "    [RESTORED]  DoSvc -> $desired"
    }
}
