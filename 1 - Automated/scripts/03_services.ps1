# 03_services.ps1 - Disable unnecessary services for gaming

$services = [ordered]@{
    'SysMain'            = 'Superfetch - constant disk I/O, useless on SSD'
    'DPS'                = 'Diagnostic Policy Service - unnecessary system diagnostics'
    'Spooler'            = 'Print Spooler - printing (disable if no printer attached)'
    'TabletInputService' = 'Touch keyboard and handwriting panel'
    'RmSvc'              = 'Radio Management Service'
    'DiagTrack'          = 'Connected User Experiences telemetry'
    'dmwappushservice'   = 'WAP push telemetry'
    'WSearch'            = 'Windows Search indexer - constant background disk I/O'
    'WerSvc'             = 'Windows Error Reporting - sends crash reports to Microsoft'
    'DoSvc'              = 'Delivery Optimization - P2P update sharing'
    'PhoneSvc'           = 'Phone service (Bluetooth calls, useless for pure gaming)'
    'SCardSvr'           = 'Smart Card - useless without a smart card reader'
    'ScDeviceEnum'       = 'Smart Card Device Enumeration Service'
    'SEMgrSvc'           = 'NFC payments / SE Manager'
    'WpcMonSvc'          = 'Windows Parental Controls'
    'lfsvc'              = 'Geolocation service (GPS/location for apps)'
    'MapsBroker'         = 'Downloaded maps manager'
    'RetailDemo'         = 'Demo mode (retail PC - no effect if not present)'
    'RemoteRegistry'     = 'Remote Registry - security risk'
    'SharedAccess'       = 'Internet Connection Sharing (ICS)'
}

foreach ($svc in $services.Keys) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) {
        Stop-Service $svc -Force -ErrorAction SilentlyContinue
        Set-Service  $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "    [DISABLED]   $svc"
    } else {
        Write-Host "    [NOT FOUND]  $svc" -ForegroundColor Gray
    }
}

# --- Services set to Manual (start on demand, not at boot) ---
# Source: Chris Titus WinUtil - services not covered by the pack
$servicesManual = [ordered]@{
    'CDPSvc'       = 'Connected Devices Platform - cross-device sync'
    'InventorySvc' = 'Inventory and Compatibility Appraisal - hardware telemetry'
    'PcaSvc'       = 'Program Compatibility Assistant - compatibility issue detection'
    'StorSvc'      = 'Storage Service - Storage Sense (starts on demand if needed)'
    'UsoSvc'       = 'Update Session Orchestrator - automatic background updates'
    'WpnService'   = 'Windows Push Notifications - toasts and interruptions'
    'camsvc'       = 'Capability Access Manager - UWP app access to camera/mic'
    'edgeupdate'   = 'Microsoft Edge Update - automatic Edge updates'
    'edgeupdatem'  = 'Microsoft Edge Update (scheduled task)'
    'BITS'         = 'Background Intelligent Transfer - background transfers'
    'WSAIFabricSvc'= 'Windows AI Fabric - AI runtime (Recall, Copilot runtime)'
}

foreach ($svc in $servicesManual.Keys) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) {
        Set-Service $svc -StartupType Manual -ErrorAction SilentlyContinue
        Write-Host "    [MANUAL]     $svc"
    } else {
        Write-Host "    [NOT FOUND]  $svc" -ForegroundColor Gray
    }
}

# --- Kiosk mode (useless on a gaming PC) ---
$s = Get-Service 'AssignedAccessManagerSvc' -ErrorAction SilentlyContinue
if ($s) {
    Stop-Service 'AssignedAccessManagerSvc' -Force -ErrorAction SilentlyContinue
    Set-Service  'AssignedAccessManagerSvc' -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "    [DISABLED]   AssignedAccessManagerSvc"
} else {
    Write-Host "    [NOT FOUND]  AssignedAccessManagerSvc" -ForegroundColor Gray
}
