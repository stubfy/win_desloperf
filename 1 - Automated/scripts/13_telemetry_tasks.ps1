# 13_telemetry_tasks.ps1 - Disable telemetry scheduled tasks + PS7 telemetry + Brave
#
# Windows schedules a large number of telemetry collection tasks that run periodically
# in the background regardless of the AllowTelemetry=0 registry policy. These tasks
# can still execute their payload (data collection, hardware inventory, event uploads)
# even when the policy level is set to minimum. Disabling them individually via
# Disable-ScheduledTask prevents their scheduled execution.
#
# Note: Disable-ScheduledTask only marks tasks as disabled; Windows Update can
# re-enable them after a feature update. Re-run this script or check Task Scheduler
# after major updates.

# --- Microsoft telemetry scheduled tasks ---
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
    # reports to Microsoft. WerSvc is also disabled in 03_services.ps1.
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
    $braveInstalled = Test-Path "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe" `
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

    # UrlKeyedAnonymizedDataCollectionEnabled=0: Disables URL-keyed metrics (page
    # load performance data linked to visited domains, even if anonymized).
    Set-ItemProperty -Path $bravePolicy -Name 'UrlKeyedAnonymizedDataCollectionEnabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue

    # SafeBrowsingEnabled=0: Disables Google Safe Browsing URL checks. Each URL
    # visited is hashed and checked against Google's API; disabling trades some
    # phishing protection for privacy and a small reduction in network overhead.
    Set-ItemProperty -Path $bravePolicy -Name 'SafeBrowsingEnabled'      -Value 0 -Type DWord -ErrorAction SilentlyContinue

    $braveUpdate = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Update'
    # Disable automatic Brave update checks (same pattern as Edge in 07_edge.ps1).
    Set-ItemProperty -Path $braveUpdate -Name 'AutoUpdateCheckPeriodMinutes' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $braveUpdate -Name 'DisableAutoUpdateChecks'       -Value 1 -Type DWord -ErrorAction SilentlyContinue

    Write-Host "    [OK] Brave detected - telemetry/background policies applied"
} else {
    Write-Host "    Brave not detected - Brave policies skipped" -ForegroundColor Gray
}
