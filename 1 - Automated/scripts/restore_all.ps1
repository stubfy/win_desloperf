#Requires -RunAsAdministrator
<#
.SYNOPSIS
    win_deslopper - Full restore
    Reverts all tweaks applied by run_all.ps1

.DESCRIPTION
    Restores the system to its original state.
    Uses the restore point created at launch (recommended method)
    or applies the default values for each tweak.
#>

$ErrorActionPreference = 'Continue'
$ROOT    = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$RESTORE = Join-Path $ROOT "restore"

function Write-Step {
    param([string]$Msg)
    Write-Host ""
    Write-Host ">>> $Msg" -ForegroundColor Yellow
}

function Invoke-Script {
    param([string]$Path)
    $name = Split-Path $Path -Leaf
    Write-Host "    $name ... " -NoNewline
    try {
        & $Path
        Write-Host "[OK]" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "   WIN_DESLOPPER - RESTORE                      " -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "This operation reverts all tweaks applied by run_all.ps1" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Confirm restore? (Y/N)"
if ($confirm -ine 'Y') {
    Write-Host "Cancelled." -ForegroundColor Gray
    exit
}

Write-Step "Restore registry (Windows default values)"
Invoke-Script "$RESTORE\01_registry.ps1"

Write-Step "Restore services"
Invoke-Script "$RESTORE\02_services.ps1"

Write-Step "Restore boot configuration (bcdedit)"
Invoke-Script "$RESTORE\03_bcdedit.ps1"

Write-Step "Restore DNS (automatic DHCP)"
Invoke-Script "$RESTORE\04_dns.ps1"

Write-Step "Remove Microsoft Edge policies"
Invoke-Script "$RESTORE\05_edge.ps1"

Write-Step "Remove SetTimerResolution from startup"
Invoke-Script "$RESTORE\06_timer.ps1"

Write-Step "Restore power plan"
Invoke-Script "$RESTORE\07_power.ps1"

Write-Step "Restore USB selective suspend"
Invoke-Script "$RESTORE\08_usb.ps1"

Write-Step "Remove AI / Recall / Copilot policies"
Invoke-Script "$RESTORE\09_ai_restore.ps1"

Write-Step "UWP app reinstallation help"
Invoke-Script "$RESTORE\10_debloat_restore.ps1"

Write-Step "Restore network tweaks (Teredo)"
Invoke-Script "$RESTORE\14_network_tweaks.ps1"

Write-Step "Restore Windows Update (maximum mode - Windows default)"
Invoke-Script "$RESTORE\15_windows_update.ps1"

Write-Step "Restore UWT equivalent tweaks"
Invoke-Script "$RESTORE\16_uwt.ps1"

# Scheduled tasks
Write-Host ""
Write-Host "    Note: disabled telemetry scheduled tasks are not" -ForegroundColor Gray
Write-Host "    restored automatically. Re-enable them via: Task Scheduler" -ForegroundColor Gray
Write-Host "    (Microsoft\Windows\Customer Experience Improvement Program, etc.)" -ForegroundColor Gray

# Conditional Edge / OneDrive options
Write-Host ""
$restoreEdge = Read-Host "Reinstall Microsoft Edge? (Y/N)"
if ($restoreEdge -ieq 'Y') {
    Write-Step "OPTION - Reinstall Microsoft Edge"
    Invoke-Script "$RESTORE\opt_edge_restore.ps1"
}

$restoreOneDrive = Read-Host "Reinstall OneDrive? (Y/N)"
if ($restoreOneDrive -ieq 'Y') {
    Write-Step "OPTION - Reinstall OneDrive"
    Invoke-Script "$RESTORE\opt_onedrive_restore.ps1"
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

$restart = Read-Host "Restart now? (Y/N)"
if ($restart -ieq 'Y') {
    Restart-Computer -Force
}
