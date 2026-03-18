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
        registry       -> consolidated reg file + visual effects + MarkC mouse fix
        services       -> startup type alignment
        performance    -> Ultimate Performance plan + BCD + USB selective suspend
        [7 - DNS]             -> Cloudflare DNS (user choice)
        debloat            -> UWP app removal
        privacy            -> OOSU10 + AI/Copilot/Recall + telemetry tasks + privacy registry
        timer              -> Optional SetTimerResolution startup
        network_tweaks     -> Teredo disable + TCP/Nagle/QoS
        [8 - Windows Update]  -> WU profile (user choice)
        firewall           -> Firewall disable (user choice)
        personal_settings  -> Subjective shell/theme preferences (user choice)
        [6 - Interrupt Affinity] -> GPU IRQ pin to core 2 (user choice)
      Options - Edge uninstall, OneDrive uninstall (user choice)
      Phase C - Diff report (show_diff)

    Logging: all output is written to %APPDATA%\win_desloperf\logs\win_desloperf.log
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
$MSI_UTILS_DIR   = Join-Path $PACK_ROOT "3 - MSI Utils"
$NVINSPECTOR_DIR = Join-Path $PACK_ROOT "4 - NVInspector"
$LOG_DIR      = Join-Path $env:APPDATA 'win_desloperf\logs'
$LOG_FILE     = Join-Path $LOG_DIR "win_desloperf.log"

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
Write-Host "  win_desloperf $PACK_VERSION" -ForegroundColor Cyan
Write-Host ""
Write-Host "  by stubfy" -ForegroundColor DarkGray
Write-Host ""

# ── Log init ───────────────────────────────────────────────────────────────────
Write-Log "============================================================"
Write-Log "win_desloperf $PACK_VERSION" 'INFO'
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
$nvInspectorBaseDir = Join-Path $env:APPDATA 'win_desloperf'
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

Write-Host "     Skip this if you do not want the subjective theme/taskbar/Explorer/Settings preferences from this pack." -ForegroundColor DarkGray
$ans = Read-Host "  Apply personal shell settings (theme, colors, taskbar, Settings app)? (Y/N) [default: Y]"
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
& "$SCRIPTS\snapshot.ps1"

Write-Step "PHASE A.1 - Backup (restore point + service/registry state)"
Invoke-Script "$SCRIPTS\backup.ps1"

# ── PHASE B: Automated tweaks ──────────────────────────────────────────────────
Write-Step "PHASE B.1 - Registry tweaks + visual effects + MarkC mouse fix"
Invoke-Script "$SCRIPTS\registry.ps1"

Write-Step "PHASE B.2 - Apply service startup tweaks"
Invoke-Script "$SCRIPTS\services.ps1"

Write-Step "PHASE B.3 - System performance (power plan, BCD, USB suspend)"
Invoke-Script "$SCRIPTS\performance.ps1"

if ($configureDns) {
    Write-Step "PHASE B.4 - Cloudflare DNS (1.1.1.1 / 1.0.0.1)"
    Invoke-Script "$SCRIPTS\set_dns.ps1"
} else {
    Write-Step "PHASE B.4 - Cloudflare DNS (skipped)"
    Write-Host "    Skipped        : user chose not to override the current DNS configuration"
    Write-Log "Skipped: set_dns.ps1 (user chose not to apply Cloudflare DNS)" 'INFO'
}

Write-Step "PHASE B.5 - Remove bloatware UWP apps"
Invoke-Script "$SCRIPTS\debloat.ps1"

Write-Step "PHASE B.6 - Privacy & AI (OOSU10, telemetry, AI/Copilot, privacy registry)"
Invoke-Script "$SCRIPTS\privacy.ps1"

if ($enableTimerTool) {
    Write-Step "PHASE B.7 - SetTimerResolution at startup"
    Invoke-Script "$SCRIPTS\timer.ps1"
} else {
    Write-Step "PHASE B.7 - SetTimerResolution at startup (skipped)"
    Write-Host "    Skipped        : user chose not to install the timer tool"
    Write-Host "                     Process Lasso users can use its built-in timer resolution tool instead"
    Write-Log "Skipped: timer.ps1 (user chose not to enable SetTimerResolution startup)" 'INFO'
}

