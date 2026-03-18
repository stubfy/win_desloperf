#Requires -RunAsAdministrator
<#
.SYNOPSIS
    win_desloperf - Main launcher
    Windows 11 25H2 - Gaming optimization / Debloat / QoL

.DESCRIPTION
    Runs all automatable tweaks in the recommended order.
    Creates a backup before any modification.
    To undo: .\restore_all.ps1

    Execution order:
      Phase A - Snapshot + Backup (snapshot, backup)
      Phase B - Tweaks in dependency order:
        registry             -> consolidated reg file + visual effects + MarkC mouse fix
        services             -> startup type alignment
        performance          -> Ultimate Performance plan + BCD + USB selective suspend
        [7 - DNS]            -> Cloudflare DNS (user choice)
        debloat              -> UWP app removal
        privacy              -> OOSU10 + AI/Copilot/Recall + telemetry tasks + privacy registry
        timer                -> Optional SetTimerResolution startup
        network_tweaks       -> Teredo disable + TCP/Nagle/QoS
        [8 - Windows Update] -> WU profile (user choice)
        firewall             -> Firewall disable (user choice)
        personal_settings    -> Subjective shell/theme preferences (user choice)
        [6 - Interrupt Affinity] -> GPU IRQ pin to core 2 (user choice)
      Options - Edge uninstall, OneDrive uninstall (user choice)
      Phase C - Diff report (show_diff)

    Logging: all output is written to %APPDATA%\win_desloperf\logs\win_desloperf.log
    Format: [HH:mm:ss] [LEVEL] message
    Levels: INFO, STEP, RUN, OUT, OK, WARN, ERROR

    The launch configuration is edited from a single keyboard-driven menu at the
    start of the run and saved to 1 - Automated\backup\run_all_options.json.
    Defender Safe Mode remains a final confirmation so the script never reboots
    without warning.

.NOTES
    Manual steps after execution: see README.md at the pack root
#>

$ErrorActionPreference = 'Continue'
$ROOT                  = Split-Path (Split-Path (Split-Path $MyInvocation.MyCommand.Path))
$PACK_ROOT             = Split-Path $ROOT -Parent
$SCRIPTS               = $PSScriptRoot
$BACKUP_DIR            = Join-Path $ROOT 'backup'
$MSI_UTILS_DIR         = Join-Path $PACK_ROOT '3 - MSI Utils'
$NVINSPECTOR_DIR       = Join-Path $PACK_ROOT '4 - NVInspector'
$RUN_ALL_OPTIONS_FILE  = Join-Path $BACKUP_DIR 'run_all_options.json'
$MSI_STATE_FILE        = Join-Path $BACKUP_DIR 'msi_state.json'
$LEGACY_MSI_STATE_FILE = Join-Path $MSI_UTILS_DIR 'msi_state.json'
$LOG_DIR               = Join-Path $env:APPDATA 'win_desloperf\logs'
$LOG_FILE              = Join-Path $LOG_DIR 'win_desloperf.log'

if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }

function Get-PackVersion {
    param([string]$PackRoot)

    $versionFile = Join-Path $PackRoot 'pack-version.txt'
    if (Test-Path $versionFile) {
        $raw = Get-Content -Path $versionFile -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            return $raw.Trim()
        }
    }

    return 'v0.9'
}

$PACK_VERSION = Get-PackVersion -PackRoot $PACK_ROOT

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Msg
    Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
}

function Write-Step {
    param([string]$Msg)
    Write-Host ''
    Write-Host ">>> $Msg" -ForegroundColor Yellow
    Write-Log $Msg 'STEP'
}

function Unblock-LaunchFile {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return
    }

    try {
        Unblock-File -LiteralPath $Path -ErrorAction Stop
    } catch {
    }
}

function Unblock-PackLaunchFiles {
    param([string]$RootPath)

    if ([string]::IsNullOrWhiteSpace($RootPath) -or -not (Test-Path $RootPath)) {
        return
    }

    try {
        Get-ChildItem -Path $RootPath -Recurse -File | Where-Object {
            $_.Extension -in @('.ps1', '.psm1', '.bat', '.cmd')
        } | ForEach-Object {
            try {
                Unblock-File -LiteralPath $_.FullName -ErrorAction Stop
            } catch {
            }
        }

        Write-Log "Checked downloaded script files for MOTW under: $RootPath" 'INFO'
    } catch {
        Write-Log ("Unable to scan pack for blocked files: {0}" -f $_.Exception.Message) 'WARN'
    }
}

Unblock-PackLaunchFiles -RootPath $PACK_ROOT

function Invoke-Script {
    param([string]$Path, [hashtable]$Params = @{})
    $name = Split-Path $Path -Leaf
    Write-Host "    $name ... " -NoNewline
    Write-Log "Start: $name" 'RUN'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Unblock-LaunchFile -Path $Path
        & $Path @Params *>&1 | ForEach-Object {
            $line = $_
            if ($line -is [System.Management.Automation.ErrorRecord]) {
                Write-Log "  [ERR] $($line.Exception.Message)" 'WARN'
                Write-Host ''
                Write-Host "      [ERR] $($line.Exception.Message)" -ForegroundColor Yellow
            } else {
                Write-Log "  $line" 'OUT'
                if ($null -ne $line -and "$line".Trim().Length -gt 0) {
                    Write-Host ''
                    Write-Host "      $line" -ForegroundColor DarkGray
                }
            }
        }
        $sw.Stop()
        Write-Host '[OK]' -ForegroundColor Green
        Write-Log "End: $name -> OK ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" 'OK'
    } catch {
        $sw.Stop()
        Write-Host "[ERROR] $_" -ForegroundColor Red
        Write-Log "End: $name -> ERROR after $([math]::Round($sw.Elapsed.TotalSeconds, 1))s: $_" 'ERROR'
        Write-Log "  StackTrace: $($_.ScriptStackTrace)" 'ERROR'
    }
}

