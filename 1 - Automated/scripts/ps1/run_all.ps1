#Requires -RunAsAdministrator
<#
.SYNOPSIS
    win_deslopper - Main launcher
    Windows 11 25H2 - Gaming optimization / Debloat / QoL

.DESCRIPTION
    Runs all automatable tweaks in the recommended order.
    Creates a backup before any modification.
    To undo: .\restore_all.ps1

    Execution order:
      Phase A - Snapshot + Backup (00_snapshot, 01_backup)
      Phase B - Tweaks in dependency order:
        02 registry       -> consolidated reg file (performance, privacy, QoL)
        03 services       -> startup type alignment
        04 bcdedit        -> timer tick + boot menu
        05 power              -> Ultimate Performance plan
        [7 - DNS]             -> Cloudflare DNS (user choice)
        06 debloat            -> UWP app removal
        07 oosu10             -> O&O ShutUp10++ privacy config
        08 timer              -> Optional SetTimerResolution startup
        09 usb                -> USB selective suspend
        10 ai_disable         -> Recall/Copilot/AI policies
        11 telemetry          -> Scheduled tasks + PS7 + Brave
        12 network            -> Teredo disable
        [8 - Windows Update]  -> WU profile (user choice)
        [9 - Firewall]        -> Firewall disable (user choice)
        13 uwt                -> UWT equivalent tweaks + SPI visual effects
        14 personal           -> Subjective shell/theme preferences (user choice)
        15 mouse_accel        -> MarkC mouse fix (DPI-aware)
        [6 - Interrupt Affinity] -> GPU IRQ pin to core 2 (user choice)
      Options - Edge uninstall, OneDrive uninstall (user choice)
      Phase C - Diff report (99_show_diff)

    Logging: all output is written to %APPDATA%\win_deslopper\logs\win_deslopper.log
    Format: [HH:mm:ss] [LEVEL] message
    Levels: INFO, STEP, RUN, OUT, OK, WARN, ERROR

    Safe Mode reboot path:
      If the user chooses [S] at the reboot prompt, the script:
        a. Sets safeboot=minimal in BCD.
        b. Creates a helper .bat on the Desktop that disables Defender and
           removes the safeboot flag before rebooting to normal Windows.
      This automates the manual Safe Mode Defender step (2 - Windows Defender/run_defender.bat).

.NOTES
    Manual steps after execution: see README.md at the pack root
#>

$ErrorActionPreference = 'Continue'
$ROOT         = Split-Path (Split-Path (Split-Path $MyInvocation.MyCommand.Path))
$PACK_ROOT    = Split-Path $ROOT -Parent
$SCRIPTS      = $PSScriptRoot
$DEFENDER_DIR    = Join-Path $PACK_ROOT "2 - Windows Defender"
$MSI_UTILS_DIR   = Join-Path $PACK_ROOT "3 - MSI Utils"
$NVINSPECTOR_DIR = Join-Path $PACK_ROOT "4 - NVInspector"
$AFFINITY_DIR    = Join-Path $PACK_ROOT "6 - Interrupt Affinity"
$DNS_DIR         = Join-Path $PACK_ROOT "7 - DNS"
$WU_DIR          = Join-Path $PACK_ROOT "8 - Windows Update"
$FIREWALL_DIR    = Join-Path $PACK_ROOT "9 - Firewall"
$PACK_VERSION = 'v0.9'
$LOG_DIR      = Join-Path $env:APPDATA 'win_deslopper\logs'
$LOG_FILE     = Join-Path $LOG_DIR "win_deslopper.log"

if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Msg
    Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
}

function Write-Step {
    param([string]$Msg)
    Write-Host ""
    Write-Host ">>> $Msg" -ForegroundColor Yellow
    Write-Log $Msg 'STEP'
}

