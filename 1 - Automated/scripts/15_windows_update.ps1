#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Update profile configuration

.DESCRIPTION
    Three profiles available (inspired by WinUtil / Chris Titus Tech):
      1 - Maximum  : all updates (security, quality, drivers, feature updates)
      2 - Security : security/quality updates only (no feature updates, no drivers via WU)
      3 - Disable  : completely disable Windows Update (services + policies)

    Profile 2 (Security) details:
      - Pins the current OS version via TargetReleaseVersion to prevent Windows from
        upgrading to the next feature release (e.g., 25H2 -> 26H1).
      - Disables driver updates through WU (SearchOrderConfig=0, PreventDeviceMetadataFromNetwork=1)
        to prevent Windows from replacing manually installed GPU/NIC/NVMe drivers with
        potentially older or generic inbox versions.
      - Sets AUOptions=3: Windows downloads updates automatically but prompts the user
        before installing, giving control over the install timing.
      - DisableWUfBSafeguards=1: Disables Windows Update for Business safeguard holds
        which sometimes block quality updates on machines with detected compatibility issues.

    Profile 3 (Disable) details:
      - WARNING: Completely disabled Windows Update leaves the system without security patches.
        This profile is appropriate only for isolated systems or short-term use.
      - Stops and disables wuauserv (Windows Update Agent) and UsoSvc (Update Session Orchestrator).
      - Sets DisableWindowsUpdateAccess=1 which blocks the Windows Update UI and API.

    Rollback: restore\15_windows_update.ps1 re-applies Profile 1 (Maximum = Windows defaults).

.PARAMETER Profil
    1, 2 or 3. If omitted, an interactive menu is shown.

.EXAMPLE
    .\15_windows_update.ps1 -Profil 2
    .\15_windows_update.ps1          # interactive menu
#>

param(
    [ValidateSet('1','2','3')]
    [string]$Profil
)

$ErrorActionPreference = 'Continue'

$WU_PATH    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$AU_PATH    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$DRV_META   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'
$DRV_SEARCH = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching'

# ── Interactive menu if -Profil not provided ───────────────────────────────────
if (-not $Profil) {
    Write-Host ""
    Write-Host "  WINDOWS UPDATE PROFILE" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Maximum  - All updates (security, quality, drivers, feature updates)" -ForegroundColor Green
    Write-Host "  [2] Security - Security/quality updates only (no feature updates, no drivers)" -ForegroundColor Yellow
    Write-Host "  [3] Disable  - Completely disable Windows Update" -ForegroundColor Red
    Write-Host ""
    do {
        $Profil = Read-Host "  Choice (1/2/3)"
    } while ($Profil -notin @('1','2','3'))
}

# ── Utility functions ──────────────────────────────────────────────────────────
function Set-RegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

