# 13_telemetry_tasks.ps1 - Desactive les taches planifiees de telemetrie + PS7 tele + Brave

# --- Taches planifiees de telemetrie Microsoft ---
$tasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
    '\Microsoft\Windows\Application Experience\StartupAppTask'
    '\Microsoft\Windows\Application Experience\MareBackup'
    '\Microsoft\Windows\Autochk\Proxy'
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
    '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask'
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
    '\Microsoft\Windows\Feedback\Siuf\DmClient'
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
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
        Write-Host "    [DESACTIVE] $task"
    } else {
        Write-Host "    [ABSENT]    $task" -ForegroundColor Gray
    }
}

# --- Telemetrie PowerShell 7 ---
[Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
Write-Host "    [SET] POWERSHELL_TELEMETRY_OPTOUT=1 (variable env Machine)"

# --- Brave Browser debloat (conditionnel) ---
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
    Set-ItemProperty -Path $bravePolicy -Name 'BackgroundModeEnabled'    -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $bravePolicy -Name 'MetricsReportingEnabled'  -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $bravePolicy -Name 'UrlKeyedAnonymizedDataCollectionEnabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $bravePolicy -Name 'SafeBrowsingEnabled'      -Value 0 -Type DWord -ErrorAction SilentlyContinue

    $braveUpdate = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Update'
    Set-ItemProperty -Path $braveUpdate -Name 'AutoUpdateCheckPeriodMinutes' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $braveUpdate -Name 'DisableAutoUpdateChecks'       -Value 1 -Type DWord -ErrorAction SilentlyContinue

    Write-Host "    [OK] Brave detecte - politiques telemetrie/arriere-plan appliquees"
} else {
    Write-Host "    Brave non detecte - politiques Brave ignorees" -ForegroundColor Gray
}
