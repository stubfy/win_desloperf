#Requires -RunAsAdministrator
# msi_restore.ps1 - Restore the default MSI safety backup.
# Default safety backup: 1 - Automated\backup\msi_state_default.json

param(
    [string]$StateFile = '',
    [switch]$SkipConfirm
)

$ErrorActionPreference = 'Continue'

function Resolve-FullPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }

    try {
        return [System.IO.Path]::GetFullPath($Path)
    } catch {
        return $Path
    }
}

function Get-PciDevices {
    if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
        return @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.InstanceId) -and $_.InstanceId -like 'PCI\*'
            })
    }

    return @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.PNPDeviceID) -and $_.PNPDeviceID -like 'PCI\*'
        } |
        ForEach-Object {
            [PSCustomObject]@{
                FriendlyName = $_.Name
                Class = $_.PNPClass
                InstanceId = $_.PNPDeviceID
            }
        })
}

function Test-EntryHasProperty($Entry, [string]$Name) {
    return ($null -ne $Entry -and $Entry.PSObject.Properties.Name -contains $Name)
}

function Set-InterruptPriorityState([string]$InstanceId, $Entry) {
    if (-not (Test-EntryHasProperty $Entry 'DevicePriority') -and -not (Test-EntryHasProperty $Entry 'DevicePriorityExists')) {
        return
    }

    $priorityPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId\Device Parameters\Interrupt Management\Affinity Policy"
    $priorityExists = if (Test-EntryHasProperty $Entry 'DevicePriorityExists') {
        [bool]$Entry.DevicePriorityExists
    } else {
        $null -ne $Entry.DevicePriority
    }

    if ($priorityExists) {
        if (-not (Test-Path -LiteralPath $priorityPath)) {
            New-Item -Path $priorityPath -Force -ErrorAction Stop | Out-Null
        }
        $priorityValue = if ($null -ne $Entry.DevicePriority) { [int]$Entry.DevicePriority } else { 0 }
        Set-ItemProperty -LiteralPath $priorityPath -Name 'DevicePriority' -Value $priorityValue -Type DWord -Force -ErrorAction Stop
        return
    }

    if (Test-Path -LiteralPath $priorityPath) {
        Remove-ItemProperty -LiteralPath $priorityPath -Name 'DevicePriority' -Force -ErrorAction SilentlyContinue
    }
}

$PACK_ROOT = Split-Path (Split-Path (Split-Path $PSScriptRoot))
if ($StateFile -eq '') { $StateFile = Join-Path $PACK_ROOT '1 - Automated\backup\msi_state_default.json' }
$StateFile = Resolve-FullPath $StateFile
$LEGACY_STATE_FILE = Resolve-FullPath (Join-Path $PACK_ROOT '3 - MSI Utils\msi_state_pre_restore.json')

