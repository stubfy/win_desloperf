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
$PACK_VERSION = 'v0.4'
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
    try {
        $output = & $Path *>&1
        foreach ($line in $output) {
            if ($line -is [System.Management.Automation.ErrorRecord]) {
                Write-Log "  [ERR] $($line.Exception.Message)" 'WARN'
            } else {
                Write-Log "  $line" 'OUT'
            }
        }
        Write-Host "[OK]" -ForegroundColor Green
        Write-Log "End: $name -> OK" 'OK'
    } catch {
        Write-Host "[ERROR] $_" -ForegroundColor Red
        Write-Log "End: $name -> ERROR: $_" 'ERROR'
        Write-Log "  StackTrace: $($_.ScriptStackTrace)" 'ERROR'
    }
}

# ── Header ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  win_deslopper v0.2" -ForegroundColor Cyan
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

$uninstallEdge     = $false
$uninstallOneDrive = $false
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

$ans = Read-Host "  Completely uninstall Microsoft Edge? (Y/N)"
if ($ans -ieq 'Y') {
    $uninstallEdge = $true
    Write-Host "  -> Edge will be uninstalled after the main tweaks." -ForegroundColor Yellow
    Write-Log "Option selected: Edge uninstall = YES" 'INFO'
} else {
    Write-Log "Option selected: Edge uninstall = NO" 'INFO'
}

$ans = Read-Host "  Completely uninstall OneDrive? (Y/N)"
if ($ans -ieq 'Y') {
    $uninstallOneDrive = $true
    Write-Host "  -> OneDrive will be uninstalled after the main tweaks." -ForegroundColor Yellow
    Write-Log "Option selected: OneDrive uninstall = YES" 'INFO'
} else {
    Write-Log "Option selected: OneDrive uninstall = NO" 'INFO'
}

Write-Host ""

# ── PHASE A: Pre-tweak backup ──────────────────────────────────────────────────
Write-Step "PHASE A - Backup (restore point + service/registry state)"
Invoke-Script "$SCRIPTS\01_backup.ps1"

# ── PHASE B: Automated tweaks ──────────────────────────────────────────────────
Write-Step "PHASE B.1 - Registry tweaks (consolidated, deduplicated)"
Invoke-Script "$SCRIPTS\02_registry.ps1"

Write-Step "PHASE B.2 - Disable unnecessary services"
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

# ── OPTIONS: physical uninstalls ──────────────────────────────────────────────
if ($uninstallEdge) {
    Write-Step "OPTION - Physical uninstall of Microsoft Edge"
    Invoke-Script "$SCRIPTS\opt_edge_uninstall.ps1"
}

if ($uninstallOneDrive) {
    Write-Step "OPTION - OneDrive uninstall (Win32)"
    Invoke-Script "$SCRIPTS\opt_onedrive_uninstall.ps1"
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "   AUTOMATED TWEAKS COMPLETE                    " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "REMAINING MANUAL STEPS (see readme.txt at the pack root):" -ForegroundColor Cyan
Write-Host "  1. Reboot the PC"
Write-Host "  2. [Safe Mode] Disable Windows Defender"
Write-Host "  3. MSI Utils - enable MSI on GPU / NIC / NVMe"
Write-Host "  4. Interrupt Affinity - pin GPU interrupts to a CPU core"
Write-Host "  5. Network adapter - disable offloads, increase buffers"
Write-Host "  6. Device Manager - disable USB power saving"
Write-Host "  7. NVIDIA Profile Inspector - per-game profiles"
Write-Host "  8. Control Panel - follow folder 4 readme"
Write-Host ""
Write-Host "To undo all tweaks: .\restore_all.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "Full log: $LOG_FILE" -ForegroundColor DarkGray
Write-Host ""

Write-Log "============================================================"
Write-Log "Execution complete: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
Write-Log "============================================================"

$restart = Read-Host "Restart now? (Y/N)"
if ($restart -ieq 'Y') {
    Write-Log "Restart requested by user." 'INFO'
    Restart-Computer -Force
}