function Ensure-DirectoryExists {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-OrderedHashtable {
    param([hashtable]$Source)

    $copy = [ordered]@{}
    foreach ($key in $Source.Keys) {
        $copy[$key] = $Source[$key]
    }

    return $copy
}

function Convert-ToOptionBool {
    param(
        $Value,
        [bool]$Default
    )

    if ($null -eq $Value) {
        return $Default
    }

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    switch -Regex ($Value.ToString().Trim()) {
        '^(1|true|yes|y|on)$' { return $true }
        '^(0|false|no|n|off)$' { return $false }
        default { return $Default }
    }
}
function Get-PreferredDisplayGpu {
    $allGpus = @()
    if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
        $allGpus = Get-PnpDevice -Class Display -Status OK -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match '^PCI\\' }
    }

    if (-not $allGpus) {
        $allGpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPDeviceID -match '^PCI\\' } |
            ForEach-Object {
                [PSCustomObject]@{
                    FriendlyName = $_.Name
                    InstanceId   = $_.PNPDeviceID
                }
            }
    }

    if (-not $allGpus) {
        return $null
    }

    $igpuPattern = 'Intel.*(UHD|Iris|HD Graphics)|Microsoft Basic Display'
    $dGpus = $allGpus | Where-Object { $_.FriendlyName -notmatch $igpuPattern }
    if (-not $dGpus) {
        $dGpus = $allGpus
    }

    $gpu = $dGpus | Where-Object { $_.FriendlyName -match 'NVIDIA' } | Select-Object -First 1
    if (-not $gpu) { $gpu = $dGpus | Where-Object { $_.FriendlyName -match 'AMD|Radeon' } | Select-Object -First 1 }
    if (-not $gpu) { $gpu = $dGpus | Select-Object -First 1 }

    return $gpu
}

function Get-UpdateProfileLabel {
    param([string]$Profile)

    return @{
        '1' = 'Maximum'
        '2' = 'Security only'
        '3' = 'Disabled'
    }[$Profile]
}

function Get-RunAllDefaultOptions {
    param(
        [bool]$HasNvidiaGpu,
        [bool]$HasMsiSnapshot
    )

    return [ordered]@{
        defenderStep          = $true
        updateProfile         = '2'
        uninstallEdge         = $true
        uninstallOneDrive     = $true
        disableFirewall       = $true
        configureDns          = $true
        enableTimerTool       = $true
        applyPersonalSettings = $true
        installNvInspector    = $HasNvidiaGpu
        setInterruptAffinity  = $true
        applySavedMsi         = $HasMsiSnapshot
    }
}

function Resolve-MsiStateFile {
    param(
        [string]$CanonicalPath,
        [string]$LegacyPath
    )

    if (Test-Path $CanonicalPath) {
        return $CanonicalPath
    }

    if (-not (Test-Path $LegacyPath)) {
        return $CanonicalPath
    }

    try {
        Ensure-DirectoryExists -Path (Split-Path $CanonicalPath -Parent)
        Copy-Item -LiteralPath $LegacyPath -Destination $CanonicalPath -Force
        Write-Host "  Migrated legacy MSI snapshot to $CanonicalPath" -ForegroundColor DarkGray
        Write-Log "Migrated legacy MSI snapshot from $LegacyPath to $CanonicalPath" 'WARN'
        return $CanonicalPath
    } catch {
        Write-Host '  WARN: Could not migrate legacy MSI snapshot, using old path for this run.' -ForegroundColor Yellow
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Log ("Failed to migrate legacy MSI snapshot from {0} to {1}: {2}" -f $LegacyPath, $CanonicalPath, $_.Exception.Message) 'WARN'
        return $LegacyPath
    }
}

function Load-RunAllOptions {
    param(
        [string]$Path,
        [hashtable]$Defaults,
        [bool]$HasNvidiaGpu,
        [bool]$HasMsiSnapshot
    )

    $options = Copy-OrderedHashtable -Source $Defaults
    if (-not (Test-Path $Path)) {
        return $options
    }

    try {
        $loaded = Get-Content -Path $Path -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host '  WARN: Failed to load saved run_all options, defaults will be used.' -ForegroundColor Yellow
        Write-Log ("Failed to read {0}: {1}" -f $Path, $_.Exception.Message) 'WARN'
        return $options
    }

    $boolKeys = @(
        'defenderStep',
        'uninstallEdge',
        'uninstallOneDrive',
        'disableFirewall',
        'configureDns',
        'enableTimerTool',
        'applyPersonalSettings',
        'installNvInspector',
        'setInterruptAffinity',
        'applySavedMsi'
    )

    foreach ($key in $boolKeys) {
        if ($loaded.PSObject.Properties.Name -contains $key) {
            $options[$key] = Convert-ToOptionBool -Value $loaded.$key -Default ([bool]$options[$key])
        }
    }

    if ($loaded.PSObject.Properties.Name -contains 'updateProfile') {
        $candidate = "$($loaded.updateProfile)".Trim()
        if ($candidate -in @('1', '2', '3')) {
            $options['updateProfile'] = $candidate
        }
    }

    if (-not $HasNvidiaGpu) {
        $options['installNvInspector'] = $false
    }

    if (-not $HasMsiSnapshot) {
        $options['applySavedMsi'] = $false
    }

    Write-Log "Loaded saved launch options from $Path" 'INFO'
    return $options
}

