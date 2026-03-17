#Requires -RunAsAdministrator
# msi_snapshot.ps1 - Capture MSI interrupt state of all PCI devices
#
# WHAT IT DOES
#   Reads the MSISupported and MessageNumberLimit registry values for every
#   PCI device and writes the result to msi_state.json (golden state for replay).
#
# BACKUPS
#   Before writing the new snapshot:
#     msi_state_backup.json    <- current live MSI state (always written)
#     msi_state_previous.json  <- previous msi_state.json if one already existed
#
# WHY
#   After a reformat, MSI mode must be re-enabled manually via the GUI tools.
#   Capturing the state once lets msi_restore.ps1 replay it automatically.
#
# HOW
#   For each PCI device, reads:
#     HKLM\SYSTEM\CurrentControlSet\Enum\<InstanceId>\
#       Device Parameters\Interrupt Management\MessageSignaledInterruptProperties\
#         MSISupported          (DWORD)
#         MessageNumberLimit    (DWORD, optional)

param([string]$DataDir = '')

$ErrorActionPreference = 'Continue'

if ($DataDir -eq '') { $DataDir = Split-Path $PSScriptRoot -Parent }
$STATE_FILE    = Join-Path $DataDir "msi_state.json"
$BACKUP_FILE   = Join-Path $DataDir "msi_state_backup.json"
$PREVIOUS_FILE = Join-Path $DataDir "msi_state_previous.json"

function Write-Info($msg)  { Write-Host "    $msg" }
function Write-Ok($msg)    { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "    [ERROR] $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   MSI SNAPSHOT                                 " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# ── A. Backup current live state ───────────────────────────────────────────────
Write-Info "Reading current live MSI state for backup..."
$liveState = [ordered]@{}
$liveState['_meta'] = [ordered]@{
    created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    machine = $env:COMPUTERNAME
    os      = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
}

$allPciDevices = Get-PnpDevice -InstanceId 'PCI\*' -ErrorAction SilentlyContinue
foreach ($dev in $allPciDevices) {
    $msiPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)\" +
               "Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
    if (Test-Path $msiPath) {
        $props = Get-ItemProperty -Path $msiPath -ErrorAction SilentlyContinue
        $liveState[$dev.InstanceId] = [ordered]@{
            FriendlyName       = $dev.FriendlyName
            Class              = $dev.Class
            MSISupported       = $props.MSISupported
            MessageNumberLimit = $props.MessageNumberLimit
        }
    }
}

try {
    $liveState | ConvertTo-Json -Depth 3 |
        Set-Content -Path $BACKUP_FILE -Encoding UTF8
    Write-Ok "Current live state saved -> msi_state_backup.json"
} catch {
    Write-Warn "Could not write msi_state_backup.json: $_"
}

# ── B. Preserve previous golden snapshot if it exists ─────────────────────────
if (Test-Path $STATE_FILE) {
    try {
        Copy-Item -Path $STATE_FILE -Destination $PREVIOUS_FILE -Force
        Write-Ok "Previous msi_state.json preserved -> msi_state_previous.json"
    } catch {
        Write-Warn "Could not copy previous msi_state.json: $_"
    }
}

Write-Host ""

# ── C. Enumerate all PCI devices and read MSI state ───────────────────────────
Write-Info "Enumerating PCI devices..."
Write-Host ""

$snapshot = [ordered]@{}
$snapshot['_meta'] = [ordered]@{
    created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    machine = $env:COMPUTERNAME
    os      = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
}

$countOn    = 0
$countOff   = 0
$countNoKey = 0

foreach ($dev in $allPciDevices) {
    $msiPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)\" +
               "Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"

    if (Test-Path $msiPath) {
        $props = Get-ItemProperty -Path $msiPath -ErrorAction SilentlyContinue
        $msiVal   = $props.MSISupported
        $limitVal = $props.MessageNumberLimit

        $snapshot[$dev.InstanceId] = [ordered]@{
            FriendlyName       = $dev.FriendlyName
            Class              = $dev.Class
            MSISupported       = $msiVal
            MessageNumberLimit = $limitVal
        }

        if ($msiVal -eq 1) {
            Write-Host ("    [MSI ON]  {0,-40} {1}" -f $dev.FriendlyName, $dev.InstanceId) -ForegroundColor Green
            $countOn++
        } else {
            Write-Host ("    [MSI OFF] {0,-40} {1}" -f $dev.FriendlyName, $dev.InstanceId) -ForegroundColor DarkYellow
            $countOff++
        }
    } else {
        $snapshot[$dev.InstanceId] = [ordered]@{
            FriendlyName       = $dev.FriendlyName
            Class              = $dev.Class
            MSISupported       = $null
            MessageNumberLimit = $null
        }
        Write-Host ("    [No key]  {0,-40} {1}" -f $dev.FriendlyName, $dev.InstanceId) -ForegroundColor DarkGray
        $countNoKey++
    }
}

Write-Host ""

# ── D. Write golden snapshot ───────────────────────────────────────────────────
try {
    $snapshot | ConvertTo-Json -Depth 3 |
        Set-Content -Path $STATE_FILE -Encoding UTF8
    Write-Ok "Snapshot written -> msi_state.json"
} catch {
    Write-Err "Failed to write msi_state.json: $_"
}

# ── E. Summary ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "    Summary: $countOn MSI ON, $countOff MSI OFF, $countNoKey no registry key" -ForegroundColor Cyan
Write-Host ""
Write-Host "    Commit msi_state.json to git to persist for future reinstalls." -ForegroundColor DarkGray
Write-Host "    Run msi_restore.bat after a reformat to replay this state." -ForegroundColor DarkGray
Write-Host ""