function Write-Info($msg) { Write-Host "    $msg" }
function Write-Ok($msg) { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "    [ERROR] $msg" -ForegroundColor Red }
function Ensure-Dir([string]$Path) {
    if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Resolve-StateFile {
    if (Test-Path -LiteralPath $StateFile) { return $StateFile }
    if (-not (Test-Path -LiteralPath $LEGACY_STATE_FILE)) { return $StateFile }

    try {
        Ensure-Dir (Split-Path -Path $StateFile -Parent)
        Move-Item -LiteralPath $LEGACY_STATE_FILE -Destination $StateFile -Force
        Write-Warn "Legacy default MSI backup moved -> $StateFile"
        return $StateFile
    } catch {
        Write-Warn "Could not move legacy default MSI backup: $($_.Exception.Message)"
        return $LEGACY_STATE_FILE
    }
}

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '   MSI RESTORE                                  ' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''

Ensure-Dir (Split-Path -Path $StateFile -Parent)
$ResolvedStateFile = Resolve-StateFile

if (-not (Test-Path -LiteralPath $ResolvedStateFile)) {
    Write-Err "Default MSI backup not found: $ResolvedStateFile"
    Write-Info 'A default MSI backup is created the first time a saved MSI snapshot is applied.'
    Write-Host ''
    exit 1
}

try {
    $raw = Get-Content -LiteralPath $ResolvedStateFile -Encoding UTF8 | ConvertFrom-Json
    $metaObj = $raw._meta
    Write-Info "Default backup: $ResolvedStateFile"
    Write-Info "Created      : $($metaObj.created) on $($metaObj.machine)"
    Write-Info "OS           : $($metaObj.os)"
} catch {
    Write-Err "Failed to read default MSI backup: $($_.Exception.Message)"
    Write-Host ''
    exit 1
}

Write-Host ''
$currentDeviceIds = @{}
$allPciDevices = Get-PciDevices
foreach ($dev in $allPciDevices) { $currentDeviceIds[$dev.InstanceId] = $dev }

$toApply = @()
$propsNames = $raw | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
foreach ($id in $propsNames) {
    if ($id -eq '_meta') { continue }
    $entry = $raw.$id
    $hasPriorityState = (Test-EntryHasProperty $entry 'DevicePriorityExists' -and [bool]$entry.DevicePriorityExists) -or (Test-EntryHasProperty $entry 'DevicePriority' -and $null -ne $entry.DevicePriority)
    if ($null -ne $entry.MSISupported -or $hasPriorityState) { $toApply += $id }
}

Write-Info "$($toApply.Count) device(s) from the default MSI/priority backup will be restored."
Write-Host ''

if (-not $SkipConfirm) {
    $ans = Read-Host '  Continue? (Y/N) [default: N]'
    if ($ans -notin @('Y', 'y')) {
        Write-Info 'Aborted by user.'
        Write-Host ''
        exit 0
    }
    Write-Host ''
}

$countApplied = 0
$countSkipped = 0
$countNotFound = 0
$countErrors = 0

foreach ($id in $propsNames) {
    if ($id -eq '_meta') { continue }
    $entry = $raw.$id
    $hasPriorityState = (Test-EntryHasProperty $entry 'DevicePriorityExists' -and [bool]$entry.DevicePriorityExists) -or (Test-EntryHasProperty $entry 'DevicePriority' -and $null -ne $entry.DevicePriority)
    if ($null -eq $entry.MSISupported -and -not $hasPriorityState) {
        $countSkipped++
        continue
    }
    if (-not $currentDeviceIds.ContainsKey($id)) {
        Write-Warn "Device not found on this system (may have changed slot/ID): $id"
        if ($entry.FriendlyName) { Write-Warn "  Was: $($entry.FriendlyName)" }
        $countNotFound++
        continue
    }

    $msiPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$id\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
    try {
        if ($null -ne $entry.MSISupported) {
            if (-not (Test-Path -LiteralPath $msiPath)) { New-Item -Path $msiPath -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -LiteralPath $msiPath -Name 'MSISupported' -Value ([int]$entry.MSISupported) -Type DWord -Force -ErrorAction Stop
            if ($null -ne $entry.MessageNumberLimit) {
                Set-ItemProperty -LiteralPath $msiPath -Name 'MessageNumberLimit' -Value ([int]$entry.MessageNumberLimit) -Type DWord -Force -ErrorAction Stop
            }
        }
        Set-InterruptPriorityState $id $entry
        $label = if ($entry.FriendlyName) { $entry.FriendlyName } else { $id }
        $msiLabel = if ($entry.MSISupported -eq 1) { 'MSI ON' } elseif ($null -ne $entry.MSISupported) { 'MSI OFF' } else { 'MSI N/A' }
        Write-Ok ("[$msiLabel] $label")
        $countApplied++
    } catch {
        Write-Err ("Failed on {0}: {1}" -f $id, $_.Exception.Message)
        $countErrors++
    }
}

Write-Host ''
Write-Host ("    Restored: {0}  |  Skipped (no key): {1}  |  Not found: {2}  |  Errors: {3}" -f $countApplied, $countSkipped, $countNotFound, $countErrors) -ForegroundColor Cyan
Write-Host ''
Write-Host "    Default safety backup: $ResolvedStateFile" -ForegroundColor DarkGray
Write-Host ''

if ($countNotFound -gt 0) {
    Write-Warn 'Some devices were not found. They may have changed PCI slot or InstanceId.'
    Write-Warn 'Open MSI_util_v3.exe to configure them manually if needed.'
    Write-Host ''
}

Write-Host '    Reboot required for changes to take effect.' -ForegroundColor Yellow
Write-Host ''