Write-Step "PHASE B.8 - Additional network tweaks (Teredo, TCP, Nagle, QoS)"
Invoke-Script "$SCRIPTS\network_tweaks.ps1"

Write-Step "PHASE B.9 - Windows Update profile: $profilLabel"
Invoke-Script "$SCRIPTS\set_windows_update.ps1" @{Profil = $updateProfil}

if ($disableFirewall) {
    Write-Step "PHASE B.10 - Disable Windows Firewall profiles"
    Invoke-Script "$SCRIPTS\firewall.ps1"
}

if ($applyPersonalSettings) {
    Write-Step "PHASE B.11 - Personal shell settings (theme, colors, taskbar, Settings app)"
    Invoke-Script "$SCRIPTS\personal_settings.ps1"
} else {
    Write-Step "PHASE B.11 - Personal shell settings (skipped)"
    Write-Host "    Skipped        : user chose not to apply the pack's subjective shell/theme preferences"
    Write-Log "Skipped: personal_settings.ps1 (user chose not to apply personal settings)" 'INFO'
}

if ($setInterruptAffinity) {
    Write-Step "PHASE B.12 - GPU interrupt affinity (pin to core 2)"
    Invoke-Script "$SCRIPTS\set_affinity.ps1" @{SkipReboot = $true}
} else {
    Write-Step "PHASE B.12 - GPU interrupt affinity (skipped)"
    Write-Host "    Skipped        : run 6 - Interrupt Affinity\set_affinity.bat after NVIDIA updates"
    Write-Log "Skipped: set_affinity.ps1 (user opted out)" 'INFO'
}

# ── PHASE B.13 - MSI interrupt mode ───────────────────────────────────────────
$msiStateFile    = Join-Path $MSI_UTILS_DIR "msi_state.json"
$msiStateApplied = $false
if (Test-Path $msiStateFile) {
    Write-Step "PHASE B.13 - MSI interrupt mode (from saved snapshot)"
    $msiMeta = (Get-Content $msiStateFile -Encoding UTF8 | ConvertFrom-Json)._meta
    Write-Host "    Snapshot found: $msiStateFile" -ForegroundColor Cyan
    Write-Host "    Created: $($msiMeta.created) on $($msiMeta.machine)" -ForegroundColor DarkGray

    $ans = Read-Host "  Apply saved MSI configuration? (Y/N) [default: Y]"
    if ($ans -eq '' -or $ans -ieq 'Y') {
        $restoreScript = "$SCRIPTS\msi_restore.ps1"
        & $restoreScript -StateFile $msiStateFile -DataDir $MSI_UTILS_DIR -SkipConfirm
        Write-Log "MSI state restored from snapshot" 'OK'
        $msiStateApplied = $true
    } else {
        Write-Host "    Skipped. Run 3 - MSI Utils\msi_restore.bat manually." -ForegroundColor Yellow
        Write-Log "Skipped: MSI restore (user opted out)" 'INFO'
    }
} else {
    Write-Step "PHASE B.13 - MSI interrupt mode (no snapshot found)"
    Write-Host "    No msi_state.json found in 3 - MSI Utils/." -ForegroundColor DarkGray
    Write-Host "    Configure MSI manually via MSI_util_v3.exe, then run msi_snapshot.bat to save" -ForegroundColor DarkGray
    Write-Host "    your settings -- next time run_all.bat runs, it will apply them automatically." -ForegroundColor DarkGray
    Write-Log "Skipped: MSI restore (no msi_state.json found)" 'INFO'
}

if ($installNvInspector) {
    Write-Step "PHASE B.14 - NVIDIA Profile Inspector install"
    Invoke-Script "$SCRIPTS\install_nvinspector.ps1" @{SourceRoot = $NVINSPECTOR_DIR}
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
& "$SCRIPTS\show_diff.ps1"

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
Write-Host "  7. Quick reruns if needed: DNS / Windows Update / Firewall (7 - DNS/, 8 - Windows Update/, 1 - Automated/scripts/firewall.bat)"
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

    $defenderLauncher = "$SCRIPTS\run_defender.ps1"
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
