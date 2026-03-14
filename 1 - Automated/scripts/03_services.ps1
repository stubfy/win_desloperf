param(
    [switch]$ExportCatalogOnly
)

# 03_services.ps1 - Apply service startup tweaks for gaming

function Get-ServiceStartupCatalog {
    $disabled = @(
        'DoSvc'
    )

    $manual = @(
        'SysMain'
        'DPS'
        'Spooler'
        'TabletInputService'
        'DiagTrack'
        'WSearch'
        'MapsBroker'
        'RemoteRegistry'
        'ALG'
        'AppMgmt'
        'AppReadiness'
        'Appinfo'
        'AxInstSV'
        'BDESVC'
        'BTAGService'
        'CDPSvc'
        'COMSysApp'
        'CertPropSvc'
        'CscService'
        'DevQueryBroker'
        'DeviceAssociationService'
        'DeviceInstall'
        'DisplayEnhancementService'
        'EFS'
        'EapHost'
        'FDResPub'
        'FrameServer'
        'FrameServerMonitor'
        'GraphicsPerfSvc'
        'HvHost'
        'IKEEXT'
        'InstallService'
        'InventorySvc'
        'IpxlatCfgSvc'
        'KtmRm'
        'LicenseManager'
        'LxpSvc'
        'MSDTC'
        'MSiSCSI'
        'McpManagementService'
        'MicrosoftEdgeElevationService'
        'NaturalAuthentication'
        'NcaSvc'
        'NcbService'
        'NcdAutoSetup'
        'NetSetupSvc'
        'Netman'
        'NlaSvc'
        'PcaSvc'
        'PeerDistSvc'
        'PerfHost'
        'PhoneSvc'
        'PlugPlay'
        'PolicyAgent'
        'PrintNotify'
        'PushToInstall'
        'QWAVE'
        'RasAuto'
        'RasMan'
        'RetailDemo'
        'RmSvc'
        'RpcLocator'
        'SCPolicySvc'
        'SCardSvr'
        'SDRSVC'
        'SEMgrSvc'
        'SNMPTRAP'
        'SNMPTrap'
        'SSDPSRV'
        'ScDeviceEnum'
        'SensorDataService'
        'SensorService'
        'SensrSvc'
        'SessionEnv'
        'SharedAccess'
        'SmsRouter'
        'SstpSvc'
        'StiSvc'
        'StorSvc'
        'TapiSrv'
        'TermService'
        'TieringEngineService'
        'TokenBroker'
        'TroubleshootingSvc'
        'TrustedInstaller'
        'UmRdpService'
        'UsoSvc'
        'VSS'
        'VaultSvc'
        'W32Time'
        'WEPHOSTSVC'
        'WFDSConMgrSvc'
        'WMPNetworkSvc'
        'WManSvc'
        'WPDBusEnum'
        'WSAIFabricSvc'
        'WalletService'
        'WarpJITSvc'
        'WbioSrvc'
        'WdiServiceHost'
        'WdiSystemHost'
        'WebClient'
        'Wecsvc'
        'WerSvc'
        'WiaRpc'
        'WinRM'
        'WpcMonSvc'
        'WpnService'
        'XblAuthManager'
        'XblGameSave'
        'XboxGipSvc'
        'XboxNetApiSvc'
        'autotimesvc'
        'bthserv'
        'camsvc'
        'cloudidsvc'
        'dcsvc'
        'defragsvc'
        'diagsvc'
        'dmwappushservice'
        'dot3svc'
        'edgeupdate'
        'edgeupdatem'
        'fdPHost'
        'fhsvc'
        'hidserv'
        'icssvc'
        'lfsvc'
        'lltdsvc'
        'lmhosts'
        'netprofm'
        'perceptionsimulation'
        'pla'
        'seclogon'
        'smphost'
        'svsvc'
        'swprv'
        'upnphost'
        'vds'
        'vmicguestinterface'
        'vmicheartbeat'
        'vmickvpexchange'
        'vmicrdv'
        'vmicshutdown'
        'vmictimesync'
        'vmicvmsession'
        'vmicvss'
        'wbengine'
        'wcncsvc'
        'webthreatdefsvc'
        'wercplsupport'
        'wisvc'
        'wlidsvc'
        'wlpasvc'
        'wmiApSrv'
        'workfolderssvc'
        'wuauserv'
        'AssignedAccessManagerSvc'
        'BITS'
    )

    $defaults = [ordered]@{
        'SysMain'                   = 'Automatic'
        'DPS'                       = 'Automatic'
        'Spooler'                   = 'Automatic'
        'TabletInputService'        = 'Manual'
        'DiagTrack'                 = 'Automatic'
        'WSearch'                   = 'Automatic'
        'MapsBroker'                = 'Automatic'
        'RemoteRegistry'            = 'Disabled'
        'CDPSvc'                    = 'Automatic'
        'InventorySvc'              = 'Automatic'
        'PcaSvc'                    = 'Automatic'
        'StorSvc'                   = 'Automatic'
        'UsoSvc'                    = 'Automatic'
        'WpnService'                = 'Automatic'
        'camsvc'                    = 'Automatic'
        'edgeupdate'                = 'Automatic'
        'BITS'                      = 'Automatic'
        'WSAIFabricSvc'             = 'Automatic'
        'DoSvc'                     = 'Automatic'
        'AssignedAccessManagerSvc'  = 'Manual'
    }

    foreach ($svc in $manual) {
        if (-not $defaults.Contains($svc)) {
            $defaults[$svc] = 'Manual'
        }
    }

    return @{
        Disabled     = $disabled
        Manual       = $manual
        Defaults     = $defaults
        Tracked      = @($manual + $disabled)
        DiffExcluded = @('BITS', 'UsoSvc', 'wuauserv')
    }
}

if ($ExportCatalogOnly) {
    return Get-ServiceStartupCatalog
}

$serviceCatalog = Get-ServiceStartupCatalog

foreach ($svc in $serviceCatalog.Manual) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) {
        Set-Service $svc -StartupType Manual -ErrorAction SilentlyContinue
        Write-Host "    [MANUAL]     $svc"
    } else {
        Write-Host "    [NOT FOUND]  $svc" -ForegroundColor Gray
    }
}

# --- DoSvc (Delivery Optimization) — force-disable via registry + remove triggers ---
# Set-Service is silently ignored by Windows 11 25H2 because the service has triggers
# that relaunch it automatically. Direct registry write + TriggerInfo removal is required.
$doSvc = Get-Service 'DoSvc' -ErrorAction SilentlyContinue
if ($doSvc) {
    Stop-Service 'DoSvc' -Force -ErrorAction SilentlyContinue
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc' -Name Start -Value 4 -ErrorAction SilentlyContinue
    $triggerPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc\TriggerInfo'
    if (Test-Path $triggerPath) {
        Remove-Item $triggerPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "    [DISABLED]   DoSvc (registry + TriggerInfo removed)"
} else {
    Write-Host "    [NOT FOUND]  DoSvc" -ForegroundColor Gray
}
