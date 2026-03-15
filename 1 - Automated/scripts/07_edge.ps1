# 07_edge.ps1 - Apply policies to disable intrusive Edge behaviors
#
# All settings are written to HKLM:\SOFTWARE\Policies\Microsoft\Edge.
# Group Policy keys in this path override Edge's own settings UI and
# survive profile resets (the user cannot change them from within Edge).
#
# Rollback: restore\05_edge.ps1 removes the entire Policies\Microsoft\Edge key.

$edgePolicies = @{
    # Prevents Edge from pre-launching at Windows startup (before the user
    # opens it). Pre-launch keeps a hidden Edge window in memory to reduce
    # perceived load time, at the cost of RAM and startup CPU usage.
    'AllowPrelaunch'              = 0

    # Prevents Edge from launching a background process at Windows startup
    # to pre-warm the browser engine. Similar to AllowPrelaunch but covers
    # the newer "startup boost" feature introduced in Edge 88+.
    'PreLaunchEnabled'            = 0

    # Disables sync of bookmarks, history, passwords and settings to the
    # Microsoft account. Keeps browsing data local only.
    'SyncDisabled'                = 1

    # Prevents Edge from freezing background tabs to reclaim RAM.
    # Freezing discards the tab's JavaScript state and can cause pages to
    # reload unexpectedly. Disabled here because Edge is already a secondary
    # browser on this PC and tab memory is acceptable.
    'TabFreezing'                 = 0

    # Disables guest browsing mode (incognito sessions not tied to any profile).
    'BrowserGuestModeEnabled'     = 0
    'DisableGuestMode'            = 1

    # Suppresses the "Welcome to Microsoft Edge" first-run experience and
    # the data-import wizard that appears on first launch.
    'HideFirstRunExperience'      = 1

    # Disables Edge's internal "Tamper Protection" for browser settings.
    # Without this Edge may periodically reset policies it considers invalid.
    # Note: This is Edge's own tamper protection, unrelated to Windows Defender's.
    'TamperProtectionEnabled'     = 1

    # Disables the audio process sandbox. Edge normally runs audio in an
    # isolated renderer process; disabling the sandbox reduces context-switch
    # overhead on the audio path. Minor gain; kept because all audio gain is
    # worthwhile and there is no meaningful security regression on a gaming PC.
    'AudioSandboxEnabled'         = 0

    # WebRTC local IP handling: 2 = disable non-proxied UDP.
    # Prevents WebRTC (used by video-call sites) from leaking the LAN IP address
    # through STUN/ICE candidates to the remote peer.
    'WebRtcLocalhostIpHandling'   = 2

    # Disables InPrivate (private browsing) mode. On a single-user gaming PC
    # private mode offers no meaningful privacy benefit; blocked to simplify usage.
    'InPrivateAllowed'            = 0

    # Prevents importing saved passwords from other browsers during setup.
    'PasswordImportEnabled'       = 0

    # Allows drag-and-drop of URLs/links to navigate to them. Quality-of-life
    # feature kept enabled (value 1 = allowed).
    'NavigateOnDragDrop'          = 1

    # Enforces SafeSearch in Bing results (moderate filtering).
    'SafeSearchEnabled'           = 1

    # Prevents importing browser data (bookmarks, history, cookies) at first run.
    'ImportBrowserData'           = 0

    # Prevents sites from locking the default search engine or homepage setting.
    'ProtectHomepages'            = 1

    # Disables Edge's built-in password generator suggestion.
    'ManagedPasswordGeneration'   = 0
}

$edgePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
if (-not (Test-Path $edgePath)) { New-Item -Path $edgePath -Force | Out-Null }
foreach ($name in $edgePolicies.Keys) {
    Set-ItemProperty -Path $edgePath -Name $name -Value $edgePolicies[$name] -Type DWord -ErrorAction SilentlyContinue
}
Write-Host "    Edge policies applied ($($edgePolicies.Count) settings)"

# Disable automatic Edge updates.
# AutoUpdateCheckPeriodMinutes=0: Never poll for updates.
# DisableAutoUpdateChecks=1: Additional flag that blocks the update check entirely.
# EdgeUpdate runs as a scheduled task and as a Windows service (edgeupdate/edgeupdatem),
# both set to Manual in 03_services.ps1. These registry values prevent updates even
# if those services are manually started.
$edgeUpdatePath = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
if (-not (Test-Path $edgeUpdatePath)) { New-Item -Path $edgeUpdatePath -Force | Out-Null }
Set-ItemProperty -Path $edgeUpdatePath -Name 'AutoUpdateCheckPeriodMinutes' -Value 0  -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $edgeUpdatePath -Name 'DisableAutoUpdateChecks'       -Value 1  -Type DWord -ErrorAction SilentlyContinue
Write-Host "    Automatic Edge updates disabled"
