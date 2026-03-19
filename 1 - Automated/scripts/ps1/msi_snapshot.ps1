#Requires -RunAsAdministrator
# msi_snapshot.ps1 - Capture the saved MSI replay snapshot after manual MSI tuning.
# Saved replay snapshot: 3 - MSI Utils\msi_state.json
# Default safety backup is captured separately as 1 - Automated\backup\msi_state_default.json before replay.

param(
    [string]$DataDir = '',
    [string]$StateFile = ''
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

$PACK_ROOT = Split-Path (Split-Path (Split-Path $PSScriptRoot))
if ($DataDir -eq '') { $DataDir = Join-Path $PACK_ROOT '3 - MSI Utils' }
if ($StateFile -eq '') { $StateFile = Join-Path $DataDir 'msi_state.json' }
$DataDir = Resolve-FullPath $DataDir
$StateFile = Resolve-FullPath $StateFile
$LEGACY_STATE_FILE = Resolve-FullPath (Join-Path $PACK_ROOT '1 - Automated\backup\msi_state.json')

function Write-Info($msg) { Write-Host "    $msg" }
function Write-Ok($msg) { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "    [ERROR] $msg" -ForegroundColor Red }
function Ensure-Dir([string]$Path) {
    if (-not [string]::IsNullOrWhiteSpace($Path) -and -not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '   MSI SNAPSHOT                                 ' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''

Ensure-Dir $DataDir
Ensure-Dir (Split-Path -Path $StateFile -Parent)

Write-Info 'Enumerating PCI devices...'
Write-Host ''

$snapshotState = [ordered]@{}
$snapshotState['_meta'] = [ordered]@{
    created = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    machine = $env:COMPUTERNAME
    os = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
}
$countOn = 0
$countOff = 0
$countNoKey = 0

$allPciDevices = Get-PciDevices
foreach ($dev in $allPciDevices) {
    $msiPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
    if (Test-Path -LiteralPath $msiPath) {
        $props = Get-ItemProperty -LiteralPath $msiPath -ErrorAction SilentlyContinue
        $msiVal = $props.MSISupported
        $limitVal = $props.MessageNumberLimit
        $snapshotState[$dev.InstanceId] = [ordered]@{
            FriendlyName = $dev.FriendlyName
            Class = $dev.Class
            MSISupported = $msiVal
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
        $snapshotState[$dev.InstanceId] = [ordered]@{
            FriendlyName = $dev.FriendlyName
            Class = $dev.Class
            MSISupported = $null
            MessageNumberLimit = $null
        }
        Write-Host ("    [No key]  {0,-40} {1}" -f $dev.FriendlyName, $dev.InstanceId) -ForegroundColor DarkGray
        $countNoKey++
    }
}

Write-Host ''
try {
    $snapshotState | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $StateFile -Encoding UTF8
    Write-Ok ("Snapshot written -> {0}" -f $StateFile)

    if ((Test-Path -LiteralPath $LEGACY_STATE_FILE) -and ($LEGACY_STATE_FILE -ne $StateFile)) {
        try {
            Remove-Item -LiteralPath $LEGACY_STATE_FILE -Force
            Write-Info ("Removed legacy snapshot copy -> {0}" -f $LEGACY_STATE_FILE)
        } catch {
            Write-Warn ("Could not remove legacy snapshot copy: {0}" -f $_.Exception.Message)
        }
    }
} catch {
    Write-Err ("Failed to write snapshot: {0}" -f $_.Exception.Message)
}

Write-Host ''
Write-Host "    Summary: $countOn MSI ON, $countOff MSI OFF, $countNoKey no registry key" -ForegroundColor Cyan
Write-Host ''
Write-Host "    Saved replay snapshot: $StateFile" -ForegroundColor DarkGray
Write-Host '    run_all.bat can apply it automatically when this file exists.' -ForegroundColor DarkGray
Write-Host ''