function Save-RunAllOptions {
    param(
        [string]$Path,
        [hashtable]$Options
    )

    Ensure-DirectoryExists -Path (Split-Path $Path -Parent)

    $payload = [ordered]@{
        schemaVersion         = 1
        savedAt               = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        defenderStep          = [bool]$Options['defenderStep']
        updateProfile         = [string]$Options['updateProfile']
        uninstallEdge         = [bool]$Options['uninstallEdge']
        uninstallOneDrive     = [bool]$Options['uninstallOneDrive']
        disableFirewall       = [bool]$Options['disableFirewall']
        configureDns          = [bool]$Options['configureDns']
        enableTimerTool       = [bool]$Options['enableTimerTool']
        applyPersonalSettings = [bool]$Options['applyPersonalSettings']
        installNvInspector    = [bool]$Options['installNvInspector']
        setInterruptAffinity  = [bool]$Options['setInterruptAffinity']
        applySavedMsi         = [bool]$Options['applySavedMsi']
    }

    try {
        $payload | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8
        Write-Log "Saved launch options to $Path" 'INFO'
    } catch {
        Write-Host "  WARN: Failed to save launch options to $Path" -ForegroundColor Yellow
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Log ("Failed to save launch options to {0}: {1}" -f $Path, $_.Exception.Message) 'WARN'
    }
}
function Get-LaunchMenuItems {
    param(
        [bool]$HasNvidiaGpu,
        [bool]$HasMsiSnapshot
    )

    $items = @(
        [PSCustomObject]@{ Type = 'option'; Id = 'defenderStep'; Label = 'Run Defender Safe Mode step at the end' }
        [PSCustomObject]@{ Type = 'option'; Id = 'updateProfile'; Label = 'Windows Update profile' }
        [PSCustomObject]@{ Type = 'option'; Id = 'uninstallEdge'; Label = 'Uninstall Microsoft Edge + WebView2' }
        [PSCustomObject]@{ Type = 'option'; Id = 'uninstallOneDrive'; Label = 'Uninstall OneDrive' }
        [PSCustomObject]@{ Type = 'option'; Id = 'disableFirewall'; Label = 'Disable Windows Firewall profiles' }
        [PSCustomObject]@{ Type = 'option'; Id = 'configureDns'; Label = 'Apply Cloudflare DNS' }
        [PSCustomObject]@{ Type = 'option'; Id = 'enableTimerTool'; Label = 'Enable SetTimerResolution at startup' }
        [PSCustomObject]@{ Type = 'option'; Id = 'applyPersonalSettings'; Label = 'Apply personal shell settings' }
    )

    if ($HasNvidiaGpu) {
        $items += [PSCustomObject]@{ Type = 'option'; Id = 'installNvInspector'; Label = 'Install NVIDIA Profile Inspector' }
    }

    $items += [PSCustomObject]@{ Type = 'option'; Id = 'setInterruptAffinity'; Label = 'Pin GPU interrupt affinity to core 2' }

    if ($HasMsiSnapshot) {
        $items += [PSCustomObject]@{ Type = 'option'; Id = 'applySavedMsi'; Label = 'Apply saved MSI snapshot' }
    }

    $items += [PSCustomObject]@{ Type = 'action'; Id = 'run'; Label = 'Launch now' }
    $items += [PSCustomObject]@{ Type = 'action'; Id = 'quit'; Label = 'Quit' }

    return $items
}

function Get-LaunchMenuValueText {
    param(
        [string]$Id,
        [hashtable]$Options
    )

    switch ($Id) {
        'updateProfile' { return "[{0}]" -f (Get-UpdateProfileLabel -Profile $Options['updateProfile']) }
        'run' { return '[Enter]' }
        'quit' { return '[Esc]' }
        default { return if ([bool]$Options[$Id]) { '[x]' } else { '[ ]' } }
    }
}

function Invoke-LaunchMenuSelection {
    param(
        [hashtable]$Options,
        [pscustomobject]$Item
    )

    if ($Item.Type -ne 'option') {
        return
    }

    switch ($Item.Id) {
        'updateProfile' {
            $Options['updateProfile'] = switch ($Options['updateProfile']) {
                '1' { '2' }
                '2' { '3' }
                default { '1' }
            }
        }
        default {
            $Options[$Item.Id] = -not [bool]$Options[$Item.Id]
        }
    }
}

