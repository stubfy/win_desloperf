# privacy.ps1 - Privacy & AI: registry tweaks, OOSU10, AI/Copilot disable, telemetry tasks
# Combines: oosu10.ps1, ai_disable.ps1, telemetry_tasks.ps1
#           + privacy_tweaks.reg import
#           + wscsvc (Windows Security Center) disable
#
# Execution order:
#   1. privacy_tweaks.reg   - privacy/telemetry registry baseline
#   2. OOSU10               - broad privacy sweep (covers undocumented keys)
#   3. AI / Recall / Copilot - specific 25H2 AI feature policies
#   4. Telemetry tasks      - disable scheduled data collection tasks + PS7 + Brave
#   5. wscsvc               - disable Security Center after Defender/firewall are off
#
# Rollback: restore\privacy.ps1
# Note: OOSU10, telemetry tasks, and wscsvc are NOT auto-restored.
#   - OOSU10: use the system restore point created by backup.ps1
#   - Telemetry tasks: re-enable manually via Task Scheduler
#   - wscsvc: restored automatically via restore\services.ps1 (backup JSON)

# === SECTION: Privacy registry tweaks ===

$REG = Join-Path $PSScriptRoot "privacy_tweaks.reg"

if (-not (Test-Path $REG)) {
    Write-Host "    [ERROR] privacy_tweaks.reg not found: $REG"
    exit 1
}

$result = Start-Process regedit.exe -ArgumentList "/s `"$REG`"" -Wait -PassThru
if ($result.ExitCode -eq 0) {
    Write-Host "    [OK] privacy_tweaks.reg imported"
} else {
    Write-Host "    [WARN] regedit exit code: $($result.ExitCode)"
}

# === SECTION: O&O ShutUp10++ (silent mode) ===
# O&O ShutUp10++ applies a comprehensive set of Windows privacy and telemetry
# settings via its own registry/policy engine. Overlap with privacy_tweaks.reg
# is intentional -- OOSU10 covers additional undocumented keys not in the .reg file.

$OOSU_ROOT = Split-Path (Split-Path $PSScriptRoot)
$oosuExe   = Join-Path $OOSU_ROOT "tools\OOSU10.exe"
$oosuCfg   = Join-Path $OOSU_ROOT "tools\ooshutup10.cfg"

if (-not (Test-Path $oosuExe)) {
    Write-Host "    OOSU10.exe not found: $oosuExe" -ForegroundColor Yellow
} elseif (-not (Test-Path $oosuCfg)) {
    Write-Host "    ooshutup10.cfg not found." -ForegroundColor Red
} else {
    Start-Process $oosuExe -ArgumentList "`"$oosuCfg`" /quiet" -Wait -Verb RunAs
    Write-Host "    O&O ShutUp10++ applied: $oosuCfg"
}

# === SECTION: AI / Recall / Copilot / app AI features ===
# Windows 11 25H2 introduces several AI features that run background processes,
# capture screen content, and communicate with Microsoft servers. All keys written
# under HKLM\SOFTWARE\Policies\ or HKCU\SOFTWARE\Policies\ function as Group Policy
# overrides and cannot be changed by the user from the Settings UI.

