param(
    [switch]$ExportCatalogOnly
)

# 03_services.ps1 - Align service startup types to the reference main PC

function Set-ServiceDwordValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Get-ServiceStartupCatalog {
    $disabled = @(
        'AssignedAccessManagerSvc'
        'DiagTrack'
        'dmwappushservice'
        'DPS'
        'lfsvc'
        'MapsBroker'
        'PhoneSvc'
        'RemoteRegistry'
        'RetailDemo'
        'RmSvc'
        'SCardSvr'
        'ScDeviceEnum'
        'SEMgrSvc'
        'SharedAccess'
        'Spooler'
        'SysMain'
        'WerSvc'
        'WpcMonSvc'
        'WSearch'
    )

    $manual = @(
        'ALG'
        'Appinfo'
        'AppMgmt'
        'AppReadiness'
        'autotimesvc'
        'AxInstSV'
        'BDESVC'
        'BITS'
        'BTAGService'
        'bthserv'
        'camsvc'
        'CDPSvc'
        'CertPropSvc'
        'cloudidsvc'
        'COMSysApp'
        'CscService'
        'dcsvc'
        'defragsvc'
        'DeviceInstall'
        'DevQueryBroker'
        'diagsvc'
        'DisplayEnhancementService'
        'DoSvc'
        'dot3svc'
        'EapHost'
        'edgeupdate'
        'edgeupdatem'
        'EFS'
        'fdPHost'
        'FDResPub'
        'fhsvc'
        'FrameServer'
        'FrameServerMonitor'
        'GraphicsPerfSvc'
        'hidserv'
        'HvHost'
        'icssvc'
        'InventorySvc'
        'IpxlatCfgSvc'
        'KtmRm'
        'LicenseManager'
        'lltdsvc'
        'lmhosts'
        'LxpSvc'
        'McpManagementService'
        'MicrosoftEdgeElevationService'
        'MSDTC'
        'MSiSCSI'
        'NaturalAuthentication'
        'NcaSvc'
        'NcbService'
        'NcdAutoSetup'
        'Netman'
        'netprofm'
        'NetSetupSvc'
        'NlaSvc'
        'PcaSvc'
        'PeerDistSvc'
        'perceptionsimulation'
        'PerfHost'
        'pla'
        'PlugPlay'
        'PolicyAgent'
        'PrintNotify'
        'PushToInstall'
        'QWAVE'
        'RasAuto'
        'RasMan'
        'RpcLocator'
        'SCPolicySvc'
        'SDRSVC'
        'seclogon'
        'SensorDataService'
        'SensorService'
        'SensrSvc'
        'SessionEnv'
        'smphost'
        'SmsRouter'
        'SNMPTrap'
        'SSDPSRV'
        'SstpSvc'
        'StorSvc'
        'svsvc'
        'swprv'
        'TapiSrv'
        'TieringEngineService'
        'TokenBroker'
        'TroubleshootingSvc'
        'TrustedInstaller'
        'UmRdpService'
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
        'VSS'
        'WalletService'
        'WarpJITSvc'
        'wbengine'
        'WbioSrvc'
        'wcncsvc'
        'WdiServiceHost'
        'WdiSystemHost'
        'WebClient'
        'webthreatdefsvc'
        'Wecsvc'
        'WEPHOSTSVC'
        'wercplsupport'
        'WFDSConMgrSvc'
        'WiaRpc'
        'WinRM'
        'wisvc'
        'wlidsvc'
        'wlpasvc'
        'WManSvc'
        'wmiApSrv'
        'WMPNetworkSvc'
        'workfolderssvc'
        'WPDBusEnum'
        'WpnService'
        'WSAIFabricSvc'
        'XblAuthManager'
        'XblGameSave'
        'XboxGipSvc'
        'XboxNetApiSvc'
    )

    $automatic = @(
        'DeviceAssociationService'
        'IKEEXT'
        'InstallService'
        'StiSvc'
        'TermService'
        'VaultSvc'
        'W32Time'
        'wuauserv'
    )

    $automaticDelayedStart = @(
        'UsoSvc'
    )

    $defaults = [ordered]@{
        'AssignedAccessManagerSvc'      = 'Manual'
        'BITS'                          = 'Automatic'
        'CDPSvc'                        = 'Automatic'
        'DeviceAssociationService'      = 'Manual'
        'DiagTrack'                     = 'Automatic'
        'dmwappushservice'              = 'Manual'
        'DoSvc'                         = 'Automatic'
        'DPS'                           = 'Automatic'
        'IKEEXT'                        = 'Manual'
        'InstallService'                = 'Manual'
        'InventorySvc'                  = 'Automatic'
        'lfsvc'                         = 'Manual'
        'MapsBroker'                    = 'Automatic'
        'PhoneSvc'                      = 'Manual'
        'PcaSvc'                        = 'Automatic'
        'RemoteRegistry'                = 'Disabled'
        'RetailDemo'                    = 'Manual'
        'RmSvc'                         = 'Manual'
        'SCardSvr'                      = 'Manual'
        'ScDeviceEnum'                  = 'Manual'
        'SEMgrSvc'                      = 'Manual'
        'SharedAccess'                  = 'Manual'
        'Spooler'                       = 'Automatic'
        'StiSvc'                        = 'Manual'
        'StorSvc'                       = 'Automatic'
        'SysMain'                       = 'Automatic'
        'TermService'                   = 'Manual'
        'UsoSvc'                        = 'Automatic'
        'VaultSvc'                      = 'Manual'
        'W32Time'                       = 'Manual'
        'WerSvc'                        = 'Manual'
        'WpcMonSvc'                     = 'Manual'
        'WpnService'                    = 'Automatic'
        'WSearch'                       = 'Automatic'
        'WSAIFabricSvc'                 = 'Automatic'
        'wuauserv'                      = 'Manual'
        'camsvc'                        = 'Automatic'
        'edgeupdate'                    = 'Automatic'
    }

    foreach ($svc in $manual) {
        if (-not $defaults.Contains($svc)) {
            $defaults[$svc] = 'Manual'
        }
    }

    foreach ($svc in $automatic) {
        if (-not $defaults.Contains($svc)) {
            $defaults[$svc] = 'Manual'
        }
    }

    return @{
        Disabled               = $disabled
        Manual                 = $manual
        Automatic              = $automatic
        AutomaticDelayedStart  = $automaticDelayedStart
        TriggerlessManual      = @('DoSvc')
        Defaults               = $defaults
        Tracked                = @($disabled + $manual + $automatic + $automaticDelayedStart)
        DiffExcluded           = @('BITS', 'UsoSvc', 'wuauserv')
    }
}

