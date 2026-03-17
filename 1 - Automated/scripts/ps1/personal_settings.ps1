# personal_settings.ps1 - Subjective shell/theme preferences
# Keeps user-specific UI taste separate from optimization/privacy tweaks.

$REG = Join-Path $PSScriptRoot "personal_settings.reg"

if (-not (Test-Path $REG)) {
    Write-Host "    [ERROR] personal_settings.reg not found: $REG"
    exit 1
}

$result = Start-Process regedit.exe -ArgumentList "/s `"$REG`"" -Wait -PassThru
if ($result.ExitCode -eq 0) {
    Write-Host "    [OK] personal_settings.reg imported"
} else {
    Write-Host "    [WARN] regedit exit code: $($result.ExitCode)"
}

function Disable-AutoDndRules {
    # Windows 11 stores automatic Do Not Disturb rules (game, fullscreen, display
    # duplication, post-update, scheduled) as binary blobs in CloudStore.
    # Blob layout: 43 42 01 00 | 0A 02 [enabled] 00 | 2A 2A 00 00 00
    #              header       field1  0=off 1=on     field5 (no profile data)
    # Using 0x00 at the enabled byte explicitly disables the rule in the Settings UI.
    $disabled = [byte[]](0x43,0x42,0x01,0x00,0x0A,0x02,0x00,0x00,0x2A,0x2A,0x00,0x00,0x00)

    $base = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\" +
            "default`$windows.data.donotdisturb.quietmoment`$quietmomentlist"

    $moments = @(
        'quietmomentgame'          # When playing a game
        'quietmomentpresentation'  # When duplicating your display
        'quietmomentfullscreen'    # When using an app in full-screen mode
        'quietmomentpostoobe'      # For the first hour after a Windows feature update
        'quietmomentscheduled'     # During these times
    )

    $ok = 0
    foreach ($m in $moments) {
        $path = "$base\windows.data.donotdisturb.quietmoment`$$m"
        try {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -Force | Out-Null
            }
            Set-ItemProperty -Path $path -Name 'Data' -Value $disabled -Type Binary -Force
            $ok++
        } catch {
            Write-Host "    [WARN] Failed to disable $m : $_"
        }
    }

    # Restart WpnUserService so the new blobs take effect immediately
    try {
        Get-Service WpnUserService_* | Restart-Service -Force -ErrorAction Stop
        Write-Host "    [OK] Automatic Do Not Disturb rules disabled ($ok/5 rules, WpnUserService restarted)"
    } catch {
        Write-Host "    [OK] Automatic Do Not Disturb rules disabled ($ok/5 rules)"
        Write-Host "    [WARN] Could not restart WpnUserService: $_ -- changes apply after reboot"
    }

    # Clean up legacy QuietHours policy (no longer needed)
    $legacyPath = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\QuietHours'
    if (Test-Path $legacyPath) {
        Remove-Item -Path $legacyPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Set-ClassicAltTab {
    $explorerPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
    if (-not (Test-Path $explorerPath)) {
        New-Item -Path $explorerPath -Force | Out-Null
    }

    New-ItemProperty -Path $explorerPath -Name 'AltTabSettings' -PropertyType DWord -Value 1 -Force | Out-Null

    $policyPath = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    if (Test-Path $policyPath) {
        Remove-ItemProperty -Path $policyPath -Name 'MultiTaskingAltTabFilter' -ErrorAction SilentlyContinue
        $remainingValues = (Get-Item -Path $policyPath -ErrorAction SilentlyContinue).Property
        if (-not $remainingValues -or $remainingValues.Count -eq 0) {
            Remove-Item -Path $policyPath -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "    [SET] Classic Alt+Tab enabled"
}

function Refresh-UserPolicy {
    $result = Start-Process -FilePath "$env:SystemRoot\System32\gpupdate.exe" `
        -ArgumentList '/target:user /force' `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    if ($result.ExitCode -eq 0) {
        Write-Host "    [SET] User policy refreshed"
    } else {
        Write-Host "    [WARN] gpupdate exit code: $($result.ExitCode)"
    }
}

function Set-DesktopWallpaper {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path
    )

    if (-not ('WinDeslopper.WallpaperNativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WinDeslopper {
    public static class WallpaperNativeMethods {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetSysColors(int cElements, int[] lpaElements, int[] lpaRgbValues);
    }
}
'@
    }

    $themePath = Join-Path $env:APPDATA 'Microsoft\Windows\Themes'
    $cachedFilesPath = Join-Path $themePath 'CachedFiles'
    $transcodedWallpaper = Join-Path $themePath 'TranscodedWallpaper'

    Remove-Item -LiteralPath $transcodedWallpaper -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $cachedFilesPath -Recurse -Force -ErrorAction SilentlyContinue

    [uint32]$SPI_SETDESKWALLPAPER = 0x0014
    [uint32]$SPIF_UPDATEINIFILE   = 0x0001
    [uint32]$SPIF_SENDCHANGE      = 0x0002

    [WinDeslopper.WallpaperNativeMethods]::SystemParametersInfo(
        $SPI_SETDESKWALLPAPER,
        0,
        $Path,
        $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE
    ) | Out-Null

    if ([string]::IsNullOrEmpty($Path)) {
        [int[]]$desktopElement = 1   # COLOR_DESKTOP
        [int[]]$blackColor     = 0   # RGB(0,0,0)
        [WinDeslopper.WallpaperNativeMethods]::SetSysColors(1, $desktopElement, $blackColor) | Out-Null
    }

    Write-Host "    [SET] Desktop background forced to solid black"
}

function Refresh-UserShell {
    Start-Process -FilePath "$env:SystemRoot\System32\rundll32.exe" `
        -ArgumentList 'user32.dll,UpdatePerUserSystemParameters' `
        -WindowStyle Hidden `
        -Wait
    Write-Host "    [SET] User shell parameters refreshed"
}

Set-ClassicAltTab
Disable-AutoDndRules
Refresh-UserPolicy
Set-DesktopWallpaper -Path ''
Refresh-UserShell
Write-Host "    [NOTE] Some taskbar/theme changes may fully apply after Explorer restart or reboot" -ForegroundColor DarkGray