function Show-LaunchOptionsMenu {
    param(
        [hashtable]$Options,
        [bool]$HasNvidiaGpu,
        [bool]$HasMsiSnapshot,
        [string]$OptionsFile,
        [string]$MsiStateFile
    )

    $items = Get-LaunchMenuItems -HasNvidiaGpu $HasNvidiaGpu -HasMsiSnapshot $HasMsiSnapshot
    $selectedIndex = 0

    while ($true) {
        Clear-Host
        Write-Host ''
        Write-Host "  win_desloperf $PACK_VERSION" -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  CONFIGURATION BEFORE LAUNCH' -ForegroundColor Magenta
        Write-Host '  Up/Down: select   Space: toggle/change   Enter: confirm   Esc: quit' -ForegroundColor DarkGray
        Write-Host '  Saved choices become the defaults on future runs.' -ForegroundColor DarkGray
        Write-Host ''
        if (Test-Path $OptionsFile) {
            Write-Host "  Saved defaults : $OptionsFile" -ForegroundColor DarkGray
        } else {
            Write-Host '  Saved defaults : none yet (this run will create them after launch)' -ForegroundColor DarkGray
        }
        if ($HasMsiSnapshot) {
            Write-Host "  MSI snapshot   : $MsiStateFile" -ForegroundColor DarkGray
        }
        Write-Host ''

        for ($i = 0; $i -lt $items.Count; $i++) {
            $item = $items[$i]
            $prefix = if ($i -eq $selectedIndex) { '>' } else { ' ' }
            $valueText = Get-LaunchMenuValueText -Id $item.Id -Options $Options
            $line = " {0} {1,-56} {2}" -f $prefix, $item.Label, $valueText
            if ($item.Type -eq 'action') {
                $color = if ($i -eq $selectedIndex) { 'Yellow' } else { 'White' }
                Write-Host $line -ForegroundColor $color
            } else {
                $color = if ($i -eq $selectedIndex) { 'White' } else { 'Gray' }
                Write-Host $line -ForegroundColor $color
            }
        }

        Write-Host ''
        Write-Host '  Defender stays enabled by default, but the final reboot is always confirmed.' -ForegroundColor DarkGray
        Write-Host ''

        $keyInfo = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($keyInfo.VirtualKeyCode) {
            38 {
                if ($selectedIndex -le 0) { $selectedIndex = $items.Count - 1 } else { $selectedIndex-- }
                continue
            }
            40 {
                if ($selectedIndex -ge ($items.Count - 1)) { $selectedIndex = 0 } else { $selectedIndex++ }
                continue
            }
            32 {
                $selectedItem = $items[$selectedIndex]
                if ($selectedItem.Type -eq 'action') {
                    if ($selectedItem.Id -eq 'run') { return $Options }
                    return $null
                }
                Invoke-LaunchMenuSelection -Options $Options -Item $selectedItem
                continue
            }
            13 {
                $selectedItem = $items[$selectedIndex]
                if ($selectedItem.Type -eq 'action') {
                    if ($selectedItem.Id -eq 'run') { return $Options }
                    return $null
                }
                Invoke-LaunchMenuSelection -Options $Options -Item $selectedItem
                continue
            }
            27 {
                return $null
            }
            default {
                continue
            }
        }
    }
}
function Read-BooleanChoice {
    param(
        [string]$Prompt,
        [bool]$Default
    )

    $defaultLabel = if ($Default) { 'Y' } else { 'N' }
    while ($true) {
        $answer = Read-Host "  $Prompt (Y/N) [default: $defaultLabel]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }
        if ($answer -match '^[Yy]$') { return $true }
        if ($answer -match '^[Nn]$') { return $false }
    }
}

function Read-UpdateProfileChoice {
    param([string]$Default)

    Write-Host '  WINDOWS UPDATE PROFILE:' -ForegroundColor White
    Write-Host '    [1] Maximum  - All updates (security, quality, drivers, feature updates)' -ForegroundColor Green
    Write-Host '    [2] Security - Security/quality updates only, no feature updates or drivers' -ForegroundColor Yellow
    Write-Host '    [3] Disable  - Completely disable Windows Update' -ForegroundColor Red
    Write-Host ''

    while ($true) {
        $answer = Read-Host "  Update profile choice (1/2/3) [default: $Default]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }
        if ($answer -in @('1', '2', '3')) {
            return $answer
        }
    }
}

