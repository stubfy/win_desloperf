param(
    [switch]$ExportCatalogOnly
)

# services.ps1 - Align service startup types to the reference main PC
#
# Strategy: Most services are set to Manual (demand-start via SCM trigger or
# explicit Start-Service call). Windows will start them automatically when
# needed by a component that depends on them -- the difference is they no longer
# auto-start during boot, reducing baseline CPU/disk activity at session start.
#
# Startup type mapping (registry Start value):
#   2 = Automatic              (starts at boot, no delay)
#   2 + DelayedAutoStart=1    = AutomaticDelayedStart (starts ~2 min after boot)
#   3 = Manual                 (starts on demand / trigger)
#   4 = Disabled               (cannot start unless manually re-enabled)
#
# Two writes per service (Set-Service + direct registry DWORD) ensure the change
# is visible to both the SCM API and the raw registry simultaneously, avoiding
# cases where one layer disagrees with the other after a failed Set-Service call.
#
# DoSvc (Delivery Optimization): Set to Disabled AND its TriggerInfo sub-key is
# removed. TriggerInfo causes SCM to automatically start DoSvc when certain
# network events fire (e.g., ETW network connectivity trigger). Removing it
# prevents SCM from relaunching DoSvc behind our back after Start=4 is applied.
# This is intentional redundancy on top of DODownloadMode=0 in privacy.ps1.
#
# Rollback: restore\services.ps1 reads backup\services_state.json and
# restores each service to its pre-tweak startup type.

function Set-ServiceDwordValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )

    try {
        $props = Get-ItemProperty -Path $Path -ErrorAction Stop
        if ($props.PSObject.Properties.Name -contains $Name) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force -ErrorAction Stop
        } else {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        }
        return $true
    } catch {
        return $false
    }
}

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

    $resolved = @(Get-Service -Name $Name, "$Name_*" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name -Unique)

    if ($resolved.Count -gt 0) {
        return @($resolved | Sort-Object -Unique)
    }

    return @($Name)
}

