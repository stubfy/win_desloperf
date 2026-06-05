#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Update profile configuration

.DESCRIPTION
    Three profiles available (ported from WinUtil / Chris Titus Tech):
      1 - Default  : restores the WinUtil out-of-box Windows Update configuration
      2 - Security : WinUtil recommended profile (365-day feature deferral, 4-day quality deferral, no drivers via WU)
      3 - Disabled : completely disables Windows Update

    The numeric interface stays stable for compatibility with run_all.ps1,
    standalone launchers, and saved options.

    Rollback: 1 - Automated\restore\windows_update.bat reapplies Profile 1 (Default).

.PARAMETER Profil
    1, 2 or 3. If omitted, an interactive menu is shown.

.EXAMPLE
    .\set_windows_update.ps1 -Profil 2
    .\set_windows_update.ps1          # interactive menu
#>

param(
    [ValidateSet('1','2','3')]
    [string]$Profil
)

$ErrorActionPreference = 'Continue'
$VendorRoot = Join-Path $PSScriptRoot 'vendor\winutil'
$VendorFiles = @(
    'Invoke-WPFUpdatesdefault.ps1'
    'Invoke-WPFUpdatessecurity.ps1'
    'Invoke-WPFUpdatesdisable.ps1'
)

foreach ($file in $VendorFiles) {
    $path = Join-Path $VendorRoot $file
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing vendored WinUtil function: $path"
    }

    . $path
}

function Remove-PackWindowsUpdateOverrides {
    $paths = @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching'
        'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization'
    )

    foreach ($path in $paths) {
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Repair-DeliveryOptimizationService {
    $svc = Get-Service -Name DoSvc -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host '  Delivery Optimization service (DoSvc) not found.' -ForegroundColor DarkGray
        return
    }

    $serviceKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc'
    $startValue = $null
    if (Test-Path $serviceKey) {
        $startValue = (Get-ItemProperty -LiteralPath $serviceKey -Name Start -ErrorAction SilentlyContinue).Start
    }

    if ($startValue -eq 4) {
        Write-Host '  Repairing Delivery Optimization service startup: Automatic'
        Set-Service -Name DoSvc -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name DoSvc -ErrorAction SilentlyContinue
    } else {
        Write-Host '  Delivery Optimization service available.'
    }
}

function Ensure-DeliveryOptimizationHttpOnly {
    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'

    New-Item -Path $path -Force | Out-Null
    Set-ItemProperty -Path $path -Name 'DODownloadMode' -Type DWord -Value 0
    Write-Host '  Delivery Optimization P2P sharing disabled (HTTP only).'
}

function Ensure-WindowsUpdateStableOnly {
    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

    New-Item -Path $path -Force | Out-Null
    Set-ItemProperty -Path $path -Name 'ManagePreviewBuilds' -Type DWord -Value 0
    Set-ItemProperty -Path $path -Name 'SetAllowOptionalContent' -Type DWord -Value 0
    Write-Host '  Preview builds and automatic optional preview updates disabled.'
}

function Ensure-WindowsUpdateNoAutoReboot {
    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'

    New-Item -Path $path -Force | Out-Null
    Set-ItemProperty -Path $path -Name 'NoAutoRebootWithLoggedOnUsers' -Type DWord -Value 1
    Set-ItemProperty -Path $path -Name 'AUPowerManagement' -Type DWord -Value 0
    Write-Host '  Automatic restart while a user is logged on disabled.'
}

function Get-PackHiddenDriverStatePath {
    $root = Join-Path $env:APPDATA 'win_desloperf'
    New-Item -Path $root -ItemType Directory -Force | Out-Null
    Join-Path $root 'windows_update_hidden_drivers.json'
}

function Read-PackHiddenDriverState {
    param(
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        return @()
    }

    $json = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrWhiteSpace($json)) {
        return @()
    }

    $parsed = $json | ConvertFrom-Json
    $items = foreach ($item in @($parsed)) {
        foreach ($nested in @($item)) {
            if ($nested -and $nested.UpdateID) {
                $nested
            }
        }
    }

    return @($items)
}