function Show-LaunchOptionsFallback {
    param(
        [hashtable]$Options,
        [bool]$HasNvidiaGpu,
        [bool]$HasMsiSnapshot,
        [string]$OptionsFile
    )

    Clear-Host
    Write-Host ''
    Write-Host "  win_desloperf $PACK_VERSION" -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  CONFIGURATION BEFORE LAUNCH' -ForegroundColor Magenta
    Write-Host '  Raw console key input is not available here, falling back to sequential prompts.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "  Saved defaults: $OptionsFile" -ForegroundColor DarkGray
    Write-Host ''

    $Options['defenderStep'] = Read-BooleanChoice -Prompt 'Run Defender Safe Mode step at the end?' -Default ([bool]$Options['defenderStep'])
    $Options['updateProfile'] = Read-UpdateProfileChoice -Default $Options['updateProfile']
    $Options['uninstallEdge'] = Read-BooleanChoice -Prompt 'Uninstall Microsoft Edge + WebView2?' -Default ([bool]$Options['uninstallEdge'])
    $Options['uninstallOneDrive'] = Read-BooleanChoice -Prompt 'Uninstall OneDrive?' -Default ([bool]$Options['uninstallOneDrive'])
    $Options['disableFirewall'] = Read-BooleanChoice -Prompt 'Disable Windows Firewall profiles?' -Default ([bool]$Options['disableFirewall'])
    $Options['configureDns'] = Read-BooleanChoice -Prompt 'Apply Cloudflare DNS?' -Default ([bool]$Options['configureDns'])
    $Options['enableTimerTool'] = Read-BooleanChoice -Prompt 'Enable SetTimerResolution at startup?' -Default ([bool]$Options['enableTimerTool'])
    $Options['applyPersonalSettings'] = Read-BooleanChoice -Prompt 'Apply personal shell settings?' -Default ([bool]$Options['applyPersonalSettings'])

    if ($HasNvidiaGpu) {
        $Options['installNvInspector'] = Read-BooleanChoice -Prompt 'Install NVIDIA Profile Inspector?' -Default ([bool]$Options['installNvInspector'])
    } else {
        $Options['installNvInspector'] = $false
    }

    $Options['setInterruptAffinity'] = Read-BooleanChoice -Prompt 'Pin GPU interrupt affinity to core 2?' -Default ([bool]$Options['setInterruptAffinity'])

    if ($HasMsiSnapshot) {
        $Options['applySavedMsi'] = Read-BooleanChoice -Prompt 'Apply saved MSI snapshot?' -Default ([bool]$Options['applySavedMsi'])
    } else {
        $Options['applySavedMsi'] = $false
    }

    if (-not (Read-BooleanChoice -Prompt 'Launch with these choices now?' -Default $true)) {
        return $null
    }

    return $Options
}

function Write-SelectedOptionsLog {
    param(
        [hashtable]$Options,
        [bool]$HasNvidiaGpu,
        [bool]$HasMsiSnapshot
    )

    Write-Log "Option selected: Defender Safe Mode step = $([bool]$Options['defenderStep'])" 'INFO'
    Write-Log "Option selected: Windows Update profile = $(Get-UpdateProfileLabel -Profile $Options['updateProfile'])" 'INFO'
    Write-Log "Option selected: Edge + WebView2 uninstall = $([bool]$Options['uninstallEdge'])" 'INFO'
    Write-Log "Option selected: OneDrive uninstall = $([bool]$Options['uninstallOneDrive'])" 'INFO'
    Write-Log "Option selected: Firewall disable = $([bool]$Options['disableFirewall'])" 'INFO'
    Write-Log "Option selected: Cloudflare DNS = $([bool]$Options['configureDns'])" 'INFO'
    Write-Log "Option selected: SetTimerResolution startup = $([bool]$Options['enableTimerTool'])" 'INFO'
    Write-Log "Option selected: Personal settings = $([bool]$Options['applyPersonalSettings'])" 'INFO'
    if ($HasNvidiaGpu) {
        Write-Log "Option selected: NVInspector install = $([bool]$Options['installNvInspector'])" 'INFO'
    } else {
        Write-Log 'Option auto-skipped: NVInspector install (no NVIDIA GPU detected)' 'INFO'
    }
    Write-Log "Option selected: Interrupt affinity = $([bool]$Options['setInterruptAffinity'])" 'INFO'
    if ($HasMsiSnapshot) {
        Write-Log "Option selected: Apply saved MSI snapshot = $([bool]$Options['applySavedMsi'])" 'INFO'
    } else {
        Write-Log 'Option auto-skipped: MSI snapshot apply (no saved snapshot found)' 'INFO'
    }
}

Write-Host ''
Write-Host "  win_desloperf $PACK_VERSION" -ForegroundColor Cyan
Write-Host ''
Write-Host '  by stubfy' -ForegroundColor DarkGray
Write-Host ''

Write-Log '============================================================'
Write-Log "win_desloperf $PACK_VERSION" 'INFO'
Write-Log "Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
Write-Log "OS     : $([System.Environment]::OSVersion.VersionString)" 'INFO'
Write-Log "Machine: $env:COMPUTERNAME" 'INFO'
Write-Log "User   : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" 'INFO'
Write-Log "Log    : $LOG_FILE" 'INFO'
Write-Log '============================================================'
Write-Host "  Log: $LOG_FILE" -ForegroundColor DarkGray
Write-Host ''

$nvInspectorBaseDir  = Join-Path $env:APPDATA 'win_desloperf'
$nvInspectorExe      = Join-Path $nvInspectorBaseDir 'NVInspector\NVPI-R.exe'
$nvInspectorShortcut = Join-Path ([System.Environment]::GetFolderPath('Desktop')) 'NVIDIA Profile Inspector.lnk'
$preferredGpu        = Get-PreferredDisplayGpu
$hasNvidiaGpu        = $null -ne $preferredGpu -and $preferredGpu.FriendlyName -match 'NVIDIA'
$msiStateFile        = Resolve-MsiStateFile -CanonicalPath $MSI_STATE_FILE -LegacyPath $LEGACY_MSI_STATE_FILE
$hasMsiSnapshot      = Test-Path $msiStateFile