$policies = @{
    # ---- Recall (Windows 11 24H2+ AI feature) ----
    # Recall continuously captures screenshots and uses a local AI model to make
    # screen content searchable ("what was I looking at three days ago?").
    # DisableAIDataAnalysis=1: Disables the Recall AI analysis pipeline.
    # AllowRecallEnablement=0: Prevents the user from re-enabling Recall in Settings.
    # DisableClickToDo=1 (policy): Disables Click to Do, the 25H2 AI feature that
    #   analyses on-screen content to offer contextual AI actions on click.
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' = @{
        'DisableAIDataAnalysis' = 1
        'AllowRecallEnablement' = 0
        'DisableClickToDo'      = 1
        'DisableSettingsAgent'  = 1
    }

    # ---- Click to Do (user-level override) ----
    # Additional user-level key for Click to Do disable, complementary to the
    # policy key above. Covers cases where the policy is not honoured by the
    # Explorer shell extension before a group policy refresh.
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ClickToDo' = @{
        'DisableClickToDo' = 1
    }

    # ---- Paint AI features ----
    # Official machine-wide Paint policies documented by Microsoft for the main
    # generative features exposed on current Windows 11 builds.
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' = @{
        'DisableCocreator'      = 1
        'DisableGenerativeFill' = 1
        'DisableImageCreator'   = 1
    }
    # Additional user-level Paint flags kept as best-effort coverage for app-side
    # toggles that aren't exposed through the documented HKLM Paint policy set.
    'HKCU:\Software\Microsoft\MSPaint\Settings' = @{
        'DisableCocreator'        = 1
        'DisableGenerativeFill'   = 1
        'DisableImageCreator'     = 1
        'DisableGenerativeErase'  = 1
        'DisableRemoveBackground' = 1
    }

    # ---- Notepad AI features ----
    # Official ADMX-backed machine policy for Notepad AI. Microsoft documents
    # HKLM:\SOFTWARE\Policies\WindowsNotepad\DisableAIFeatures=1 as the
    # supported control to disable Copilot-backed features in Notepad.
    'HKLM:\SOFTWARE\Policies\WindowsNotepad' = @{
        'DisableAIFeatures' = 1
    }
    # Legacy user-level flag kept as a best-effort fallback on builds that still
    # read the per-user settings hive.
    'HKCU:\Software\Microsoft\Notepad\Settings' = @{
        'DisableAIFeatures' = 1
    }

    # ---- Edge AI features ----
    # Disables the AI/Copilot integration points surfaced inside Microsoft Edge.
    # These policy keys mirror the Edge group policy schema (ADMX) and are
    # honoured by Edge regardless of whether the machine is domain-joined.
    # CopilotCDPPageContext=0: Disables Copilot from reading the current page via CDP.
    # CopilotPageContext=0: Blocks Copilot from using page content as context.
    # HubsSidebarEnabled=0: Hides the Edge sidebar (Copilot, Shopping, etc.).
    # EdgeEntraCopilotPageContext=0: Disables Copilot page context for Entra accounts.
    # EdgeHistoryAISearchEnabled=0: Prevents AI-powered history search in Edge.
    # ComposeInlineEnabled=0: Disables the Compose (AI writing assistant) inline mode.
    # GenAILocalFoundationalModelSettings=1: Blocks local AI model downloads by Edge.
    # NewTabPageBingChatEnabled=0: Hides the Bing Chat/Copilot entry on the NTP.
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge' = @{
        'CopilotCDPPageContext'               = 0
        'CopilotPageContext'                  = 0
        'HubsSidebarEnabled'                  = 0
        'EdgeEntraCopilotPageContext'          = 0
        'EdgeHistoryAISearchEnabled'           = 0
        'ComposeInlineEnabled'                = 0
        'GenAILocalFoundationalModelSettings' = 1
        'NewTabPageBingChatEnabled'           = 0
    }

    # ---- Copilot (current user + machine) ----
    # Copilot is the Windows-integrated AI assistant panel. Both HKCU and HKLM
    # keys are set to ensure the policy applies regardless of which hive Windows
    # checks on different builds.
    'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' = @{
        'TurnOffWindowsCopilot' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' = @{
        'TurnOffWindowsCopilot' = 1
    }

    # ---- Copilot taskbar icon ----
    # Show=3: Value 3 hides the Copilot icon from the taskbar entirely.
    # (0=Not configured, 1=Show, 2=Hide, 3=Disable)
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\ChatIcon' = @{
        'Show' = 3
    }

    # ---- Delivery Optimization P2P mode ----
    # DODownloadMode=0: Disables Delivery Optimization peer-to-peer update sharing.
    # Mode 0 = HTTP only (download from Microsoft CDN only, no LAN/Internet peers).
    # This is set here in addition to the DoSvc TriggerInfo removal in services.ps1.
    # The two are intentionally redundant: the registry policy blocks the P2P logic
    # at the protocol layer, while removing TriggerInfo prevents the process from
    # ever starting in the background to check for work.
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' = @{
        'DODownloadMode' = 0
    }

    # ---- Copilot shell availability (WinUtil method) ----
    # These non-policy keys are checked by the Copilot shell runtime at startup
    # to determine whether to activate. Setting both to 0 provides an additional
    # suppression layer on top of the TurnOffWindowsCopilot policy above.
    'HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot' = @{
        'IsCopilotAvailable' = 0
    }
    'HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat' = @{
        'IsUserEligible' = 0
    }
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot' = @{
        'AllowCopilotRuntime' = 0
    }

    # ---- Office AI / Copilot features ----
    # Disable training, connected experiences and content safety prompts used by
    # Copilot-backed Office features.
    'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\training\general' = @{
        'disabletraining' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\training\specific\adaptivefloatie' = @{
        'disabletrainingofadaptivefloatie' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\general' = @{
        'disablecontentsafety' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\alternativetext' = @{
        'disablecontentsafety' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\imagequestionandanswering' = @{
        'disablecontentsafety' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\promptassistance' = @{
        'disablecontentsafety' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\rewrite' = @{
        'disablecontentsafety' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\summarization' = @{
        'disablecontentsafety' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\summarizationwithreferences' = @{
        'disablecontentsafety' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\specific\texttotable' = @{
        'disablecontentsafety' = 1
    }
    'HKCU:\Software\Policies\Microsoft\office\16.0\common\privacy' = @{
        'controllerconnectedservicesenabled' = 2
        'usercontentdisabled'               = 2
    }
    'HKCU:\Software\Microsoft\Office\16.0\Word\Options' = @{
        'EnableCopilot' = 0
    }
    'HKCU:\Software\Microsoft\Office\16.0\Excel\Options' = @{
        'EnableCopilot' = 0
    }
    'HKCU:\Software\Microsoft\Office\16.0\OneNote\Options\Copilot' = @{
        'CopilotEnabled'          = 0
        'CopilotNotebooksEnabled' = 0
        'CopilotSkittleEnabled'   = 0
    }
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings' = @{
        'AutoOpenCopilotLargeScreens' = 0
    }

    # ---- Cross-Device Resume (CDP) ----
    # EnableCdp=0: Disables the Connected Devices Platform (CDP) which powers
    # the "Cross-Device Resume" feature (24H2+). CDP allows Windows to resume
    # phone/browser activity on the PC and syncs clipboard/notifications across
    # devices. Also related to CDPSvc which is set to Manual in services.ps1.
    # Note: EnableActivityFeed/PublishUserActivities in tweaks_consolidated.reg
    # also disables Timeline which uses the same CDP infrastructure.
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' = @{
        'EnableCdp' = 0
    }

    # ---- Nearby Sharing / Drag Tray ----
    # FeatureManagement override used on recent Windows 11 builds to suppress
    # the Drag Tray / Nearby Sharing surface tied to cross-device sharing.
    'HKLM:\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\14\3895955085' = @{
        'EnabledState' = 1
        'EnabledStateOptions' = 0
    }
    'HKLM:\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\14\3895955085' = @{
        'EnabledState' = 1
        'EnabledStateOptions' = 0
    }
}

