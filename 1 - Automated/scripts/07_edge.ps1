# 07_edge.ps1 - Apply policies to disable intrusive Edge behaviors

$edgePolicies = @{
    'AllowPrelaunch'              = 0
    'PreLaunchEnabled'            = 0
    'SyncDisabled'                = 1
    'TabFreezing'                 = 0
    'BrowserGuestModeEnabled'     = 0
    'DisableGuestMode'            = 1
    'HideFirstRunExperience'      = 1
    'TamperProtectionEnabled'     = 1
    'AudioSandboxEnabled'         = 0
    'WebRtcLocalhostIpHandling'   = 2
    'InPrivateAllowed'            = 0
    'PasswordImportEnabled'       = 0
    'NavigateOnDragDrop'          = 1
    'SafeSearchEnabled'           = 1
    'ImportBrowserData'           = 0
    'ProtectHomepages'            = 1
    'ManagedPasswordGeneration'   = 0
}

$edgePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
if (-not (Test-Path $edgePath)) { New-Item -Path $edgePath -Force | Out-Null }
foreach ($name in $edgePolicies.Keys) {
    Set-ItemProperty -Path $edgePath -Name $name -Value $edgePolicies[$name] -Type DWord -ErrorAction SilentlyContinue
}
Write-Host "    Edge policies applied ($($edgePolicies.Count) settings)"

# Disable automatic Edge updates
$edgeUpdatePath = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
if (-not (Test-Path $edgeUpdatePath)) { New-Item -Path $edgeUpdatePath -Force | Out-Null }
Set-ItemProperty -Path $edgeUpdatePath -Name 'AutoUpdateCheckPeriodMinutes' -Value 0  -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $edgeUpdatePath -Name 'DisableAutoUpdateChecks'       -Value 1  -Type DWord -ErrorAction SilentlyContinue
Write-Host "    Automatic Edge updates disabled"
