#Requires -RunAsAdministrator
<#
.SYNOPSIS
    win_desloperf - Full restore
    Reverts all tweaks applied by run_all.ps1

.DESCRIPTION
    Restores the system to its original state.
    Recommended primary method: use the system restore point created by backup.ps1
    (Control Panel > Recovery > Open System Restore) for a complete state revert.

    This script applies symmetric rollback scripts from restore\ as a programmatic
    alternative. Each restore script undoes one category of tweaks:
      registry.ps1          - Imports tweaks_defaults.reg + resets SPI visual effects + mouse curves
      services.ps1          - Reads backup\services_state.json and restores each service
      performance.ps1       - Removes disabledynamictick/bootmenupolicy, restores power plan + USB
      dns.ps1               - Restores DHCP-assigned DNS on all interfaces
      timer.ps1             - Deletes startup shortcut, terminates SetTimerResolution
      privacy.ps1           - Imports privacy_defaults.reg, removes AI/Recall/Copilot policy keys
      ai_debloat.ps1        - Restores saved JSON backups for AI deep-debloat
      debloat_restore.ps1   - Provides guidance for reinstalling removed UWP apps
      network_tweaks.ps1    - Re-enables Teredo (netsh teredo set state default)
      usb_power.ps1         - Restores USB device power management from backup\usb_power_state.json
      windows_update.ps1    - Restores full WU (Profile 1 = Maximum)
      firewall.ps1          - Restores firewall profiles from backup\firewall_state.json
      personal_settings.ps1 - Imports personal_settings_defaults.reg
      restore_affinity.ps1  - Deletes or reverts GPU interrupt affinity policy

    Known limitations (not automatically restored):
      - UWP apps removed by debloat.ps1 and ai_debloat.ps1 must be reinstalled manually from the Store.
      - Telemetry scheduled tasks disabled by privacy.ps1 must be re-enabled
        via Task Scheduler (Microsoft\Windows\Customer Experience Improvement Program etc.)
      - OOSU10 settings applied by privacy.ps1 are not individually rolled back.
#>

$ErrorActionPreference = 'Continue'
$ROOT         = Split-Path (Split-Path (Split-Path $MyInvocation.MyCommand.Path))
$PACK_ROOT    = Split-Path $ROOT -Parent
$RESTORE      = Join-Path $ROOT "restore\ps1"
$SCRIPTS      = Join-Path $ROOT "scripts\ps1"
$LOG_DIR      = Join-Path $env:APPDATA 'win_desloperf\logs'
$LOG_FILE     = Join-Path $LOG_DIR 'win_desloperf_restore.log'

if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }
if (Test-Path $LOG_FILE) { Remove-Item -LiteralPath $LOG_FILE -Force -ErrorAction SilentlyContinue }

function Get-PackVersion {
    param([string]$PackRoot)

    $versionFile = Join-Path $PackRoot 'pack-version.txt'
    if (Test-Path $versionFile) {
        $raw = Get-Content -Path $versionFile -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            return $raw.Trim()
        }
    }

    return 'v1.0'
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
        Write-Host "[OK]" -ForegroundColor Green
        Write-Log "End: $name -> OK ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" 'OK'
    } catch {
        $sw.Stop()
        Write-Host "[ERROR] $_" -ForegroundColor Red
        Write-Log "End: $name -> ERROR after $([math]::Round($sw.Elapsed.TotalSeconds, 1))s: $_" 'ERROR'
        Write-Log "  StackTrace: $($_.ScriptStackTrace)" 'ERROR'
    }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "   WIN_DESLOPERF - RESTORE                      " -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "This operation reverts all tweaks applied by run_all.ps1" -ForegroundColor Red
Write-Host "Log: $LOG_FILE" -ForegroundColor DarkGray
Write-Host ""

Write-Log '============================================================'
Write-Log "win_desloperf restore $PACK_VERSION" 'INFO'
Write-Log "Date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
Write-Log "OS     : $([System.Environment]::OSVersion.VersionString)" 'INFO'
Write-Log "Machine: $env:COMPUTERNAME" 'INFO'
Write-Log "User   : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" 'INFO'
Write-Log "Log    : $LOG_FILE" 'INFO'
Write-Log '============================================================'