function Set-ServiceStartupTypeExact {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$StartupType
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) { return $false }

    $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"

    switch ($StartupType) {
        'Disabled' {
            Stop-Service $Name -Force -ErrorAction SilentlyContinue
            Set-Service $Name -StartupType Disabled -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 4
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0
        }
        'Manual' {
            Set-Service $Name -StartupType Manual -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 3
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0
        }
        'Automatic' {
            Set-Service $Name -StartupType Automatic -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 2
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0
        }
        'AutomaticDelayedStart' {
            Set-Service $Name -StartupType Automatic -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 2
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 1
        }
        default {
            throw "Unsupported startup type: $StartupType"
        }
    }

    return $true
}

if ($ExportCatalogOnly) {
    return Get-ServiceStartupCatalog
}

$serviceCatalog = Get-ServiceStartupCatalog

foreach ($svc in $serviceCatalog.Disabled) {
    if (Set-ServiceStartupTypeExact -Name $svc -StartupType 'Disabled') {
        Write-Host "    [DISABLED]   $svc"
    } else {
        Write-Host "    [NOT FOUND]  $svc" -ForegroundColor Gray
    }
}

foreach ($svc in $serviceCatalog.Manual) {
    if ($svc -in $serviceCatalog.TriggerlessManual) { continue }

    if (Set-ServiceStartupTypeExact -Name $svc -StartupType 'Manual') {
        Write-Host "    [MANUAL]     $svc"
    } else {
        Write-Host "    [NOT FOUND]  $svc" -ForegroundColor Gray
    }
}

foreach ($svc in $serviceCatalog.Automatic) {
    if (Set-ServiceStartupTypeExact -Name $svc -StartupType 'Automatic') {
        Write-Host "    [AUTO]       $svc"
    } else {
        Write-Host "    [NOT FOUND]  $svc" -ForegroundColor Gray
    }
}

foreach ($svc in $serviceCatalog.AutomaticDelayedStart) {
    if (Set-ServiceStartupTypeExact -Name $svc -StartupType 'AutomaticDelayedStart') {
        Write-Host "    [AUTO-DELAY] $svc"
    } else {
        Write-Host "    [NOT FOUND]  $svc" -ForegroundColor Gray
    }
}

# Align DoSvc to the reference main PC: Manual startup with TriggerInfo removed.
$doSvc = Get-Service 'DoSvc' -ErrorAction SilentlyContinue
if ($doSvc) {
    Set-ServiceStartupTypeExact -Name 'DoSvc' -StartupType 'Manual' | Out-Null
    $triggerPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc\TriggerInfo'
    if (Test-Path $triggerPath) {
        Remove-Item $triggerPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "    [MANUAL]     DoSvc (TriggerInfo removed)"
} else {
    Write-Host "    [NOT FOUND]  DoSvc" -ForegroundColor Gray
}