foreach ($path in $policies.Keys) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    foreach ($name in $policies[$path].Keys) {
        Set-ItemProperty -Path $path -Name $name -Value $policies[$path][$name] -Type DWord -ErrorAction SilentlyContinue
        Write-Host "    [SET] $name = $($policies[$path][$name])  ($path)"
    }
}


# --- Refresh Paint app settings so AI/Copilot policy is re-read ---
$paintPackageRoot = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.Paint_8wekyb3d8bbwe'
$paintSettingsDir = Join-Path $paintPackageRoot 'Settings'
$paintStateNames = @('settings.dat', 'settings.dat.LOG1', 'settings.dat.LOG2', 'roaming.lock')
$paintStateReset = $false

Get-Process -Name 'mspaint' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $paintSettingsDir) {
    foreach ($name in $paintStateNames) {
        $target = Join-Path $paintSettingsDir $name
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            $paintStateReset = $true
        }
    }
}

if ($paintStateReset) {
    Write-Host '    [SET] Paint app settings reset so AI policy is re-read on next launch'
} else {
    Write-Host '    [INFO] Paint app settings not found; reset skipped' -ForegroundColor DarkGray
}# --- Voice Access ---
$voiceAccessPath = 'HKCU:\Software\Microsoft\VoiceAccess'
if (-not (Test-Path $voiceAccessPath)) { New-Item -Path $voiceAccessPath -Force | Out-Null }
Set-ItemProperty -Path $voiceAccessPath -Name 'RunningState' -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $voiceAccessPath -Name 'TextCorrection' -Value 1 -Type DWord -ErrorAction SilentlyContinue
Write-Host '    [SET] Voice Access startup + correction disabled'

# --- Hide AI Components page in Settings ---
$visibilityPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
if (-not (Test-Path $visibilityPath)) { New-Item -Path $visibilityPath -Force | Out-Null }
$currentVisibility = try { Get-ItemPropertyValue -Path $visibilityPath -Name 'SettingsPageVisibility' -ErrorAction Stop } catch { $null }
if ($currentVisibility -like 'showonly:*') {
    Write-Host '    [SKIP] AI Components hide skipped because SettingsPageVisibility uses showonly:' -ForegroundColor Gray
} else {
    $tokens = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($currentVisibility) -and $currentVisibility -like 'hide:*') {
        foreach ($token in ($currentVisibility.Substring(5) -split ';')) {
            if (-not [string]::IsNullOrWhiteSpace($token) -and -not $tokens.Contains($token)) {
                [void]$tokens.Add($token)
            }
        }
    }
    foreach ($token in @('aicomponents', 'appactions')) {
        if (-not $tokens.Contains($token)) {
            [void]$tokens.Add($token)
        }
    }
    $newVisibility = 'hide:' + (($tokens | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ';') + ';'
    Set-ItemProperty -Path $visibilityPath -Name 'SettingsPageVisibility' -Value $newVisibility -Type String -ErrorAction SilentlyContinue
    Write-Host "    [SET] SettingsPageVisibility = $newVisibility"
}