function Get-ServiceStartupCatalog {
    # ---- DISABLED ----
    # Services that provide no benefit on a gaming PC and are stopped entirely.
    # Notable entries:
    #   AssignedAccessManagerSvc - Kiosk/assigned access mode management; unused on regular desktops
    #   DiagTrack                - Connected User Experiences and Telemetry (CEIP data uploader)
    #   dmwappushservice         - WAP Push Message Routing; used by MDM/Device Management
    #   DPS                      - Diagnostic Policy Service; monitors component health and creates event log entries
    #   lfsvc                    - Geolocation Service; feeds location data to apps
    #   MapsBroker               - Downloads offline maps in the background
    #   PhoneSvc                 - Phone integration (Phone Link); disabled if YourPhone/PhoneLink is not used
    #   RemoteRegistry           - Allows remote registry editing; security risk on a personal PC
    #   RetailDemo               - Retail demo experience; irrelevant outside of a store display
    #   RmSvc                    - Radio Management; controls airplane mode toggle state
    #   SCardSvr                 - Smart Card service; no smart card reader on most gaming PCs
    #   ScDeviceEnum             - Smart Card Device Enumeration
    #   SEMgrSvc                 - Payments and NFC; contactless payment subsystem
    #   SharedAccess             - ICS (Internet Connection Sharing); unused if not sharing internet
    #   Spooler                  - Print Spooler; disabled if no printer is attached
    #   SysMain                  - SuperFetch/prefetch memory manager; replaced by NVMe speed on modern systems
    #   WerSvc                   - Windows Error Reporting host; crash dump collector
    #   WpcMonSvc                - Parental Controls/Family Safety monitor
    #   WSearch                  - Windows Search indexer; responsible for ongoing background I/O
    $disabled = @(
        'AssignedAccessManagerSvc'
        'DiagTrack'
        'dmwappushservice'
        'DoSvc'
        'CDPSvc'            # Connected Devices Platform: Nearby Sharing / shared experiences
        'CDPUserSvc'        # Per-user CDP instance backing Nearby and cross-device features
        'DevicePickerUserSvc' # Per-user device picker used by Nearby / cast / share UX
        'DevicesFlowUserSvc'  # Per-user Devices Flow broker for Nearby device discovery
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

    # ---- MANUAL ----
    # Services kept at Manual (demand-start). Windows will start them when required
    # by another component; they simply no longer run unconditionally at boot.
    # Grouped by function below.
    $manual = @(
        # --- Application / Package Management ---
        'ALG'             # Application Layer Gateway: NAT/firewall helper for legacy apps using ICS
        'Appinfo'         # Application Information: required for UAC elevation dialogs
        'AppMgmt'         # Application Management: handles Software Installation Group Policy
        'AppReadiness'    # Prepares Start menu and app tiles for new user accounts
        'AxInstSV'        # ActiveX Installer: downloads/installs ActiveX controls via IE (legacy)

        # --- BitLocker ---
        'BDESVC'          # BitLocker Drive Encryption service

        # --- Background Intelligent Transfer ---
        'BITS'            # Background Intelligent Transfer: used by Windows Update for downloads

        # --- Bluetooth ---
        'BTAGService'     # Bluetooth Audio Gateway: A2DP profile for Bluetooth headsets
        'bthserv'         # Bluetooth Support service

        # --- Camera ---
        'camsvc'          # Camera capabilities and privacy access broker

        # --- Certificates ---
        'CertPropSvc'     # Certificate Propagation: pushes smart card certs to the cert store

        # --- Cloud / Identity ---
        'cloudidsvc'      # Cloud Identity: Azure AD / Microsoft account identity integration

        # --- COM+ ---
        'COMSysApp'       # COM+ System Application: required only when COM+ applications are running

        # --- Offline Files ---
        'CscService'      # Client-Side Caching (Offline Files)

        # --- Data Collection ---
        'dcsvc'           # Declared Configuration Service: MDM/DSC configuration agent

        # --- Defrag ---
        'defragsvc'       # Optimize Drives: scheduled SSD TRIM / HDD defrag jobs

        # --- Device Management ---
        'DeviceInstall'   # Detects hardware changes and installs PnP drivers
        'DevQueryBroker'  # Device Query Broker: WinRT device query API

        # --- Diagnostics ---
        'diagsvc'         # Diagnostic Execution Service: runs interactive diagnostic steps
        'DisplayEnhancementService' # Manages display brightness / color profile on supported panels

        # --- 802.1x / EAP ---
        'dot3svc'         # Wired 802.1x authentication
        'EapHost'         # Extensible Authentication Protocol host

        # --- Edge Update ---
        'edgeupdate'      # Microsoft Edge Update (elevated)
        'edgeupdatem'     # Microsoft Edge Update (medium integrity)

        # --- EFS ---
        'EFS'             # Encrypting File System; not needed unless EFS-encrypted files are in use

        # --- Function Discovery ---
        'fdPHost'         # Function Discovery Provider Host: network device discovery
        'FDResPub'        # Function Discovery Resource Publication: advertises this PC on the network

        # --- File History ---
        'fhsvc'           # File History Service: incremental backup to external drive

        # --- Camera / Windows Hello ---
        'FrameServer'     # Windows Camera Frame Server: shared camera access for multiple apps
        'FrameServerMonitor' # Monitors camera usage to enforce privacy

        # --- Graphics ---
        'GraphicsPerfSvc' # Graphics performance telemetry (sends GPU data to Microsoft)

        # --- HID ---
        'hidserv'         # Human Interface Device: bridges HID over USB for accessibility devices

        # --- Hyper-V guest ---
        # These vmicXXX services are the Hyper-V integration components. On a
        # bare-metal gaming PC they are unused. On a VM they would be Automatic.
        'HvHost'          # Hyper-V Host service
        'vmicguestinterface'  # Hyper-V Guest Service Interface
        'vmicheartbeat'       # Hyper-V Heartbeat
        'vmickvpexchange'     # Hyper-V Data Exchange
        'vmicrdv'             # Hyper-V Remote Desktop Virtualization
        'vmicshutdown'        # Hyper-V Guest Shutdown
        'vmictimesync'        # Hyper-V Time Synchronization
        'vmicvmsession'       # Hyper-V PowerShell Direct session
        'vmicvss'             # Hyper-V Volume Shadow Copy Requestor

        # --- Mobile Hotspot ---
        'icssvc'          # Windows Mobile Hotspot Service

        # --- Inventory ---
        'InventorySvc'    # Inventory and Compatibility Appraisal

        # --- NAT64 ---
        'IpxlatCfgSvc'    # IP Translation Configuration (IPv6/IPv4 translation)

        # --- DTC ---
        'KtmRm'           # KTM Resource Manager: coordinates distributed transactions with MSDTC

        # --- License ---
        'LicenseManager'  # Windows Store license management

        # --- LLTD ---
        'lltdsvc'         # Link-Layer Topology Discovery: maps PCs on the network in Network window

        # --- NetBIOS ---
        'lmhosts'         # TCP/IP NetBIOS Helper: NetBIOS name resolution over TCP

        # --- Localisation ---
        'LxpSvc'          # Language Experience Service: installs language packs on demand

        # --- Connected Cache ---
        'McpManagementService' # Microsoft Connected Cache management

        # --- Edge Elevation ---
        'MicrosoftEdgeElevationService' # Edge update/elevation service

        # --- MSDTC ---
        'MSDTC'           # Distributed Transaction Coordinator

        # --- iSCSI ---
        'MSiSCSI'         # Microsoft iSCSI Initiator: connects to remote iSCSI storage

        # --- Windows Hello / Biometrics ---
        'NaturalAuthentication' # Signals whether the user is present (gesture/sensor)
        'WbioSrvc'        # Windows Biometric Framework: fingerprint/face reader management

        # --- Network ---
        'NcaSvc'          # Network Connectivity Awareness: monitors network path quality
        'NcbService'      # Network Connection Broker: notifies apps of network changes
        'NcdAutoSetup'    # Network Connected Devices Auto-Setup: auto-installs UPnP devices
        'Netman'          # Network Connections: manages network/VPN connections in Control Panel
        'netprofm'        # Network List Service: identifies and tracks connected networks
        'NetSetupSvc'     # Network Setup Service: installs/configures network adapters
        'NlaSvc'          # Network Location Awareness: determines network type (domain/private/public)

        # --- Program Compatibility ---
        'PcaSvc'          # Program Compatibility Assistant: detects and resolves compatibility issues

        # --- Peer Distribution ---
        'PeerDistSvc'     # BranchCache peer-to-peer distribution

        # --- Perception Simulation ---
        'perceptionsimulation' # Windows Mixed Reality perception simulation

        # --- Performance Logs ---
        'PerfHost'        # Performance Counter DLL Host: hosts out-of-process performance counters
        'pla'             # Performance Logs and Alerts

        # --- PnP ---
        'PlugPlay'        # Plug and Play: handles device arrival/removal events

        # --- IPsec ---
        'PolicyAgent'     # IPsec Policy Agent: enforces IPsec connection security rules

        # --- Print ---
        'PrintNotify'     # Printer Extensions and Notifications

        # --- Push-to-Install ---
        'PushToInstall'   # Microsoft Store push install feature (install from browser on another device)

        # --- Quality of Service ---
        'QWAVE'           # Quality Windows Audio Video Experience: QoS for multimedia streams

        # --- RAS / VPN ---
        'RasAuto'         # Remote Access Auto Connection: automatically creates VPN connections
        'RasMan'          # Remote Access Connection Manager: manages VPN/dial-up connections
        'SstpSvc'         # Secure Socket Tunneling Protocol (SSTP VPN)

        # --- RPC ---
        'RpcLocator'      # Remote Procedure Call Locator (legacy; only needed for old COM apps)

        # --- Smart Card ---
        'SCPolicySvc'     # Smart Card Removal Policy

        # --- Backup ---
        'SDRSVC'          # Windows Backup (System Data Recovery)

        # --- Secondary Logon ---
        'seclogon'        # Secondary Logon: 'Run as different user' functionality

        # --- Sensors ---
        'SensorDataService' # Delivers sensor data to applications
        'SensorService'   # Manages sensor hardware on the machine
        'SensrSvc'        # Monitors simple sensors (brightness, orientation)

        # --- IPsec ---
        'IKEEXT'          # IKE/AuthIP: key exchange for IPsec connections (unused without IPsec VPN)

        # --- Remote Desktop / Imaging ---
        'SessionEnv'      # Remote Desktop Configuration
        'StiSvc'          # Windows Image Acquisition (scanners)
        'TermService'     # Remote Desktop Services: keep Manual to avoid exposing 3389 at boot
        'UmRdpService'    # Remote Desktop Services UserMode Port Redirector

        # --- Storage Migration ---
        'smphost'         # Storage Migration Service Proxy host

        # --- SMS ---
        'SmsRouter'       # Microsoft Windows SMS Router Service

        # --- SNMP ---
        'SNMPTrap'        # SNMP Trap: receives SNMP messages from network agents

        # --- SSDP / UPnP ---
        'SSDPSRV'         # SSDP Discovery: discovers UPnP devices on the network
        'upnphost'        # UPnP Device Host: hosts UPnP device descriptions

        # --- Storage ---
        'StorSvc'         # Storage Service: manages removable storage settings
        'svsvc'           # Spot Verifier: verifies file system integrity
        'swprv'           # Microsoft Software Shadow Copy Provider (for VSS snapshots)
        'TieringEngineService' # Storage Spaces tiering engine

        # --- Telephony ---
        'TapiSrv'         # Telephony API service (TAPI)

        # --- Token Broker ---
        'TokenBroker'     # Web authentication broker for Microsoft and third-party accounts

        # --- Troubleshooting ---
        'TroubleshootingSvc' # Windows Troubleshooting platform

        # --- Trusted Installer ---
        'TrustedInstaller' # Windows Modules Installer: installs/removes Windows updates

        # --- VDS ---
        'vds'             # Virtual Disk Service: manages disk/volume configuration

        # --- VSS ---
        'VSS'             # Volume Shadow Copy Service: coordinates shadow copy creation

        # --- Wallet ---
        'WalletService'   # Wallet for NFC payments

        # --- JIT ---
        'WarpJITSvc'      # WARP JIT Service: software rasterizer JIT compilation for UWP

        # --- Windows Backup ---
        'wbengine'        # Block Level Backup Engine: Windows Backup engine

        # --- Wireless ---
        'wcncsvc'         # Windows Connect Now: WPS-style network device pairing
        'WFDSConMgrSvc'   # Wi-Fi Direct Services Connection Manager

        # --- Diagnostics ---
        'WdiServiceHost'  # Diagnostic Service Host
        'WdiSystemHost'   # Diagnostic System Host

        # --- WebClient ---
        'WebClient'       # WebDAV client (maps WebDAV shares as drive letters)

        # --- Threat Defense ---
        'webthreatdefsvc' # Web Threat Defense: SmartScreen/browser protection

        # --- Event Collector ---
        'Wecsvc'          # Windows Event Collector: aggregates events from remote machines

        # --- WEP / WLAN ---
        'WEPHOSTSVC'      # Windows Encryption Provider Host

        # --- WER support ---
        'wercplsupport'   # Problem Reports Control Panel support (WER UI helper)

        # --- Windows Image Acquisition ---
        'WiaRpc'          # Scanner/camera WIA RPC endpoint

        # --- WinRM ---
        'WinRM'           # Windows Remote Management (PowerShell remoting, WS-Management)

        # --- Insider ---
        'wisvc'           # Windows Insider Service

        # --- Microsoft Account ---
        'wlidsvc'         # Microsoft Account Sign-in Assistant
        'wlpasvc'         # Local Profile Assistant Service

        # --- Management ---
        'WManSvc'         # Windows Management Service (MDM push)

        # --- WMI ---
        'wmiApSrv'        # WMI Performance Adapter: exposes perf counters via WMI

        # --- Media Player ---
        'WMPNetworkSvc'   # Windows Media Player Network Sharing (DLNA server)

        # --- Work Folders ---
        'workfolderssvc'  # Work Folders: corporate folder sync feature

        # --- MTP / PTP ---
        'WPDBusEnum'      # Portable Device Enumerator: MTP/PTP device sync

        # --- Push Notifications ---
        'WpnService'      # Windows Push Notifications System Service (WNS)

        # --- AI fabric ---
        'WSAIFabricSvc'   # Windows Subsystem for AI fabric (Qualcomm NPU on ARM; no-op on x86 desktops)

        # --- Xbox (non-overlay) ---
        # Gaming overlay and Game Bar are disabled via registry in registry.ps1;
        # the underlying Xbox services are set to Manual rather than Disabled
        # to avoid breaking games that authenticate against Xbox Live.
        'XblAuthManager'  # Xbox Live Auth Manager: signs the user into Xbox Live
        'XblGameSave'     # Xbox Live Game Save: cloud save synchronization
        'XboxGipSvc'      # Xbox Accessories (GIP protocol for Xbox controllers)
        'XboxNetApiSvc'   # Xbox Live Networking: NAT traversal for multiplayer
    )

    # ---- AUTOMATIC ----
    # Services that should remain running at all times for system stability.
    # These are either security infrastructure, hardware support or core UX.
    $automatic = @(
        'DeviceAssociationService' # Pairs devices that use pairing protocols (Bluetooth, USB accessories)
        'InstallService'  # Microsoft Store installation infrastructure
        'VaultSvc'        # Credential Vault: stores encrypted credentials for apps and Windows
        'W32Time'         # Windows Time: NTP synchronization (keeps system clock accurate)
        'wuauserv'        # Windows Update Agent: managed separately by 8 - Windows Update\ps1\set_windows_update.ps1
    )

    # ---- AUTOMATIC DELAYED START ----
    # Starts ~2 minutes after boot, reducing boot-time CPU pressure.
    $automaticDelayedStart = @(
        'UsoSvc'          # Update Session Orchestrator: coordinates WU scan/download/install sessions
    )

    $defaults = [ordered]@{
        'AssignedAccessManagerSvc'      = 'Manual'
        'BITS'                          = 'Automatic'
        'CDPSvc'                        = 'Automatic'
        'CDPUserSvc'                    = 'Automatic'
        'DevicePickerUserSvc'           = 'Manual'
        'DevicesFlowUserSvc'            = 'Manual'
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
        TriggerlessDisabled    = @('DoSvc')
        TriggerlessManual      = @()
        Defaults               = $defaults
        Tracked                = @($disabled + $manual + $automatic + $automaticDelayedStart)
        DiffExcluded           = @('BITS', 'UsoSvc', 'wuauserv')
        DiffVolatile           = @('DeviceAssociationService', 'IKEEXT', 'PcaSvc')
    }
}

function Set-ServiceStartupTypeExact {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$StartupType
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) {
        return [PSCustomObject]@{
            Exists    = $false
            Applied   = $false
            Current   = $null
            Requested = $StartupType
        }
    }

    $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"

    $scStartValue = $null
    switch ($StartupType) {
        'Disabled' {
            $scStartValue = 'disabled'
            try { Stop-Service $Name -Force -ErrorAction SilentlyContinue } catch {}
            try { Set-Service $Name -StartupType Disabled -ErrorAction SilentlyContinue } catch {}
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 4 | Out-Null
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0 | Out-Null
        }
        'Manual' {
            $scStartValue = 'demand'
            try { Set-Service $Name -StartupType Manual -ErrorAction SilentlyContinue } catch {}
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 3 | Out-Null
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0 | Out-Null
        }
        'Automatic' {
            $scStartValue = 'auto'
            try { Set-Service $Name -StartupType Automatic -ErrorAction SilentlyContinue } catch {}
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 2 | Out-Null
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0 | Out-Null
        }
        'AutomaticDelayedStart' {
            $scStartValue = 'delayed-auto'
            try { Set-Service $Name -StartupType Automatic -ErrorAction SilentlyContinue } catch {}
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 2 | Out-Null
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 1 | Out-Null
        }
        default {
            throw "Unsupported startup type: $StartupType"
        }
    }

    if ($scStartValue) {
        try { & sc.exe config $Name start= $scStartValue 2>$null | Out-Null } catch {}
    }

    $current = Get-ExactServiceStartupType -Name $Name
    if ($Name -eq 'IKEEXT' -and $current -ne $StartupType -and $scStartValue) {
        try { & sc.exe config $Name start= $scStartValue 2>$null | Out-Null } catch {}
        Start-Sleep -Milliseconds 250
        $current = Get-ExactServiceStartupType -Name $Name
    }
    return [PSCustomObject]@{
        Exists    = $true
        Applied   = ($current -eq $StartupType)
        Current   = $current
        Requested = $StartupType
    }
}