$confirm = Read-Host "Confirm restore? (Y/N)"
Write-Log "Prompt: Confirm restore = $confirm" 'INFO'
if ($confirm -ine 'Y') {
    Write-Host "Cancelled." -ForegroundColor Gray
    Write-Log 'Restore cancelled at confirmation prompt.' 'INFO'
    exit
}

Write-Log 'Restore confirmed by user.' 'INFO'

Write-Step "Restore registry (Windows default values)"
Invoke-Script "$RESTORE\registry.ps1"

Write-Step "Restore services"
Invoke-Script "$RESTORE\services.ps1"

Write-Step "Restore system performance (boot config, power plan, USB)"
Invoke-Script "$RESTORE\performance.ps1"

Write-Step "Restore DNS (automatic DHCP)"
Invoke-Script "$RESTORE\dns.ps1"

Write-Step "Remove SetTimerResolution from startup"
Invoke-Script "$RESTORE\timer.ps1"

Write-Step "Restore privacy & AI settings"
Invoke-Script "$RESTORE\privacy.ps1"

Write-Step "Restore AI deep-debloat backups"
Invoke-Script "$RESTORE\ai_debloat.ps1"

Write-Step "UWP app reinstallation help"
Invoke-Script "$RESTORE\debloat_restore.ps1"

Write-Step "Restore network tweaks (Teredo)"
Invoke-Script "$RESTORE\network_tweaks.ps1"

Write-Step "Restore USB device power management"
Invoke-Script "$RESTORE\usb_power.ps1"

Write-Step "Restore Windows Update (maximum mode - Windows default)"
Invoke-Script "$RESTORE\windows_update.ps1"

Write-Step "Restore Windows Firewall profiles"
Invoke-Script "$RESTORE\firewall.ps1"

Write-Step "Restore personal shell/theme settings"
Invoke-Script "$RESTORE\personal_settings.ps1"

Write-Step "Restore interrupt affinity (GPU + mouse, Windows default)"
Invoke-Script "$SCRIPTS\restore_affinity.ps1"

# Scheduled tasks
Write-Host ""
Write-Host "    Note: disabled telemetry scheduled tasks are not" -ForegroundColor Gray
Write-Host "    restored automatically. Re-enable them via: Task Scheduler" -ForegroundColor Gray
Write-Host "    (Microsoft\Windows\Customer Experience Improvement Program, etc.)" -ForegroundColor Gray
Write-Log 'Reminder: telemetry scheduled tasks are not restored automatically.' 'WARN'

# Conditional Edge / OneDrive options
Write-Host ""
$restoreEdge = Read-Host "Reinstall Microsoft Edge? (Y/N)"
Write-Log "Prompt: Reinstall Edge = $restoreEdge" 'INFO'
if ($restoreEdge -ieq 'Y') {
    Write-Step "OPTION - Reinstall Microsoft Edge"
    Invoke-Script "$RESTORE\opt_edge_restore.ps1"
} else {
    Write-Log 'Skipped: opt_edge_restore.ps1 (user chose not to reinstall Edge)' 'INFO'
}

$restoreOneDrive = Read-Host "Reinstall OneDrive? (Y/N)"
Write-Log "Prompt: Reinstall OneDrive = $restoreOneDrive" 'INFO'
if ($restoreOneDrive -ieq 'Y') {
    Write-Step "OPTION - Reinstall OneDrive"
    Invoke-Script "$RESTORE\opt_onedrive_restore.ps1"
} else {
    Write-Log 'Skipped: opt_onedrive_restore.ps1 (user chose not to reinstall OneDrive)' 'INFO'
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "   RESTORE COMPLETE                             " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Restart the PC to finalize." -ForegroundColor Yellow
Write-Host ""
Write-Host "If issues persist, use the system restore point" -ForegroundColor Gray
Write-Host "created by run_all.ps1 (Control Panel > Recovery)." -ForegroundColor Gray
Write-Host ""

Write-Log '============================================================'
Write-Log "Restore complete: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
Write-Log '============================================================'

$restart = Read-Host "Restart now? (Y/N)"
Write-Log "Prompt: Restart now = $restart" 'INFO'
if ($restart -ieq 'Y') {
    Write-Log 'Immediate restart confirmed by user.' 'INFO'
    Restart-Computer -Force
} else {
    Write-Log 'Immediate restart skipped by user.' 'INFO'
}