function Set-ServiceDwordValue {
    param([string]$Path, [string]$Name, [int]$Value)
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Set-ServiceStartupTypeExact {
    param([string]$Name, [string]$StartupType)

    $s = Get-Service $Name -ErrorAction SilentlyContinue
    if (-not $s) { return $false }

    $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    switch ($StartupType) {
        'Disabled' {
            Stop-Service $Name -Force -ErrorAction SilentlyContinue
            Set-Service $Name -StartupType Disabled -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 4
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0
        }
        'Manual' {
            Set-Service $Name -StartupType Manual -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 3
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0
        }
        'Automatic' {
            Set-Service $Name -StartupType Automatic -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 2
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0
        }
        'AutomaticDelayedStart' {
            Set-Service $Name -StartupType Automatic -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 2
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 1
        }
        default {
            throw "Unsupported startup type: $StartupType"
        }
    }

    return $true
}

function Remove-WUPolicies {
    # Removes all restrictive WU policy keys, restoring Windows Update to its
    # out-of-box defaults. Called by Profile 1 to undo any previously applied
    # Profile 2 or 3 restrictions.
    Remove-Item -Path $WU_PATH    -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $DRV_META   -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $DRV_SEARCH -Name 'SearchOrderConfig' -Force -ErrorAction SilentlyContinue
}

function Enable-WUServices {
    # Ensures wuauserv (Windows Update Agent), UsoSvc (Update Session Orchestrator)
    # and BITS (Background Intelligent Transfer) are running and set to the correct
    # startup types. BITS is Manual (used by WU on demand) not Automatic.
    foreach ($item in @(
        @{ Name = 'wuauserv'; StartupType = 'Automatic'; StartNow = $true }
        @{ Name = 'UsoSvc';   StartupType = 'AutomaticDelayedStart'; StartNow = $true }
        @{ Name = 'BITS';     StartupType = 'Manual'; StartNow = $false }
    )) {
        if (Set-ServiceStartupTypeExact -Name $item.Name -StartupType $item.StartupType) {
            if ($item.StartNow) {
                Start-Service $item.Name -ErrorAction SilentlyContinue
            }
            Write-Host "    [SERVICE] $($item.Name) -> $($item.StartupType)"
        }
    }
}

function Disable-WUServices {
    # Stops and disables the two core Windows Update services.
    # BITS is left at Manual (it serves other consumers beyond WU).
    foreach ($svc in @('wuauserv','UsoSvc')) {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if ($s) {
            Stop-Service  $svc -Force -ErrorAction SilentlyContinue
            Set-Service   $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "    [SERVICE] $svc -> Disabled"
        }
    }
}

# ── Apply profile ──────────────────────────────────────────────────────────────
switch ($Profil) {

    '1' {
        Write-Host ""
        Write-Host "  Profile [1] Maximum - restoring Windows Update baseline" -ForegroundColor Green
        Write-Host ""

        # Remove all policy restrictions and re-enable the WU services.
        # This profile is effectively a "restore to defaults" for Windows Update.
        Remove-WUPolicies
        Enable-WUServices

        Write-Host "    [OK] All restrictive WU policies removed"
        Write-Host "    [OK] Full Windows Update re-enabled"
    }

    '2' {
        Write-Host ""
        Write-Host "  Profile [2] Security only" -ForegroundColor Yellow
        Write-Host ""

        # Read the current DisplayVersion (e.g., "25H2") to pin the release.
        # Falls back to the older ReleaseId property on pre-20H2 builds.
        $releaseId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
        if (-not $releaseId) {
            $releaseId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ReleaseId
        }

        # TargetReleaseVersion=1 + TargetReleaseVersionInfo=$releaseId:
        # Pins the OS to the current release, blocking automatic feature updates.
        # Windows will still install quality/security updates within this release.
        Set-RegValue $WU_PATH 'TargetReleaseVersion'     1            'DWord'
        Set-RegValue $WU_PATH 'TargetReleaseVersionInfo' $releaseId   'String'
        # DisableWUfBSafeguards=1: Disables safeguard holds that might block
        # quality updates on this machine due to detected app compatibility issues.
        Set-RegValue $WU_PATH 'DisableWUfBSafeguards'    1            'DWord'
        Write-Host "    [POLICY] Version pinned: $releaseId (no feature updates)"

        # Prevent WU from fetching driver packages from Windows Update servers.
        # PreventDeviceMetadataFromNetwork=1: Blocks device metadata (driver info) download.
        # SearchOrderConfig=0: Prevents the "search Windows Update for drivers" behavior
        # (also set in tweaks_consolidated.reg via 02_registry.ps1; applied here again
        # to ensure it is set regardless of the order scripts run in).
        Set-RegValue $DRV_META   'PreventDeviceMetadataFromNetwork' 1 'DWord'
        Set-RegValue $DRV_SEARCH 'SearchOrderConfig'                0 'DWord'
        Write-Host "    [POLICY] Driver updates via WU disabled"

        # AUOptions=3: Auto-download updates but prompt before installing.
        # This gives the user control over the install window (e.g., not during a gaming session).
        # AutoInstallMinorUpdates=1: Minor updates (patches, hotfixes) install silently without prompting.
        Set-RegValue $AU_PATH 'NoAutoUpdate'            0 'DWord'
        Set-RegValue $AU_PATH 'AUOptions'               3 'DWord'   # 3 = auto download, notify before install
        Set-RegValue $AU_PATH 'AutoInstallMinorUpdates' 1 'DWord'
        Write-Host "    [POLICY] Mode: auto download, notify before install"

        Enable-WUServices
        Write-Host "    [OK] Security profile applied"
    }

    '3' {
        Write-Host ""
        Write-Host "  Profile [3] Disable Windows Update" -ForegroundColor Red
        Write-Host "  WARNING: without security updates, the system is exposed." -ForegroundColor DarkRed
        Write-Host ""

        # DisableWindowsUpdateAccess=1: Blocks all access to the WU API and UI.
        # Any attempt to open Windows Update in Settings returns an error.
        Set-RegValue $WU_PATH 'DisableWindowsUpdateAccess' 1 'DWord'
        Set-RegValue $WU_PATH 'DisableWUfBSafeguards'      1 'DWord'
        Write-Host "    [POLICY] Windows Update access blocked"

        # NoAutoUpdate=1 + AUOptions=1: Belt-and-suspenders policy disable on
        # top of the service stop below, in case the services are re-enabled.
        Set-RegValue $AU_PATH 'NoAutoUpdate' 1 'DWord'
        Set-RegValue $AU_PATH 'AUOptions'    1 'DWord'   # 1 = never check
        Write-Host "    [POLICY] Automatic download disabled"

        Disable-WUServices
        Write-Host "    [OK] Windows Update completely disabled"
    }
}

Write-Host ""