function Write-ServiceStartupResult {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$SuccessPrefix
    )

    if (-not $Result.Exists) {
        Write-Host "    [NOT FOUND]  $Name" -ForegroundColor Gray
        return
    }

    if ($Result.Applied) {
        Write-Host "    $SuccessPrefix$Name"
        return
    }

    $current = if ($Result.Current) { $Result.Current } else { 'Unknown' }
    Write-Host "    [WARN]       $Name -> current=$current wanted=$($Result.Requested)" -ForegroundColor Yellow
}

if ($ExportCatalogOnly) {
    return Get-ServiceStartupCatalog
}

$serviceCatalog = Get-ServiceStartupCatalog

foreach ($svc in $serviceCatalog.Disabled) {
    if ($svc -in $serviceCatalog.TriggerlessDisabled) { continue }

    foreach ($resolvedSvc in (Resolve-TrackedServiceNames -Name $svc)) {
        $result = Set-ServiceStartupTypeExact -Name $resolvedSvc -StartupType 'Disabled'
        Write-ServiceStartupResult -Result $result -Name $resolvedSvc -SuccessPrefix '[DISABLED]   '
    }
}

foreach ($svc in $serviceCatalog.Manual) {
    if ($svc -in $serviceCatalog.TriggerlessManual) { continue }

    foreach ($resolvedSvc in (Resolve-TrackedServiceNames -Name $svc)) {
        $result = Set-ServiceStartupTypeExact -Name $resolvedSvc -StartupType 'Manual'
        Write-ServiceStartupResult -Result $result -Name $resolvedSvc -SuccessPrefix '[MANUAL]     '
    }
}

