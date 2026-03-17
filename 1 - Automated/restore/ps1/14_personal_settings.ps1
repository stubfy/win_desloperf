# restore\14_personal_settings.ps1 - Restore defaults for personal shell/theme preferences

$REG = Join-Path $PSScriptRoot "personal_settings_defaults.reg"

if (-not (Test-Path $REG)) {
    Write-Host "    [ERROR] personal_settings_defaults.reg not found: $REG"
    exit 1
}

$result = Start-Process regedit.exe -ArgumentList "/s `"$REG`"" -Wait -PassThru
if ($result.ExitCode -eq 0) {
    Write-Host "    [OK] personal_settings_defaults.reg imported"
} else {
    Write-Host "    [WARN] regedit exit code: $($result.ExitCode)"
}

function Restore-AutoDndRules {
    # Restore Windows 11 default automatic DND rules (all enabled except scheduled).
    # Each blob is the factory-default binary from CloudStore.
    $base = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\" +
            "default`$windows.data.donotdisturb.quietmoment`$quietmomentlist"

    # Default enabled blobs captured from a clean Windows 11 25H2 install.
    # game & postoobe use PriorityOnly profile; presentation & fullscreen use AlarmsOnly.
    $enabledPriorityOnly = [byte[]](
        0x43,0x42,0x01,0x00,0x0A,0x02,0x01,0x00,0x2A,0x06,0x00,0x00,0x00,0x00,0x00,
        0x2A,0x2B,0x0E,0x5E,0x43,0x42,0x01,0x00,0xC2,0x0A,0x01,0xD2,0x1E,0x28,
        0x4D,0x00,0x69,0x00,0x63,0x00,0x72,0x00,0x6F,0x00,0x73,0x00,0x6F,0x00,
        0x66,0x00,0x74,0x00,0x2E,0x00,0x51,0x00,0x75,0x00,0x69,0x00,0x65,0x00,
        0x74,0x00,0x48,0x00,0x6F,0x00,0x75,0x00,0x72,0x00,0x73,0x00,0x50,0x00,
        0x72,0x00,0x6F,0x00,0x66,0x00,0x69,0x00,0x6C,0x00,0x65,0x00,0x2E,0x00,
        0x50,0x00,0x72,0x00,0x69,0x00,0x6F,0x00,0x72,0x00,0x69,0x00,0x74,0x00,
        0x79,0x00,0x4F,0x00,0x6E,0x00,0x6C,0x00,0x79,0x00,0xCA,0x50,0x00,0x00,
        0x00,0x00,0x00
    )
    $enabledAlarmsOnly = [byte[]](
        0x43,0x42,0x01,0x00,0x0A,0x02,0x01,0x00,0x2A,0x06,0x00,0x00,0x00,0x00,0x00,
        0x2A,0x2B,0x0E,0x5A,0x43,0x42,0x01,0x00,0xC2,0x0A,0x01,0xD2,0x1E,0x26,
        0x4D,0x00,0x69,0x00,0x63,0x00,0x72,0x00,0x6F,0x00,0x73,0x00,0x6F,0x00,
        0x66,0x00,0x74,0x00,0x2E,0x00,0x51,0x00,0x75,0x00,0x69,0x00,0x65,0x00,
        0x74,0x00,0x48,0x00,0x6F,0x00,0x75,0x00,0x72,0x00,0x73,0x00,0x50,0x00,
        0x72,0x00,0x6F,0x00,0x66,0x00,0x69,0x00,0x6C,0x00,0x65,0x00,0x2E,0x00,
        0x41,0x00,0x6C,0x00,0x61,0x00,0x72,0x00,0x6D,0x00,0x73,0x00,0x4F,0x00,
        0x6E,0x00,0x6C,0x00,0x79,0x00,0xCA,0x50,0x00,0x00,0x00,0x00,0x00
    )
    $disabled = [byte[]](0x43,0x42,0x01,0x00,0x0A,0x02,0x01,0x00,0x2A,0x2A,0x00,0x00,0x00)

    $rules = @{
        'quietmomentgame'         = $enabledPriorityOnly
        'quietmomentpresentation' = $enabledAlarmsOnly
        'quietmomentfullscreen'   = $enabledAlarmsOnly
        'quietmomentpostoobe'     = $enabledPriorityOnly
        'quietmomentscheduled'    = $disabled  # Disabled by default on clean install
    }

    $ok = 0
    foreach ($entry in $rules.GetEnumerator()) {
        $path = "$base\windows.data.donotdisturb.quietmoment`$$($entry.Key)"
        try {
            if (-not (Test-Path $path)) {
                New-Item -Path $path -Force | Out-Null
            }
            Set-ItemProperty -Path $path -Name 'Data' -Value $entry.Value -Type Binary -Force
            $ok++
        } catch {
            Write-Host "    [WARN] Failed to restore $($entry.Key) : $_"
        }
    }

    try {
        Get-Service WpnUserService_* | Restart-Service -Force -ErrorAction Stop
        Write-Host "    [OK] Automatic Do Not Disturb rules restored to Windows defaults ($ok/5 rules, WpnUserService restarted)"
    } catch {
        Write-Host "    [OK] Automatic Do Not Disturb rules restored to Windows defaults ($ok/5 rules)"
        Write-Host "    [WARN] Could not restart WpnUserService: $_ -- changes apply after reboot"
    }

    # Clean up legacy QuietHours policy if present
    $legacyPath = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\QuietHours'
    if (Test-Path $legacyPath) {
        Remove-Item -Path $legacyPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Restore-AltTabDefault {
    $explorerPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
    if (Test-Path $explorerPath) {
        Remove-ItemProperty -Path $explorerPath -Name 'AltTabSettings' -ErrorAction SilentlyContinue
    }

    $policyPath = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    if (Test-Path $policyPath) {
        Remove-ItemProperty -Path $policyPath -Name 'MultiTaskingAltTabFilter' -ErrorAction SilentlyContinue
        $remainingValues = (Get-Item -Path $policyPath -ErrorAction SilentlyContinue).Property
        if (-not $remainingValues -or $remainingValues.Count -eq 0) {
            Remove-Item -Path $policyPath -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "    [SET] Alt+Tab restored to Windows default"
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

    Write-Host "    [SET] Desktop wallpaper restored"
}

function Refresh-UserShell {
    Start-Process -FilePath "$env:SystemRoot\System32\rundll32.exe" `
        -ArgumentList 'user32.dll,UpdatePerUserSystemParameters' `
        -WindowStyle Hidden `
        -Wait
    Write-Host "    [SET] User shell parameters refreshed"
}

Restore-AltTabDefault
Restore-AutoDndRules
Refresh-UserPolicy
$defaultWallpaper = if (Test-Path "$env:SystemRoot\Web\Wallpaper\Windows\img0.jpg") {
    "$env:SystemRoot\Web\Wallpaper\Windows\img0.jpg"
} else {
    "$env:SystemRoot\Web\Wallpaper\Windows\img19.jpg"
}
Set-DesktopWallpaper -Path $defaultWallpaper
Refresh-UserShell
Write-Host "    [NOTE] Some taskbar/theme changes may fully apply after Explorer restart or reboot" -ForegroundColor DarkGray
