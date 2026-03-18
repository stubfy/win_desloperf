# restore\personal_settings.ps1 - Restore defaults for personal shell/theme preferences

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

function Get-SettingsPageVisibilityBackupFile {
    $automatedRoot = Split-Path (Split-Path $PSScriptRoot)
    $backupDir = Join-Path $automatedRoot 'backup'
    return Join-Path $backupDir 'personal_settings_settings_page_visibility.json'
}

function Get-VisibilityTokens {
    param(
        [AllowNull()]
        [string]$TokenString
    )

    if ([string]::IsNullOrWhiteSpace($TokenString)) {
        return @()
    }

    return @(
        $TokenString.Split(';') |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ } |
            Select-Object -Unique
    )
}

function Remove-EmptyExplorerPolicyKey {
    $policyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    if (-not (Test-Path $policyPath)) {
        return
    }

    $remainingValues = (Get-Item -Path $policyPath -ErrorAction SilentlyContinue).Property
    if (-not $remainingValues -or $remainingValues.Count -eq 0) {
        Remove-Item -Path $policyPath -Force -ErrorAction SilentlyContinue
    }
}

function Restore-SettingsHomeDefault {
    $policyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $backupFile = Get-SettingsPageVisibilityBackupFile

    if (Test-Path $backupFile) {
        try {
            $backup = Get-Content -Path $backupFile -Encoding UTF8 | ConvertFrom-Json
            if ($backup.Existed) {
                if (-not (Test-Path $policyPath)) {
                    New-Item -Path $policyPath -Force | Out-Null
                }

                Set-ItemProperty -Path $policyPath -Name 'SettingsPageVisibility' -Value ([string]$backup.Value) -Type String -Force | Out-Null
                Write-Host "    [SET] Settings page visibility restored from backup"
            } else {
                if (Test-Path $policyPath) {
                    Remove-ItemProperty -Path $policyPath -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue
                }

                Remove-EmptyExplorerPolicyKey
                Write-Host "    [SET] Settings Home restored to Windows default"
            }

            Remove-Item -Path $backupFile -Force -ErrorAction SilentlyContinue
            return
        } catch {
            Write-Host "    [WARN] Settings Home backup could not be read; falling back to token cleanup" -ForegroundColor Yellow
        }
    }

    if (-not (Test-Path $policyPath)) {
        Write-Host "    [SET] Settings Home already at Windows default"
        return
    }

    $currentValue = (Get-ItemProperty -Path $policyPath -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue).SettingsPageVisibility
    if ([string]::IsNullOrWhiteSpace($currentValue)) {
        Remove-ItemProperty -Path $policyPath -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue
        Remove-EmptyExplorerPolicyKey
        Write-Host "    [SET] Settings Home already at Windows default"
        return
    }

    if ($currentValue -match '^hide\s*:(?<Tokens>.*)$') {
        $tokens = @(Get-VisibilityTokens -TokenString $Matches.Tokens | Where-Object { $_ -ne 'home' })
        if ($tokens.Count -eq 0) {
            Remove-ItemProperty -Path $policyPath -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue
            Remove-EmptyExplorerPolicyKey
        } else {
            Set-ItemProperty -Path $policyPath -Name 'SettingsPageVisibility' -Value ('hide:' + ($tokens -join ';')) -Type String -Force | Out-Null
        }

        Write-Host "    [SET] Settings Home restored to Windows default"
        return
    }

    Write-Host "    [WARN] Existing Settings page policy was left unchanged (no backup found to restore it safely)" -ForegroundColor Yellow
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

function Warn-WallpaperOverrides {
    $wallpaperProcesses = Get-Process -Name 'wallpaper64', 'wallpaperservice32' -ErrorAction SilentlyContinue
    $wallpaperService = Get-Service -Name 'Wallpaper Engine Service' -ErrorAction SilentlyContinue

    if ($wallpaperProcesses -or ($wallpaperService -and $wallpaperService.Status -eq 'Running')) {
        Write-Host "    [WARN] Wallpaper Engine is running and may immediately override desktop background changes" -ForegroundColor Yellow
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
    $wallpapersPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers'
    $desktopPath = 'HKCU:\Control Panel\Desktop'

    Remove-Item -LiteralPath $transcodedWallpaper -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $cachedFilesPath -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $wallpapersPath)) {
        New-Item -Path $wallpapersPath -Force | Out-Null
    }

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
        Set-ItemProperty -Path $wallpapersPath -Name 'BackgroundType' -Value 1 -Type DWord
        Set-ItemProperty -Path $desktopPath -Name 'WallPaper' -Value ''
        Set-ItemProperty -Path $desktopPath -Name 'WallpaperStyle' -Value '0'
        Set-ItemProperty -Path $desktopPath -Name 'TileWallpaper' -Value '0'
    } else {
        Set-ItemProperty -Path $wallpapersPath -Name 'BackgroundType' -Value 0 -Type DWord
        Set-ItemProperty -Path $desktopPath -Name 'WallPaper' -Value $Path
        Set-ItemProperty -Path $desktopPath -Name 'WallpaperStyle' -Value '10'
        Set-ItemProperty -Path $desktopPath -Name 'TileWallpaper' -Value '0'
    }

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
Restore-SettingsHomeDefault
Refresh-UserPolicy
Warn-WallpaperOverrides
$defaultWallpaper = if (Test-Path "$env:SystemRoot\Web\Wallpaper\Windows\img0.jpg") {
    "$env:SystemRoot\Web\Wallpaper\Windows\img0.jpg"
} else {
    "$env:SystemRoot\Web\Wallpaper\Windows\img19.jpg"
}
Set-DesktopWallpaper -Path $defaultWallpaper
Refresh-UserShell
Write-Host "    [NOTE] Some taskbar/theme changes may fully apply after Explorer restart or reboot" -ForegroundColor DarkGray