function Invoke-Script {
    param([string]$Path, [hashtable]$Params = @{})
    $name = Split-Path $Path -Leaf
    Write-Host "    $name ... " -NoNewline
    Write-Log "Start: $name" 'RUN'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Path @Params *>&1 | ForEach-Object {
            $line = $_
            if ($line -is [System.Management.Automation.ErrorRecord]) {
                Write-Log "  [ERR] $($line.Exception.Message)" 'WARN'
                Write-Host ""
                Write-Host "      [ERR] $($line.Exception.Message)" -ForegroundColor Yellow
            } else {
                Write-Log "  $line" 'OUT'
                if ($null -ne $line -and "$line".Trim().Length -gt 0) {
                    Write-Host ""
                    Write-Host "      $line" -ForegroundColor DarkGray
                }
            }
        }
        $sw.Stop()
        Write-Host "[OK]" -ForegroundColor Green
        Write-Log "End: $name -> OK ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" 'OK'
    } catch {
        $sw.Stop()
        Write-Host "[ERROR] $_" -ForegroundColor Red
        Write-Log "End: $name -> ERROR after $([math]::Round($sw.Elapsed.TotalSeconds, 1))s: $_" 'ERROR'
        Write-Log "  StackTrace: $($_.ScriptStackTrace)" 'ERROR'
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

# ── Header ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  win_deslopper v0.9" -ForegroundColor Cyan
Write-Host ""
Write-Host "  by stubfy" -ForegroundColor DarkGray
Write-Host ""

# ── Log init ───────────────────────────────────────────────────────────────────
Write-Log "============================================================"
Write-Log "win_deslopper $PACK_VERSION" 'INFO'
Write-Log "Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
Write-Log "OS     : $([System.Environment]::OSVersion.VersionString)" 'INFO'
Write-Log "Machine: $env:COMPUTERNAME" 'INFO'
Write-Log "User   : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" 'INFO'
Write-Log "Log    : $LOG_FILE" 'INFO'
Write-Log "============================================================"
Write-Host "  Log: $LOG_FILE" -ForegroundColor DarkGray
Write-Host ""

# ── OPTIONAL OPTIONS (prompt before any modification) ─────────────────────────
Write-Host "OPTIONS BEFORE LAUNCH:" -ForegroundColor Magenta
Write-Host "(These operations are irreversible without manual reinstallation)" -ForegroundColor DarkGray
Write-Host ""

$uninstallEdge     = $true
$uninstallOneDrive = $true
$disableFirewall   = $true
$enableTimerTool   = $true
$configureDns      = $true
$applyPersonalSettings = $true
$installNvInspector = $false
$updateProfil      = '2'   # default: security only
$nvInspectorBaseDir = Join-Path $env:APPDATA 'win_deslopper'
$nvInspectorExe    = Join-Path $nvInspectorBaseDir 'NVInspector\NVPI-R.exe'
$nvInspectorShortcut = Join-Path ([System.Environment]::GetFolderPath('Desktop')) 'NVIDIA Profile Inspector.lnk'
$preferredGpu = Get-PreferredDisplayGpu
$hasNvidiaGpu = $null -ne $preferredGpu -and $preferredGpu.FriendlyName -match 'NVIDIA'

Write-Host "  WINDOWS UPDATE PROFILE:" -ForegroundColor White
Write-Host "    [1] Maximum  - All updates (security, quality, drivers, feature updates)" -ForegroundColor Green
Write-Host "    [2] Security - Security/quality updates only, no feature updates or drivers" -ForegroundColor Yellow
Write-Host "    [3] Disable  - Completely disable Windows Update" -ForegroundColor Red
Write-Host ""
do {
    $ans = Read-Host "  Update profile choice (1/2/3) [default: 2]"
    if ($ans -eq '') { $ans = '2' }
} while ($ans -notin @('1','2','3'))
$updateProfil = $ans
$profilLabel = @{'1'='Maximum'; '2'='Security only'; '3'='Disabled'}[$updateProfil]
Write-Host "  -> Update profile: $profilLabel" -ForegroundColor Yellow
Write-Log "Option selected: Windows Update profile = $profilLabel" 'INFO'
Write-Host ""

$ans = Read-Host "  Uninstall Microsoft Edge + WebView2 Runtime (best-effort)? (Y/N) [default: Y]"
if ($ans -ieq 'N') {
    $uninstallEdge = $false
    Write-Log "Option selected: Edge + WebView2 uninstall = NO" 'INFO'
} else {
    $uninstallEdge = $true
    Write-Host "  -> The pack will uninstall Edge and try to remove WebView2 after the main tweaks." -ForegroundColor Yellow
    Write-Host "     Windows 11 or apps that depend on WebView2 can reinstall the runtime later." -ForegroundColor DarkGray
    Write-Log "Option selected: Edge + WebView2 uninstall = YES" 'INFO'
}

$ans = Read-Host "  Completely uninstall OneDrive? (Y/N) [default: Y]"
if ($ans -ieq 'N') {
    $uninstallOneDrive = $false
    Write-Log "Option selected: OneDrive uninstall = NO" 'INFO'
} else {
    $uninstallOneDrive = $true
    Write-Host "  -> OneDrive will be uninstalled after the main tweaks." -ForegroundColor Yellow
    Write-Log "Option selected: OneDrive uninstall = YES" 'INFO'
}

$ans = Read-Host "  Disable Windows Firewall profiles? (Y/N) [default: Y]"
if ($ans -ieq 'N') {
    $disableFirewall = $false
    Write-Log "Option selected: Firewall disable = NO" 'INFO'
} else {
    $disableFirewall = $true
    Write-Host "  -> Windows Firewall profiles will be disabled." -ForegroundColor Yellow
    Write-Log "Option selected: Firewall disable = YES" 'INFO'
}

Write-Host "     Skip this if you want to keep DHCP/router DNS or another manual DNS setup." -ForegroundColor DarkGray
$ans = Read-Host "  Apply Cloudflare DNS (1.1.1.1 / 1.0.0.1)? (Y/N) [default: Y]"
if ($ans -ieq 'N') {
    $configureDns = $false
    Write-Log "Option selected: Cloudflare DNS = NO" 'INFO'
} else {
    $configureDns = $true
    Write-Host "  -> Active network adapters will be configured to use Cloudflare DNS." -ForegroundColor Yellow
    Write-Log "Option selected: Cloudflare DNS = YES" 'INFO'
}

Write-Host "     Skip this if Process Lasso already manages the system timer resolution." -ForegroundColor DarkGray
$ans = Read-Host "  Enable SetTimerResolution at startup (~0.52 ms)? (Y/N) [default: Y]"
if ($ans -ieq 'N') {
    $enableTimerTool = $false
    Write-Log "Option selected: SetTimerResolution startup = NO" 'INFO'
} else {
    $enableTimerTool = $true
    Write-Host "  -> SetTimerResolution will be installed to user startup." -ForegroundColor Yellow
    Write-Log "Option selected: SetTimerResolution startup = YES" 'INFO'
}

Write-Host "     Skip this if you do not want the subjective theme/taskbar/Explorer preferences from this pack." -ForegroundColor DarkGray
$ans = Read-Host "  Apply personal shell settings (theme, colors, taskbar)? (Y/N) [default: Y]"
if ($ans -ieq 'N') {
    $applyPersonalSettings = $false
    Write-Log "Option selected: Personal settings = NO" 'INFO'
} else {
    $applyPersonalSettings = $true
    Write-Host "  -> Personal shell/theme preferences will be applied near the end of the run." -ForegroundColor Yellow
    Write-Log "Option selected: Personal settings = YES" 'INFO'
}

if ($hasNvidiaGpu) {
    Write-Host "  NVIDIA GPU detected: $($preferredGpu.FriendlyName)" -ForegroundColor Green
    $ans = Read-Host "  Install NVIDIA Profile Inspector to $nvInspectorBaseDir and create a Desktop shortcut? (Y/N) [default: Y]"
    if ($ans -ieq 'N') {
        Write-Host "  -> Skipping. Run 4 - NVInspector\install_nvinspector.bat manually." -ForegroundColor Yellow
        Write-Log "Option selected: NVInspector install = NO" 'INFO'
    } else {
        $installNvInspector = $true
        Write-Host "  -> NVIDIA Profile Inspector will be copied to $nvInspectorBaseDir\NVInspector." -ForegroundColor Yellow
        Write-Host "     A Desktop shortcut to NVPI-R.exe will be created." -ForegroundColor DarkGray
        Write-Log "Option selected: NVInspector install = YES" 'INFO'
    }
} elseif ($preferredGpu) {
    Write-Host "  -> Skipping NVIDIA Profile Inspector: detected GPU is $($preferredGpu.FriendlyName)." -ForegroundColor DarkGray
    Write-Log "Option auto-skipped: NVInspector install (GPU not NVIDIA: $($preferredGpu.FriendlyName))" 'INFO'
} else {
    Write-Host "  -> Skipping NVIDIA Profile Inspector: no compatible PCI display device detected." -ForegroundColor DarkGray
    Write-Log "Option auto-skipped: NVInspector install (no compatible display GPU detected)" 'INFO'
}

$setInterruptAffinity = $true
Write-Host "     Re-run set_affinity.bat after each NVIDIA driver update." -ForegroundColor DarkGray
$ans = Read-Host "  Pin GPU interrupt affinity to core 2? (Y/N) [default: Y]"
if ($ans -ieq 'N') {
    $setInterruptAffinity = $false
    Write-Host "  -> Skipping. Run 6 - Interrupt Affinity\set_affinity.bat manually." -ForegroundColor Yellow
    Write-Log "Option selected: Interrupt affinity = NO" 'INFO'
} else {
    Write-Host "  -> GPU interrupt chain will be pinned to core 2." -ForegroundColor Yellow
    Write-Log "Option selected: Interrupt affinity = YES" 'INFO'
}

Write-Host ""

# ── PHASE A: Snapshot + Backup ────────────────────────────────────────────────
Write-Step "PHASE A.0 - Snapshot current state (for diff report at end)"
& "$SCRIPTS\00_snapshot.ps1"

Write-Step "PHASE A.1 - Backup (restore point + service/registry state)"
Invoke-Script "$SCRIPTS\01_backup.ps1"

# ── PHASE B: Automated tweaks ──────────────────────────────────────────────────
Write-Step "PHASE B.1 - Registry tweaks (consolidated, deduplicated)"
Invoke-Script "$SCRIPTS\02_registry.ps1"

Write-Step "PHASE B.2 - Apply service startup tweaks"
Invoke-Script "$SCRIPTS\03_services.ps1"

Write-Step "PHASE B.3 - Boot configuration (bcdedit)"
Invoke-Script "$SCRIPTS\04_bcdedit.ps1"

Write-Step "PHASE B.4 - Ultimate Performance power plan"
Invoke-Script "$SCRIPTS\05_power.ps1"

if ($configureDns) {
    Write-Step "PHASE B.5 - Cloudflare DNS (1.1.1.1 / 1.0.0.1)"
    Invoke-Script (Join-Path $DNS_DIR 'ps1\set_dns.ps1')
} else {
    Write-Step "PHASE B.5 - Cloudflare DNS (skipped)"
    Write-Host "    Skipped        : user chose not to override the current DNS configuration"
    Write-Log "Skipped: set_dns.ps1 (user chose not to apply Cloudflare DNS)" 'INFO'
}

Write-Step "PHASE B.6 - Remove bloatware UWP apps"
Invoke-Script "$SCRIPTS\06_debloat.ps1"

Write-Step "PHASE B.7 - O&O ShutUp10++ (silent mode)"
Invoke-Script "$SCRIPTS\07_oosu10.ps1"

if ($enableTimerTool) {
    Write-Step "PHASE B.8 - SetTimerResolution at startup"
    Invoke-Script "$SCRIPTS\08_timer.ps1"
} else {
    Write-Step "PHASE B.8 - SetTimerResolution at startup (skipped)"
    Write-Host "    Skipped        : user chose not to install the timer tool"
    Write-Host "                     Process Lasso users can use its built-in timer resolution tool instead"
    Write-Log "Skipped: 08_timer.ps1 (user chose not to enable SetTimerResolution startup)" 'INFO'
}

Write-Step "PHASE B.9 - USB selective suspend"
Invoke-Script "$SCRIPTS\09_usb.ps1"

Write-Step "PHASE B.10 - Disable AI / Recall / Copilot (25H2)"
Invoke-Script "$SCRIPTS\10_ai_disable.ps1"

Write-Step "PHASE B.11 - Telemetry scheduled tasks + PS7 + Brave"
Invoke-Script "$SCRIPTS\11_telemetry_tasks.ps1"

Write-Step "PHASE B.12 - Additional network tweaks (Teredo)"
Invoke-Script "$SCRIPTS\12_network_tweaks.ps1"

Write-Step "PHASE B.13 - Windows Update profile: $profilLabel"
& (Join-Path $WU_DIR 'ps1\set_windows_update.ps1') -Profil $updateProfil

if ($disableFirewall) {
    Write-Step "PHASE B.14 - Disable Windows Firewall profiles"
    Invoke-Script (Join-Path $FIREWALL_DIR 'ps1\disable_firewall.ps1')
}

Write-Step "PHASE B.15 - UWT equivalent tweaks (privacy, context menu, visual effects)"
Invoke-Script "$SCRIPTS\13_uwt.ps1"

if ($applyPersonalSettings) {
    Write-Step "PHASE B.16 - Personal shell settings (theme, colors, taskbar)"
    Invoke-Script "$SCRIPTS\14_personal_settings.ps1"
} else {
    Write-Step "PHASE B.16 - Personal shell settings (skipped)"
    Write-Host "    Skipped        : user chose not to apply the pack's subjective shell/theme preferences"
    Write-Log "Skipped: 14_personal_settings.ps1 (user chose not to apply personal settings)" 'INFO'
}

Write-Step "PHASE B.17 - MarkC mouse acceleration fix (1:1 scaling)"
Invoke-Script "$SCRIPTS\15_mouse_accel.ps1"

if ($setInterruptAffinity) {
    Write-Step "PHASE B.18 - GPU interrupt affinity (pin to core 2)"
    Invoke-Script (Join-Path $AFFINITY_DIR "ps1\set_affinity.ps1") @{SkipReboot = $true}
} else {
    Write-Step "PHASE B.18 - GPU interrupt affinity (skipped)"
    Write-Host "    Skipped        : run 6 - Interrupt Affinity\set_affinity.bat after NVIDIA updates"
    Write-Log "Skipped: set_affinity.ps1 (user opted out)" 'INFO'
}

# ── PHASE B.19 - MSI interrupt mode ───────────────────────────────────────────
$msiStateFile    = Join-Path $MSI_UTILS_DIR "msi_state.json"
$msiStateApplied = $false
if (Test-Path $msiStateFile) {
    Write-Step "PHASE B.19 - MSI interrupt mode (from saved snapshot)"
    $msiMeta = (Get-Content $msiStateFile -Encoding UTF8 | ConvertFrom-Json)._meta
    Write-Host "    Snapshot found: $msiStateFile" -ForegroundColor Cyan
    Write-Host "    Created: $($msiMeta.created) on $($msiMeta.machine)" -ForegroundColor DarkGray

    $ans = Read-Host "  Apply saved MSI configuration? (Y/N) [default: Y]"
    if ($ans -eq '' -or $ans -ieq 'Y') {
        $restoreScript = Join-Path $MSI_UTILS_DIR "ps1\msi_restore.ps1"
        & $restoreScript -StateFile $msiStateFile -SkipConfirm
        Write-Log "MSI state restored from snapshot" 'OK'
        $msiStateApplied = $true
    } else {
        Write-Host "    Skipped. Run 3 - MSI Utils\msi_restore.bat manually." -ForegroundColor Yellow
        Write-Log "Skipped: MSI restore (user opted out)" 'INFO'
    }
} else {
    Write-Step "PHASE B.19 - MSI interrupt mode (no snapshot found)"
    Write-Host "    No msi_state.json found in 3 - MSI Utils/." -ForegroundColor DarkGray
    Write-Host "    Configure MSI manually via MSI_util_v3.exe, then run msi_snapshot.bat to save" -ForegroundColor DarkGray
    Write-Host "    your settings -- next time run_all.bat runs, it will apply them automatically." -ForegroundColor DarkGray
    Write-Log "Skipped: MSI restore (no msi_state.json found)" 'INFO'
}

if ($installNvInspector) {
    Write-Step "PHASE B.20 - NVIDIA Profile Inspector install"
    Invoke-Script (Join-Path $NVINSPECTOR_DIR 'ps1\install_nvinspector.ps1')
}

# ── OPTIONS: physical uninstalls ──────────────────────────────────────────────
if ($uninstallOneDrive) {
    Write-Step "OPTION - OneDrive uninstall (Win32)"
    Invoke-Script "$SCRIPTS\opt_onedrive_uninstall.ps1"
}

if ($uninstallEdge) {
    Write-Step "OPTION - Microsoft Edge + WebView2 Runtime uninstall"
    Invoke-Script "$SCRIPTS\opt_edge_uninstall.ps1"
}

# ── Diff report ───────────────────────────────────────────────────────────────
Write-Step "PHASE C - Recap (what actually changed vs before)"
& "$SCRIPTS\99_show_diff.ps1"

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "   AUTOMATED TWEAKS COMPLETE                    " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "REMAINING MANUAL STEPS (see README.md at the pack root):" -ForegroundColor Cyan
Write-Host "  1. Reboot the PC"
Write-Host "  2. [Safe Mode] Disable Windows Defender      (2 - Windows Defender/run_defender.bat)"
if ($msiStateApplied) {
    Write-Host "  3. MSI Utils - snapshot applied automatically. Verify devices, reboot if needed." -ForegroundColor Green
} else {
    Write-Host "  3. MSI Utils - enable MSI on GPU/NIC/NVMe   (3 - MSI Utils/)" -ForegroundColor Yellow
    if (-not (Test-Path $msiStateFile)) {
        Write-Host "     -> After configuring, run msi_snapshot.bat to save settings for next time." -ForegroundColor DarkGray
    }
}
if ($installNvInspector -and (Test-Path $nvInspectorExe) -and (Test-Path $nvInspectorShortcut)) {
    Write-Host "  4. NVIDIA Profile Inspector - installed, Desktop shortcut created" -ForegroundColor Green
} elseif ($hasNvidiaGpu) {
    Write-Host "  4. NVIDIA Profile Inspector - run install_nvinspector.bat (4 - NVInspector/)" -ForegroundColor Yellow
} else {
    Write-Host "  4. NVIDIA Profile Inspector - skipped (no NVIDIA GPU detected)" -ForegroundColor DarkGray
}
Write-Host "  5. Device Manager - disable USB power saving (5 - Device Manager/)"
Write-Host "  6. Interrupt Affinity - re-run set_affinity.bat after each NVIDIA driver update"
Write-Host "  7. Standalone reruns if needed: DNS / Windows Update / Firewall (7 - DNS/, 8 - Windows Update/, 9 - Firewall/)"
Write-Host "  8. NIC settings - disable offloads, buffers in Device Manager"
Write-Host "  9. Optional timer check: verify with MeasureSleep.exe as admin (Tools/)"
Write-Host ""
Write-Host "To undo all tweaks: .\restore_all.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "Full log: $LOG_FILE" -ForegroundColor DarkGray
Write-Host ""

Write-Log "============================================================"
Write-Log "Execution complete: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
Write-Log "============================================================"

Write-Host "  [S] Reboot into Safe Mode  <-- RECOMMENDED: do the Defender step right now" -ForegroundColor Yellow
Write-Host "  [Y] Normal reboot" -ForegroundColor White
Write-Host "  [N] No reboot" -ForegroundColor DarkGray
Write-Host ""
$restart = Read-Host "Restart now? (S/Y/N) [default: N]"
if ($restart -eq '') { $restart = 'N' }
if ($restart -ieq 'S') {
    Write-Log "Safe Mode reboot requested by user." 'INFO'

    $defenderLauncher = Join-Path $DEFENDER_DIR 'ps1\run_defender.ps1'
    if (-not (Test-Path $defenderLauncher)) {
        Write-Host ""
        Write-Host "  ERROR: Defender launcher not found." -ForegroundColor Red
        Write-Host "    Expected: $defenderLauncher" -ForegroundColor White
        Write-Host "  Safe Mode was not enabled." -ForegroundColor Yellow
        Write-Log "Safe Mode helper creation failed: missing launcher at $defenderLauncher" 'ERROR'
        return
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $defenderLauncher -CalledFromRunAll -LogFile $LOG_FILE
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  Defender Safe Mode launcher failed." -ForegroundColor Red
        Write-Log "Defender Safe Mode launcher failed with exit code $LASTEXITCODE" 'ERROR'
    }
} elseif ($restart -ieq 'Y') {
    Write-Log "Restart requested by user." 'INFO'
    Restart-Computer -Force
}