foreach ($svc in $serviceCatalog.Automatic) {
    foreach ($resolvedSvc in (Resolve-TrackedServiceNames -Name $svc)) {
        $result = Set-ServiceStartupTypeExact -Name $resolvedSvc -StartupType 'Automatic'
        Write-ServiceStartupResult -Result $result -Name $resolvedSvc -SuccessPrefix '[AUTO]       '
    }
}

foreach ($svc in $serviceCatalog.AutomaticDelayedStart) {
    foreach ($resolvedSvc in (Resolve-TrackedServiceNames -Name $svc)) {
        $result = Set-ServiceStartupTypeExact -Name $resolvedSvc -StartupType 'AutomaticDelayedStart'
        Write-ServiceStartupResult -Result $result -Name $resolvedSvc -SuccessPrefix '[AUTO-DELAY] '
    }
}

# DoSvc (Delivery Optimization) special case:
# Set to Disabled AND remove TriggerInfo to prevent SCM from starting it
# automatically on network-connectivity ETW events. Without removing TriggerInfo
# the service can relaunch itself even after the startup type is changed.
# This is intentionally redundant with DODownloadMode=0 in privacy.ps1:
# the registry policy blocks P2P downloading, TriggerInfo removal prevents the
# process from ever running in the background to check for work.
$doSvc = Get-Service 'DoSvc' -ErrorAction SilentlyContinue
if ($doSvc) {
    $result = Set-ServiceStartupTypeExact -Name 'DoSvc' -StartupType 'Disabled'
    $triggerPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc\TriggerInfo'
    if (Test-Path $triggerPath) {
        Remove-Item $triggerPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    $current = Get-ExactServiceStartupType -Name 'DoSvc'
    if ($result.Exists -and $current -eq 'Disabled') {
        Write-Host "    [DISABLED]   DoSvc (TriggerInfo removed)"
    } else {
        $currentLabel = if ($current) { $current } else { 'Unknown' }
        Write-Host "    [WARN]       DoSvc -> current=$currentLabel wanted=Disabled (TriggerInfo removal attempted)" -ForegroundColor Yellow
    }
} else {
    Write-Host "    [NOT FOUND]  DoSvc" -ForegroundColor Gray
}