function Ensure-WindowsUpdateDriverBlocking {
    $wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $deviceMetadataPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'
    $driverSearchPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching'
    $driverSearchPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'

    New-Item -Path $wuPath -Force | Out-Null
    Set-ItemProperty -Path $wuPath -Name 'ExcludeWUDriversInQualityUpdate' -Type DWord -Value 1

    New-Item -Path $deviceMetadataPath -Force | Out-Null
    Set-ItemProperty -Path $deviceMetadataPath -Name 'PreventDeviceMetadataFromNetwork' -Type DWord -Value 1

    New-Item -Path $driverSearchPolicyPath -Force | Out-Null
    Set-ItemProperty -Path $driverSearchPolicyPath -Name 'DontPromptForWindowsUpdate' -Type DWord -Value 1
    Set-ItemProperty -Path $driverSearchPolicyPath -Name 'DontSearchWindowsUpdate' -Type DWord -Value 1
    Set-ItemProperty -Path $driverSearchPolicyPath -Name 'DriverUpdateWizardWuSearchEnabled' -Type DWord -Value 0

    New-Item -Path $driverSearchPath -Force | Out-Null
    Set-ItemProperty -Path $driverSearchPath -Name 'SearchOrderConfig' -Type DWord -Value 0

    Write-Host '  Driver updates disabled through Windows Update policies.'
}

function Test-IsWindowsUpdateDriver {
    param($Update)

    if ($Update.Type -eq 2) {
        return $true
    }

    foreach ($category in $Update.Categories) {
        if ($category.Name -eq 'Drivers') {
            return $true
        }
    }

    return $false
}

function Hide-PendingWindowsUpdateDrivers {
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result = $searcher.Search('IsInstalled=0 and IsHidden=0')
    } catch {
        Write-Host "  Unable to enumerate optional driver updates: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }

    $hidden = @()
    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $update = $result.Updates.Item($i)
        if (-not (Test-IsWindowsUpdateDriver -Update $update)) {
            continue
        }

        try {
            $update.IsHidden = $true
            $hidden += [pscustomobject]@{
                UpdateID       = $update.Identity.UpdateID
                RevisionNumber = $update.Identity.RevisionNumber
                Title          = $update.Title
            }
            Write-Host "  Hidden optional driver update: $($update.Title)"
        } catch {
            Write-Host "  Failed to hide optional driver update: $($update.Title)" -ForegroundColor Yellow
        }
    }

    if ($hidden.Count -gt 0) {
        $statePath = Get-PackHiddenDriverStatePath
        $hidden | ConvertTo-Json -Depth 4 | Set-Content -Path $statePath -Encoding UTF8
        Write-Host "  Hidden optional driver updates tracked: $statePath"
    } else {
        Write-Host '  No visible optional driver updates to hide.'
    }
}

function Restore-PackHiddenWindowsUpdateDrivers {
    $statePath = Get-PackHiddenDriverStatePath
    if (-not (Test-Path -Path $statePath)) {
        return
    }

    try {
        $state = Read-PackHiddenDriverState -Path $statePath
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result = $searcher.Search('IsInstalled=0 and IsHidden=1')
    } catch {
        Write-Host "  Unable to restore pack-hidden optional driver updates: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }

    $restored = 0
    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $update = $result.Updates.Item($i)
        if (-not (Test-IsWindowsUpdateDriver -Update $update)) {
            continue
        }

        $match = $state | Where-Object {
            $_.UpdateID -eq $update.Identity.UpdateID -and
            [int]$_.RevisionNumber -eq [int]$update.Identity.RevisionNumber
        } | Select-Object -First 1

        if (-not $match) {
            continue
        }

        try {
            $update.IsHidden = $false
            $restored++
            Write-Host "  Restored optional driver update visibility: $($update.Title)"
        } catch {
            Write-Host "  Failed to restore optional driver update visibility: $($update.Title)" -ForegroundColor Yellow
        }
    }

    Remove-Item -Path $statePath -Force -ErrorAction SilentlyContinue
    if ($restored -gt 0) {
        Write-Host "  Restored $restored pack-hidden optional driver update(s)."
    }
}

function Test-PackHiddenWindowsUpdateDriversPending {
    $statePath = Get-PackHiddenDriverStatePath
    if (-not (Test-Path -Path $statePath)) {
        return $false
    }

    try {
        $state = Read-PackHiddenDriverState -Path $statePath
        if ($state.Count -eq 0) {
            return $false
        }

        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result = $searcher.Search('IsInstalled=0 and IsHidden=1')
    } catch {
        Write-Host "  Unable to verify hidden optional driver state: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }

    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $update = $result.Updates.Item($i)
        if (-not (Test-IsWindowsUpdateDriver -Update $update)) {
            continue
        }

        $match = $state | Where-Object {
            $_.UpdateID -eq $update.Identity.UpdateID -and
            [int]$_.RevisionNumber -eq [int]$update.Identity.RevisionNumber
        } | Select-Object -First 1

        if ($match) {
            return $true
        }
    }

    return $false
}

