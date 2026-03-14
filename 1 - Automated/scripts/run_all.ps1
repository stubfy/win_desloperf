#Requires -RunAsAdministrator
<#
.SYNOPSIS
    win_deslopper - Main launcher
    Windows 11 25H2 - Gaming optimization / Debloat / QoL

.DESCRIPTION
    Runs all automatable tweaks in the recommended order.
    Creates a backup before any modification.
    To undo: .\restore_all.ps1

.NOTES
    Manual steps after execution: see readme.txt at the pack root
#>

$ErrorActionPreference = 'Continue'
$ROOT         = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$SCRIPTS      = Join-Path $ROOT "scripts"
$PACK_VERSION = 'v0.8'
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
    param([string]$Path)
    $name = Split-Path $Path -Leaf
    Write-Host "    $name ... " -NoNewline
    Write-Log "Start: $name" 'RUN'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Path *>&1 | ForEach-Object {
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

# ── Header ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  win_deslopper v0.8" -ForegroundColor Cyan
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
$updateProfil      = '2'   # default: security only

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

Write-Step "PHASE B.5 - Cloudflare DNS (1.1.1.1 / 1.0.0.1)"
Invoke-Script "$SCRIPTS\06_dns.ps1"

Write-Step "PHASE B.6 - Microsoft Edge policies"
Invoke-Script "$SCRIPTS\07_edge.ps1"

Write-Step "PHASE B.7 - Remove bloatware UWP apps"
Invoke-Script "$SCRIPTS\08_debloat.ps1"

Write-Step "PHASE B.8 - O&O ShutUp10++ (silent mode)"
Invoke-Script "$SCRIPTS\09_oosu10.ps1"

Write-Step "PHASE B.9 - SetTimerResolution at startup"
Invoke-Script "$SCRIPTS\10_timer.ps1"

Write-Step "PHASE B.10 - USB selective suspend"
Invoke-Script "$SCRIPTS\11_usb.ps1"

Write-Step "PHASE B.11 - Disable AI / Recall / Copilot (25H2)"
Invoke-Script "$SCRIPTS\12_ai_disable.ps1"

Write-Step "PHASE B.12 - Telemetry scheduled tasks + PS7 + Brave"
Invoke-Script "$SCRIPTS\13_telemetry_tasks.ps1"

Write-Step "PHASE B.13 - Additional network tweaks (Teredo)"
Invoke-Script "$SCRIPTS\14_network_tweaks.ps1"

Write-Step "PHASE B.14 - Windows Update profile: $profilLabel"
& "$SCRIPTS\15_windows_update.ps1" -Profil $updateProfil

if ($disableFirewall) {
    Write-Step "PHASE B.15 - Disable Windows Firewall profiles"
    Invoke-Script "$SCRIPTS\18_firewall.ps1"
}

Write-Step "PHASE B.16 - UWT equivalent tweaks (appearance, privacy, context menu)"
Invoke-Script "$SCRIPTS\16_uwt.ps1"

Write-Step "PHASE B.17 - MarkC mouse acceleration fix (1:1 scaling)"
Invoke-Script "$SCRIPTS\17_mouse_accel.ps1"

# ── OPTIONS: physical uninstalls ──────────────────────────────────────────────
if ($uninstallEdge) {
    Write-Step "OPTION - Microsoft Edge + WebView2 Runtime uninstall"
    Invoke-Script "$SCRIPTS\opt_edge_uninstall.ps1"
}

if ($uninstallOneDrive) {
    Write-Step "OPTION - OneDrive uninstall (Win32)"
    Invoke-Script "$SCRIPTS\opt_onedrive_uninstall.ps1"
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
Write-Host "  2. [Safe Mode] Disable Windows Defender      (2 - Windows Defender/)"
Write-Host "  3. MSI Utils - enable MSI on GPU/NIC/NVMe   (3 - MSI Utils/)"
Write-Host "  4. NVIDIA Profile Inspector - per-game       (4 - NVInspector/)"
Write-Host "  5. Device Manager - disable USB power saving (5 - Gestionnaire/)"
Write-Host "  6. Interrupt Affinity - pin GPU IRQ to core  (6 - Interrupt Affinity/)"
Write-Host "  7. NIC settings - disable offloads, buffers  (7 - Network WIP/)"
Write-Host "  8. Verify timer: run MeasureSleep.exe        (1 - Automated/tools/)"
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
    bcdedit /set '{current}' safeboot minimal | Out-Null

    # Create an explicit Safe Mode helper on the Desktop
    $batDest        = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Disable Defender and Return to Normal Mode.bat'
    $defenderScript = Join-Path $ROOT '2 - Windows Defender\1 - DisableDefender.ps1'
    @"
@echo off
echo.
echo  =========================================================
echo   win_deslopper -- Disable Defender and Return to Normal Mode
echo  =========================================================
echo.
echo  This will:
echo    1. Disable Windows Defender (6 services set to Start=4)
echo    2. Remove Safe Boot flag
echo    3. Reboot to normal Windows
echo.
pause
PowerShell -ExecutionPolicy Bypass -File "$defenderScript"
bcdedit /deletevalue {current} safeboot
shutdown /r /t 0
"@ | Set-Content -Path $batDest -Encoding ASCII

    Write-Host ""
    Write-Host "  Safe Mode is now configured." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  WHAT TO DO IN SAFE MODE:" -ForegroundColor Cyan
    Write-Host "    Run the shortcut on your Desktop: 'Disable Defender and Return to Normal Mode.bat'" -ForegroundColor White
    Write-Host "    (disables Defender, removes Safe Boot, reboots automatically)" -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  Press Enter to reboot into Safe Mode"
    Restart-Computer -Force
} elseif ($restart -ieq 'Y') {
    Write-Log "Restart requested by user." 'INFO'
    Restart-Computer -Force
}
