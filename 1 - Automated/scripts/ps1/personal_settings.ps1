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

function Get-SettingsPageVisibilityBackupFile {
    $automatedRoot = Split-Path (Split-Path $PSScriptRoot)
    $backupDir = Join-Path $automatedRoot 'backup'
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }

    return Join-Path $backupDir 'personal_settings_settings_page_visibility.json'
}

function Save-SettingsPageVisibilityBackup {
    param(
        [bool]$Existed,
        [AllowNull()]
        [string]$Value
    )

    $backupFile = Get-SettingsPageVisibilityBackupFile
    if (Test-Path $backupFile) {
        return
    }

    [PSCustomObject]@{
        Existed = $Existed
        Value   = $Value
    } | ConvertTo-Json | Set-Content -Path $backupFile -Encoding UTF8
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

function Set-SettingsHomeHidden {
    $policyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    if (-not (Test-Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }

    $currentValue = (Get-ItemProperty -Path $policyPath -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue).SettingsPageVisibility
    Save-SettingsPageVisibilityBackup -Existed (-not [string]::IsNullOrWhiteSpace($currentValue)) -Value $currentValue

    $newValue = $null
    if ([string]::IsNullOrWhiteSpace($currentValue)) {
        $newValue = 'hide:home'
    } elseif ($currentValue -match '^(?<Mode>hide|showonly)\s*:(?<Tokens>.*)$') {
        $mode = $Matches.Mode.ToLowerInvariant()
        $tokens = Get-VisibilityTokens -TokenString $Matches.Tokens

        if ($mode -eq 'hide') {
            if ($tokens -contains 'home') {
                Write-Host "    [SET] Settings Home already hidden"
                return
            }

            $newValue = 'hide:' + (($tokens + 'home') -join ';')
        } else {
            $visiblePages = @($tokens | Where-Object { $_ -ne 'home' })
            if ($visiblePages.Count -eq $tokens.Count) {
                Write-Host "    [SET] Settings Home already hidden by existing show-only policy"
                return
            }

            if ($visiblePages.Count -eq 0) {
                $newValue = 'hide:home'
                Write-Host "    [WARN] Existing Settings page policy only exposed Home; replaced with hide:home and saved the original value for restore" -ForegroundColor Yellow
            } else {
                $newValue = 'showonly:' + ($visiblePages -join ';')
            }
        }
    } else {
        $newValue = 'hide:home'
        Write-Host "    [WARN] Existing SettingsPageVisibility value was not recognized; replaced with hide:home and saved the original value for restore" -ForegroundColor Yellow
    }

    Set-ItemProperty -Path $policyPath -Name 'SettingsPageVisibility' -Value $newValue -Type String -Force | Out-Null
    Write-Host "    [SET] Settings Home hidden"
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
    $colorsPath = 'HKCU:\Control Panel\Colors'

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
        Set-ItemProperty -Path $colorsPath -Name 'Background' -Value '0 0 0'
        [int[]]$desktopElement = 1   # COLOR_DESKTOP
        [int[]]$blackColor     = 0   # RGB(0,0,0)
        [WinDeslopper.WallpaperNativeMethods]::SetSysColors(1, $desktopElement, $blackColor) | Out-Null
    } else {
        Set-ItemProperty -Path $wallpapersPath -Name 'BackgroundType' -Value 0 -Type DWord
        Set-ItemProperty -Path $desktopPath -Name 'WallPaper' -Value $Path
        Set-ItemProperty -Path $desktopPath -Name 'WallpaperStyle' -Value '10'
        Set-ItemProperty -Path $desktopPath -Name 'TileWallpaper' -Value '0'
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
Set-SettingsHomeHidden
Refresh-UserPolicy
Warn-WallpaperOverrides
Set-DesktopWallpaper -Path ''
Refresh-UserShell
Write-Host "    [NOTE] Some taskbar/theme changes may fully apply after Explorer restart or reboot" -ForegroundColor DarkGray