Write-Host '    [INFO] AI voice effects require device-specific registry state; only best-effort coverage is applied here.' -ForegroundColor DarkGray

# Block the Copilot shell extension (registered shell handler CLSID).
# Adding a CLSID to Shell Extensions\Blocked prevents it from loading into
# Explorer's context menu and shell extension pipeline. The same key in
# tweaks_consolidated.reg blocks other unwanted extensions; Copilot is added here
# separately because it is handled by the AI section, not the context menu section.
$blockedPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
if (-not (Test-Path $blockedPath)) { New-Item -Path $blockedPath -Force | Out-Null }
Set-ItemProperty -Path $blockedPath -Name "{CB5571B1-A131-4C41-BFEF-57696FCE7CA2}" -Value "Copilot Shell Extension" -Type String -ErrorAction SilentlyContinue
Write-Host "    [SET] Copilot shell extension blocked"

# === SECTION: Telemetry scheduled tasks ===
# Windows schedules a large number of telemetry collection tasks that run periodically
# in the background regardless of the AllowTelemetry=0 registry policy. These tasks
# can still execute their payload even when the policy level is set to minimum.
# Disabling them individually via Disable-ScheduledTask prevents their execution.
#
# Note: Windows Update can re-enable them after a feature update. Re-run this
# script or check Task Scheduler after major updates.

$tasks = @(
    # Application Experience tasks:
    # Microsoft Compatibility Appraiser: analyses installed apps and hardware for
    #   Windows upgrade compatibility; uploads results to Microsoft. Runs daily.
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
    # ProgramDataUpdater: updates the compatibility database used by the Appraiser.
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
    # StartupAppTask: scans startup programs for compatibility issues and suggests
    #   removing them; also sends startup app inventory to Microsoft.
    '\Microsoft\Windows\Application Experience\StartupAppTask'
    # MareBackup: backs up App Compat data for migration scenarios.
    '\Microsoft\Windows\Application Experience\MareBackup'

    # Autochk Proxy: forwards disk diagnostic data to the Windows Error Reporting
    # pipeline when chkdsk detects problems.
    '\Microsoft\Windows\Autochk\Proxy'

    # Customer Experience Improvement Program (CEIP):
    # Consolidator: aggregates and uploads usage statistics to Microsoft.
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
    # KernelCeipTask: collects kernel-level performance telemetry for CEIP.
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask'
    # UsbCeip: collects USB device usage data for CEIP.
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'

    # DiskDiagnosticDataCollector: monitors disk health and sends SMART data to
    # Microsoft. Uses EventTrigger on disk errors; disabled to prevent data upload.
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'

    # System-Initiated User Feedback (SIUF):
    # DmClient: downloads and executes feedback surveys from Microsoft's servers.
    '\Microsoft\Windows\Feedback\Siuf\DmClient'
    # DmClientOnScenarioDownload: a variant that triggers on specific usage scenarios.
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'

    # Windows Error Reporting queue processor: uploads crash dumps and Watson
    # reports to Microsoft. WerSvc is also disabled in services.ps1.
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting'

    # CloudExperienceHost: sends setup/OOBE completion telemetry and triggers
    # Microsoft account sign-in nudges after new user profile creation.
    '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask'
)

foreach ($task in $tasks) {
    $t = Get-ScheduledTask -TaskPath (Split-Path $task -Parent) `
                           -TaskName  (Split-Path $task -Leaf) `
                           -ErrorAction SilentlyContinue
    if ($t) {
        Disable-ScheduledTask -TaskPath (Split-Path $task -Parent) `
                              -TaskName  (Split-Path $task -Leaf) `
                              -ErrorAction SilentlyContinue | Out-Null
        Write-Host "    [DISABLED]   $task"
    } else {
        Write-Host "    [NOT FOUND]  $task" -ForegroundColor Gray
    }
}