function Reset-WindowsUpdateUxStore {
    if (-not (Test-PackHiddenWindowsUpdateDriversPending)) {
        Write-Host '  Windows Update UX store reset skipped (no pack-hidden optional drivers pending).'
        return
    }

    $storeRoot = Join-Path $env:ProgramData 'USOPrivate\UpdateStore'
    if (-not (Test-Path -Path $storeRoot)) {
        Write-Host '  Windows Update UX store not found; reset skipped.' -ForegroundColor Yellow
        return
    }

    $backupRoot = Join-Path $env:APPDATA 'win_desloperf\windows_update_ux_store_backup'
    $backupDir = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -Path $backupDir -ItemType Directory -Force | Out-Null

    foreach ($processName in @('SystemSettings', 'MoUsoCoreWorker', 'MusNotification', 'MusNotifyIcon')) {
        Get-Process -Name $processName -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }

    $services = @('UsoSvc', 'wuauserv')
    $runningServices = @{}
    foreach ($serviceName in $services) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        $runningServices[$serviceName] = ($service -and $service.Status -eq 'Running')
        if ($service -and $service.Status -eq 'Running') {
            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        }
    }

    Start-Sleep -Seconds 2

    $moved = 0
    foreach ($fileName in @('store.db', 'store.bak')) {
        $path = Join-Path $storeRoot $fileName
        if (-not (Test-Path -Path $path)) {
            continue
        }

        $destination = Join-Path $backupDir $fileName
        try {
            Move-Item -Path $path -Destination $destination -Force -ErrorAction Stop
            $moved++
        } catch {
            Write-Host "  Failed to back up Windows Update UX store file ($fileName): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    foreach ($serviceName in $services) {
        if ($runningServices[$serviceName]) {
            Start-Service -Name $serviceName -ErrorAction SilentlyContinue
        }
    }

    if ($moved -gt 0) {
        Write-Host "  Windows Update UX store reset; backup saved to: $backupDir"
    } else {
        Write-Host '  Windows Update UX store reset skipped (no cache files moved).' -ForegroundColor Yellow
    }
}

function Refresh-WindowsUpdateUiState {
    $uso = Join-Path $env:SystemRoot 'System32\UsoClient.exe'
    if (-not (Test-Path -Path $uso)) {
        Write-Host '  UsoClient.exe not found; Windows Update UI refresh skipped.' -ForegroundColor Yellow
        return
    }

    foreach ($action in @('RefreshSettings', 'StartInteractiveScan', 'StartScan')) {
        try {
            Start-Process -FilePath $uso -ArgumentList $action -WindowStyle Hidden -ErrorAction Stop | Out-Null
            Write-Host "  Windows Update UI refresh requested: $action"
        } catch {
            Write-Host "  Windows Update UI refresh failed ($action): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

if (-not $Profil) {
    Write-Host ''
    Write-Host '  WINDOWS UPDATE PROFILE' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  [1] Default   - Restore WinUtil out-of-box Windows Update settings' -ForegroundColor Green
    Write-Host '  [2] Security  - WinUtil recommended profile (365-day feature deferral, 4-day quality deferral)' -ForegroundColor Yellow
    Write-Host '  [3] Disabled  - Completely disable Windows Update' -ForegroundColor Red
    Write-Host ''

    do {
        $Profil = Read-Host '  Choice (1/2/3)'
    } while ($Profil -notin @('1','2','3'))
}

Remove-PackWindowsUpdateOverrides

switch ($Profil) {
    '1' {
        Write-Host ''
        Write-Host '  Profile [1] Default (WinUtil out-of-box settings)' -ForegroundColor Green
        Write-Host ''
        Invoke-WPFUpdatesdefault
        Restore-PackHiddenWindowsUpdateDrivers
        Repair-DeliveryOptimizationService
        Ensure-DeliveryOptimizationHttpOnly
    }

    '2' {
        Write-Host ''
        Write-Host '  Profile [2] Security (WinUtil recommended settings)' -ForegroundColor Yellow
        Write-Host ''
        # Start from WinUtil's default baseline so machines previously set to
        # Disabled in this pack do not keep stale services or scheduled tasks.
        Invoke-WPFUpdatesdefault
        Write-Host ''
        Invoke-WPFUpdatessecurity
        Repair-DeliveryOptimizationService
        Ensure-DeliveryOptimizationHttpOnly
        Ensure-WindowsUpdateStableOnly
        Ensure-WindowsUpdateDriverBlocking
        Hide-PendingWindowsUpdateDrivers
        Reset-WindowsUpdateUxStore
        Refresh-WindowsUpdateUiState
        Ensure-WindowsUpdateNoAutoReboot
    }

    '3' {
        Write-Host ''
        Write-Host '  Profile [3] Disabled (WinUtil disable-all profile)' -ForegroundColor Red
        Write-Host ''
        Invoke-WPFUpdatesdisable
        Ensure-DeliveryOptimizationHttpOnly
    }
}

Write-Host ''