$defaultOptions = Get-RunAllDefaultOptions -HasNvidiaGpu $hasNvidiaGpu -HasMsiSnapshot $hasMsiSnapshot
$launchOptions  = Load-RunAllOptions -Path $RUN_ALL_OPTIONS_FILE -Defaults $defaultOptions -HasNvidiaGpu $hasNvidiaGpu -HasMsiSnapshot $hasMsiSnapshot

try {
    $launchOptions = Show-LaunchOptionsMenu -Options $launchOptions -HasNvidiaGpu $hasNvidiaGpu -HasMsiSnapshot $hasMsiSnapshot -OptionsFile $RUN_ALL_OPTIONS_FILE -MsiStateFile $msiStateFile
} catch {
    Write-Host '  WARN: Interactive arrow menu unavailable, switching to sequential prompts.' -ForegroundColor Yellow
    Write-Log "Arrow-based launch menu unavailable: $($_.Exception.Message)" 'WARN'
    $launchOptions = Show-LaunchOptionsFallback -Options $launchOptions -HasNvidiaGpu $hasNvidiaGpu -HasMsiSnapshot $hasMsiSnapshot -OptionsFile $RUN_ALL_OPTIONS_FILE
}

if ($null -eq $launchOptions) {
    Write-Host ''
    Write-Host '  Cancelled before launch.' -ForegroundColor Yellow
    Write-Log 'Run cancelled at launch configuration screen.' 'INFO'
    return
}

if (-not $hasNvidiaGpu) {
    $launchOptions['installNvInspector'] = $false
}
if (-not $hasMsiSnapshot) {
    $launchOptions['applySavedMsi'] = $false
}

Save-RunAllOptions -Path $RUN_ALL_OPTIONS_FILE -Options $launchOptions
Write-SelectedOptionsLog -Options $launchOptions -HasNvidiaGpu $hasNvidiaGpu -HasMsiSnapshot $hasMsiSnapshot

$defenderStep          = [bool]$launchOptions['defenderStep']
$updateProfil          = [string]$launchOptions['updateProfile']
$profilLabel           = Get-UpdateProfileLabel -Profile $updateProfil
$uninstallEdge         = [bool]$launchOptions['uninstallEdge']
$uninstallOneDrive     = [bool]$launchOptions['uninstallOneDrive']
$disableFirewall       = [bool]$launchOptions['disableFirewall']
$configureDns          = [bool]$launchOptions['configureDns']
$enableTimerTool       = [bool]$launchOptions['enableTimerTool']
$applyPersonalSettings = [bool]$launchOptions['applyPersonalSettings']
$installNvInspector    = [bool]$launchOptions['installNvInspector']
$setInterruptAffinity  = [bool]$launchOptions['setInterruptAffinity']
$applySavedMsi         = [bool]$launchOptions['applySavedMsi']
Clear-Host
Write-Host ''
Write-Host "  win_desloperf $PACK_VERSION" -ForegroundColor Cyan
Write-Host ''
Write-Host '  Launch configuration locked. Starting automated phases...' -ForegroundColor Yellow
Write-Host "  Windows Update profile : $profilLabel" -ForegroundColor DarkGray
Write-Host "  Defender Safe Mode     : $(if ($defenderStep) { 'enabled' } else { 'disabled' })" -ForegroundColor DarkGray
if ($hasMsiSnapshot) {
    Write-Host "  Apply MSI snapshot     : $(if ($applySavedMsi) { 'yes' } else { 'no' })" -ForegroundColor DarkGray
}
Write-Host ''

Write-Step 'PHASE A.0 - Snapshot current state (for diff report at end)'
& "$SCRIPTS\snapshot.ps1"

Write-Step 'PHASE A.1 - Backup (restore point + service/registry state)'
Invoke-Script "$SCRIPTS\backup.ps1"

Write-Step 'PHASE B.1 - Registry tweaks + visual effects + MarkC mouse fix'
Invoke-Script "$SCRIPTS\registry.ps1"

Write-Step 'PHASE B.2 - Apply service startup tweaks'
Invoke-Script "$SCRIPTS\services.ps1"

Write-Step 'PHASE B.3 - System performance (power plan, BCD, USB suspend)'
Invoke-Script "$SCRIPTS\performance.ps1"

if ($configureDns) {
    Write-Step 'PHASE B.4 - Cloudflare DNS (1.1.1.1 / 1.0.0.1)'
    Invoke-Script "$SCRIPTS\set_dns.ps1"
} else {
    Write-Step 'PHASE B.4 - Cloudflare DNS (skipped)'
    Write-Host '    Skipped        : user chose not to override the current DNS configuration'
    Write-Log 'Skipped: set_dns.ps1 (user chose not to apply Cloudflare DNS)' 'INFO'
}

Write-Step 'PHASE B.5 - Remove bloatware UWP apps'
Invoke-Script "$SCRIPTS\debloat.ps1"

Write-Step 'PHASE B.6 - Privacy & AI (OOSU10, telemetry, AI/Copilot, privacy registry)'
Invoke-Script "$SCRIPTS\privacy.ps1"

