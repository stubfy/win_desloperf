#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Update profile configuration

.DESCRIPTION
    Three profiles available (inspired by WinUtil / Chris Titus Tech):
      1 - Maximum  : all updates (security, quality, drivers, feature updates)
      2 - Security : security/quality updates only (no feature updates, no drivers via WU)
      3 - Disable  : completely disable Windows Update (services + policies)

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

function Remove-WUPolicies {
    # Remove all restrictive WU policies
    Remove-Item -Path $WU_PATH    -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $DRV_META   -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $DRV_SEARCH -Name 'SearchOrderConfig' -Force -ErrorAction SilentlyContinue
}

function Enable-WUServices {
    foreach ($svc in @('wuauserv','UsoSvc','BITS')) {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service  $svc -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service $svc -ErrorAction SilentlyContinue
            Write-Host "    [SERVICE] $svc -> Automatic"
        }
    }
}

function Disable-WUServices {
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
        Write-Host "  Profile [1] Maximum - restoring Windows defaults" -ForegroundColor Green
        Write-Host ""

        Remove-WUPolicies
        Enable-WUServices

        Write-Host "    [OK] All restrictive WU policies removed"
        Write-Host "    [OK] Full Windows Update re-enabled"
    }

    '2' {
        Write-Host ""
        Write-Host "  Profile [2] Security only" -ForegroundColor Yellow
        Write-Host ""

        # Get current version to pin the release (blocks feature updates)
        $releaseId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
        if (-not $releaseId) {
            $releaseId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ReleaseId
        }

        # Pin current version (blocks feature updates)
        Set-RegValue $WU_PATH 'TargetReleaseVersion'     1            'DWord'
        Set-RegValue $WU_PATH 'TargetReleaseVersionInfo' $releaseId   'String'
        Set-RegValue $WU_PATH 'DisableWUfBSafeguards'    1            'DWord'
        Write-Host "    [POLICY] Version pinned: $releaseId (no feature updates)"

        # Disable driver updates via Windows Update
        Set-RegValue $DRV_META   'PreventDeviceMetadataFromNetwork' 1 'DWord'
        Set-RegValue $DRV_SEARCH 'SearchOrderConfig'                0 'DWord'
        Write-Host "    [POLICY] Driver updates via WU disabled"

        # Auto update: download and notify before install (conservative mode)
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

        # Block access to Windows Update
        Set-RegValue $WU_PATH 'DisableWindowsUpdateAccess' 1 'DWord'
        Set-RegValue $WU_PATH 'DisableWUfBSafeguards'      1 'DWord'
        Write-Host "    [POLICY] Windows Update access blocked"

        # Disable automatic downloads
        Set-RegValue $AU_PATH 'NoAutoUpdate' 1 'DWord'
        Set-RegValue $AU_PATH 'AUOptions'    1 'DWord'   # 1 = never
        Write-Host "    [POLICY] Automatic download disabled"

        Disable-WUServices
        Write-Host "    [OK] Windows Update completely disabled"
    }
}

Write-Host ""