# --- PowerShell 7 telemetry ---
# PowerShell 7 (pwsh.exe) sends anonymous usage data to Microsoft by default,
# including which cmdlets are run. Setting the environment variable to '1'
# opts out system-wide (Machine scope = affects all users and processes).
[Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
Write-Host "    [SET] POWERSHELL_TELEMETRY_OPTOUT=1 (Machine env variable)"

# --- Brave Browser debloat (conditional) ---
# Applied only if Brave is detected (checked via registry key or file path).
# These Group Policy values mirror the corporate policy settings for Brave,
# which Brave honors even without a domain-joined configuration.
$bravePaths = @(
    'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
    'HKLM:\SOFTWARE\Policies\BraveSoftware\Update'
)
$braveInstalled = Test-Path 'HKLM:\SOFTWARE\BraveSoftware\Brave-Browser' `
    -ErrorAction SilentlyContinue

if (-not $braveInstalled) {
    $braveInstalled = Test-Path 'HKLM:\SOFTWARE\WOW6432Node\BraveSoftware\Brave-Browser' `
        -ErrorAction SilentlyContinue
}

if (-not $braveInstalled) {
    $braveInstalled = Test-Path 'HKCU:\SOFTWARE\BraveSoftware\Brave-Browser' `
        -ErrorAction SilentlyContinue
}

if (-not $braveInstalled) {
    # Resolve the actual logged-on user's LOCALAPPDATA when running elevated
    $userLocalAppData = (Get-ItemProperty -Path 'HKCU:\Volatile Environment' -Name 'LOCALAPPDATA' -ErrorAction SilentlyContinue).LOCALAPPDATA
    if (-not $userLocalAppData) { $userLocalAppData = $env:LOCALAPPDATA }
    $braveInstalled = Test-Path "$userLocalAppData\BraveSoftware\Brave-Browser\Application\brave.exe" `
        -ErrorAction SilentlyContinue
}

if ($braveInstalled) {
    foreach ($path in $bravePaths) {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    }
    $bravePolicy = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'

    # BackgroundModeEnabled=0: Prevents Brave from running background processes
    # after all windows are closed. Without this, Brave keeps its renderer alive
    # for push notifications even when not in use.
    Set-ItemProperty -Path $bravePolicy -Name 'BackgroundModeEnabled'    -Value 0 -Type DWord -ErrorAction SilentlyContinue

    # MetricsReportingEnabled=0: Disables Brave's anonymous usage statistics upload.
    Set-ItemProperty -Path $bravePolicy -Name 'MetricsReportingEnabled'  -Value 0 -Type DWord -ErrorAction SilentlyContinue

    # UrlKeyedAnonymizedDataCollectionEnabled=0: Disables URL-keyed metrics.
    Set-ItemProperty -Path $bravePolicy -Name 'UrlKeyedAnonymizedDataCollectionEnabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue

    # SafeBrowsingEnabled=0: Disables Google Safe Browsing URL checks.
    Set-ItemProperty -Path $bravePolicy -Name 'SafeBrowsingEnabled'      -Value 0 -Type DWord -ErrorAction SilentlyContinue

    $braveUpdate = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Update'
    Set-ItemProperty -Path $braveUpdate -Name 'AutoUpdateCheckPeriodMinutes' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $braveUpdate -Name 'DisableAutoUpdateChecks'       -Value 1 -Type DWord -ErrorAction SilentlyContinue

    # Disable Brave built-in monetisation / AI / social features.
    Set-ItemProperty -Path $bravePolicy -Name 'BraveVPNDisabled'     -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $bravePolicy -Name 'BraveWalletDisabled'  -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $bravePolicy -Name 'BraveAIChatEnabled'   -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $bravePolicy -Name 'BraveRewardsDisabled' -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $bravePolicy -Name 'BraveTalkDisabled'    -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $bravePolicy -Name 'BraveNewsDisabled'    -Value 1 -Type DWord -ErrorAction SilentlyContinue

    Write-Host "    [OK] Brave detected - telemetry/background policies applied"
} else {
    Write-Host "    Brave not detected - Brave policies skipped" -ForegroundColor Gray
}

# === SECTION: Windows Security Center ===
# wscsvc monitors the state of security products (antivirus, firewall, WU)
# and generates Action Center alerts when it detects a gap. With Defender
# deliberately disabled and the firewall off, wscsvc would generate constant
# false alarms. Disabling it suppresses these alerts.
# wscsvc is restored automatically via restore\services.ps1 (JSON backup).
$svc = Get-Service 'wscsvc' -ErrorAction SilentlyContinue
if ($svc) {
    Stop-Service  'wscsvc' -Force -ErrorAction SilentlyContinue
    Set-Service   'wscsvc' -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "    [DISABLED]   wscsvc (Windows Security Center)"
} else {
    Write-Host "    [NOT FOUND]  wscsvc" -ForegroundColor Gray
}