if ($enableTimerTool) {
    Write-Step 'PHASE B.7 - SetTimerResolution at startup'
    Invoke-Script "$SCRIPTS\timer.ps1"
} else {
    Write-Step 'PHASE B.7 - SetTimerResolution at startup (skipped)'
    Write-Host '    Skipped        : user chose not to install the timer tool'
    Write-Host '                     Process Lasso users can use its built-in timer resolution tool instead'
    Write-Log 'Skipped: timer.ps1 (user chose not to enable SetTimerResolution startup)' 'INFO'
}

Write-Step 'PHASE B.8 - Additional network tweaks (Teredo, TCP, Nagle, QoS)'
Invoke-Script "$SCRIPTS\network_tweaks.ps1"

Write-Step "PHASE B.9 - Windows Update profile: $profilLabel"
Invoke-Script "$SCRIPTS\set_windows_update.ps1" @{ Profil = $updateProfil }

if ($disableFirewall) {
    Write-Step 'PHASE B.10 - Disable Windows Firewall profiles'
    Invoke-Script "$SCRIPTS\firewall.ps1"
} else {
    Write-Step 'PHASE B.10 - Disable Windows Firewall profiles (skipped)'
    Write-Host '    Skipped        : user chose to keep the current firewall configuration'
    Write-Log 'Skipped: firewall.ps1 (user chose not to disable firewall profiles)' 'INFO'
}

if ($applyPersonalSettings) {
    Write-Step 'PHASE B.11 - Personal shell settings (theme, colors, taskbar, Settings app)'
    Invoke-Script "$SCRIPTS\personal_settings.ps1"
} else {
    Write-Step 'PHASE B.11 - Personal shell settings (skipped)'
    Write-Host "    Skipped        : user chose not to apply the pack's subjective shell/theme preferences"
    Write-Log 'Skipped: personal_settings.ps1 (user chose not to apply personal settings)' 'INFO'
}

if ($setInterruptAffinity) {
    Write-Step 'PHASE B.12 - GPU interrupt affinity (pin to core 2)'
    Invoke-Script "$SCRIPTS\set_affinity.ps1" @{ SkipReboot = $true }
} else {
    Write-Step 'PHASE B.12 - GPU interrupt affinity (skipped)'
    Write-Host '    Skipped        : run 6 - Interrupt Affinity\set_affinity.bat after NVIDIA updates'
    Write-Log 'Skipped: set_affinity.ps1 (user opted out)' 'INFO'
}

$msiStateApplied = $false
if (Test-Path $msiStateFile) {
    if ($applySavedMsi) {
        Write-Step 'PHASE B.13 - MSI interrupt mode (from saved snapshot)'
        $msiMeta = (Get-Content $msiStateFile -Encoding UTF8 | ConvertFrom-Json)._meta
        Write-Host "    Snapshot found: $msiStateFile" -ForegroundColor Cyan
        Write-Host "    Created: $($msiMeta.created) on $($msiMeta.machine)" -ForegroundColor DarkGray

        $restoreScript = "$SCRIPTS\msi_restore.ps1"
        Invoke-Script $restoreScript @{ StateFile = $msiStateFile; DataDir = $MSI_UTILS_DIR; SkipConfirm = $true }
        Write-Log "MSI state restored from snapshot: $msiStateFile" 'OK'
        $msiStateApplied = $true
    } else {
        Write-Step 'PHASE B.13 - MSI interrupt mode (skipped)'
        Write-Host "    Snapshot found but skipped by launch choice: $msiStateFile" -ForegroundColor Yellow
        Write-Host '    Run 3 - MSI Utils\msi_restore.bat manually if you want to replay it later.' -ForegroundColor DarkGray
        Write-Log 'Skipped: MSI restore (launch choice disabled saved MSI replay)' 'INFO'
    }
} else {
    Write-Step 'PHASE B.13 - MSI interrupt mode (no snapshot found)'
    Write-Host '    No saved msi_state.json found in 1 - Automated\backup/.' -ForegroundColor DarkGray
    Write-Host '    Configure MSI manually via MSI_util_v3.exe, then run msi_snapshot.bat to save' -ForegroundColor DarkGray
    Write-Host '    your settings -- next time run_all.bat runs, it can apply them automatically.' -ForegroundColor DarkGray
    Write-Log 'Skipped: MSI restore (no saved msi_state.json found)' 'INFO'
}

if ($installNvInspector) {
    Write-Step 'PHASE B.14 - NVIDIA Profile Inspector install'
    Invoke-Script "$SCRIPTS\install_nvinspector.ps1" @{ SourceRoot = $NVINSPECTOR_DIR }
}

if ($uninstallOneDrive) {
    Write-Step 'OPTION - OneDrive uninstall (Win32)'
    Invoke-Script "$SCRIPTS\opt_onedrive_uninstall.ps1"
}

if ($uninstallEdge) {
    Write-Step 'OPTION - Microsoft Edge + WebView2 Runtime uninstall'
    Invoke-Script "$SCRIPTS\opt_edge_uninstall.ps1"
}

Write-Step 'PHASE C - Recap (what actually changed vs before)'
Invoke-Script "$SCRIPTS\show_diff.ps1"
Write-Host ''
Write-Host '================================================' -ForegroundColor Green
Write-Host '   AUTOMATED TWEAKS COMPLETE                    ' -ForegroundColor Green
Write-Host '================================================' -ForegroundColor Green
Write-Host ''
Write-Host 'REMAINING MANUAL STEPS (see README.md at the pack root):' -ForegroundColor Cyan

if ($defenderStep) {
    Write-Host '  1. Confirm the Safe Mode reboot prompt below for the Defender step'
    Write-Host '  2. In Safe Mode, run 2 - Windows Defender\run_defender.bat again' -ForegroundColor Yellow
} else {
    Write-Host '  1. Reboot the PC'
    Write-Host '  2. [Optional / Safe Mode] Disable Windows Defender   (2 - Windows Defender/run_defender.bat)' -ForegroundColor DarkGray
}

if ($msiStateApplied) {
    Write-Host '  3. MSI Utils - snapshot applied automatically. Verify devices, reboot if needed.' -ForegroundColor Green
} elseif (Test-Path $msiStateFile) {
    Write-Host '  3. MSI Utils - saved snapshot available but not applied. Run msi_restore.bat if needed.' -ForegroundColor Yellow
} else {
    Write-Host '  3. MSI Utils - enable MSI on GPU/NIC/NVMe   (3 - MSI Utils/)' -ForegroundColor Yellow
    Write-Host '     -> After configuring, run msi_snapshot.bat to save settings for next time.' -ForegroundColor DarkGray
}

if ($installNvInspector -and (Test-Path $nvInspectorExe) -and (Test-Path $nvInspectorShortcut)) {
    Write-Host '  4. NVIDIA Profile Inspector - installed, Desktop shortcut created' -ForegroundColor Green
} elseif ($hasNvidiaGpu) {
    Write-Host '  4. NVIDIA Profile Inspector - run install_nvinspector.bat (4 - NVInspector/)' -ForegroundColor Yellow
} else {
    Write-Host '  4. NVIDIA Profile Inspector - skipped (no NVIDIA GPU detected)' -ForegroundColor DarkGray
}

Write-Host '  5. Device Manager - disable USB power saving (5 - Device Manager/)'
Write-Host '  6. Interrupt Affinity - re-run set_affinity.bat after each NVIDIA driver update'
Write-Host '  7. Quick reruns if needed: DNS / Windows Update / Firewall (7 - DNS/, 8 - Windows Update/, 1 - Automated/scripts/firewall.bat)'
Write-Host '  8. NIC settings - disable offloads, buffers in Device Manager'
Write-Host '  9. Optional timer check: verify with MeasureSleep.exe as admin (Tools/)'
Write-Host ''
Write-Host 'To undo all tweaks: .\restore_all.ps1' -ForegroundColor Gray
Write-Host ''
Write-Host "Full log: $LOG_FILE" -ForegroundColor DarkGray
Write-Host ''

Write-Log '============================================================'
Write-Log "Execution complete: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
Write-Log '============================================================'

if ($defenderStep) {
    Write-Host '  Defender was selected at launch.' -ForegroundColor Yellow
    Write-Host '  Rebooting into Safe Mode will happen only if you confirm it now.' -ForegroundColor DarkGray
    Write-Host ''
    $restart = Read-Host 'Reboot into Safe Mode now for the Defender step? (Y/N) [default: Y]'
    if ([string]::IsNullOrWhiteSpace($restart)) { $restart = 'Y' }

    if ($restart -ieq 'Y') {
        Write-Log 'Safe Mode reboot confirmed by user for Defender step.' 'INFO'

        $defenderLauncher = "$SCRIPTS\run_defender.ps1"
        if (-not (Test-Path $defenderLauncher)) {
            Write-Host ''
            Write-Host '  ERROR: Defender launcher not found.' -ForegroundColor Red
            Write-Host "    Expected: $defenderLauncher" -ForegroundColor White
            Write-Host '  Safe Mode was not enabled.' -ForegroundColor Yellow
            Write-Log "Safe Mode helper creation failed: missing launcher at $defenderLauncher" 'ERROR'
            return
        }

        try {
            Unblock-LaunchFile -Path $defenderLauncher
            & $defenderLauncher -CalledFromRunAll -LogFile $LOG_FILE
            Write-Host ''
            Write-Host '  Safe Mode configured. Rebooting now...' -ForegroundColor Yellow
            Write-Log 'Safe Mode configured; rebooting now from run_all.' 'INFO'
            Restart-Computer -Force
        } catch {
            Write-Host ''
            Write-Host '  Defender Safe Mode launcher failed.' -ForegroundColor Red
            Write-Host "    $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Log ("Defender Safe Mode launcher failed: {0}" -f $_.Exception.Message) 'ERROR'
        }
    } else {
        Write-Host ''
        Write-Host '  Safe Mode reboot skipped. Run 2 - Windows Defender\run_defender.bat later if needed.' -ForegroundColor Yellow
        Write-Log 'Safe Mode reboot skipped by user after automated run.' 'INFO'
    }
} else {
    Write-Host '  Defender step was not selected at launch.' -ForegroundColor DarkGray
    Write-Host ''
    $restart = Read-Host 'Reboot now? (Y/N) [default: N]'
    if ([string]::IsNullOrWhiteSpace($restart)) { $restart = 'N' }

    if ($restart -ieq 'Y') {
        Write-Log 'Normal reboot confirmed by user.' 'INFO'
        Restart-Computer -Force
    } else {
        Write-Log 'Normal reboot skipped by user.' 'INFO'
    }
}





