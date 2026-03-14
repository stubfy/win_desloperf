# 16_uwt.ps1 - Registry tweaks equivalent to Ultimate Windows Tweaker 5 (settings_v2.ini)
# Covers: Explorer appearance, performance, UAC, privacy, context menu cleanup
# Also applies the remaining deterministic Control Panel user settings.

$REG = Join-Path $PSScriptRoot "uwt_tweaks.reg"

if (-not (Test-Path $REG)) {
    Write-Host "    [ERROR] uwt_tweaks.reg not found: $REG"
    exit 1
}

$result = Start-Process regedit.exe -ArgumentList "/s `"$REG`"" -Wait -PassThru
if ($result.ExitCode -eq 0) {
    Write-Host "    [OK] uwt_tweaks.reg imported"
} else {
    Write-Host "    [WARN] regedit exit code: $($result.ExitCode)"
}

if (-not ('WinDeslopper.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinDeslopper {
    [StructLayout(LayoutKind.Sequential)]
    public struct STICKYKEYS {
        public uint cbSize;
        public uint dwFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct ANIMATIONINFO {
        public uint cbSize;
        public int iMinAnimate;
    }

    public static class NativeMethods {
        [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
        public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref STICKYKEYS pvParam, uint fWinIni);

        [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
        public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref ANIMATIONINFO pvParam, uint fWinIni);

        [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto, EntryPoint="SystemParametersInfo")]
        public static extern bool SystemParametersInfoBoolRef(uint uiAction, uint uiParam, ref bool pvParam, uint fWinIni);

        [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
        public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
    }
}
"@
}

$SPI_SETDRAGFULLWINDOWS    = 0x0025
$SPI_SETSTICKYKEYS         = 0x003B
$SPI_SETANIMATION          = 0x0049
$SPI_SETMENUANIMATION      = 0x1003
$SPI_SETTOOLTIPANIMATION   = 0x1017
$SPI_SETSELECTIONFADE      = 0x1015
$SPI_SETCURSORSHADOW       = 0x101B
$SPI_SETDROPSHADOW         = 0x1025
$SPI_SETCOMBOBOXANIMATION  = 0x1005
$SPI_SETLISTBOXSMOOTHSCROLLING = 0x1007
$SPI_SETFONTSMOOTHING      = 0x004B
$SPI_SETCLIENTAREAANIMATION= 0x1043
$SPIF_SENDCHANGE           = 0x02
$SPIF_UPDATEINIFILE        = 0x01
$SPI_FLAGS                 = $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE
$SKF_DEFAULT_OFF           = 0x000001FE

function Invoke-SpiBoolRef {
    param(
        [uint32]$Action,
        [bool]$Enabled,
        [string]$Label
    )

    $value = $Enabled
    $ok = [WinDeslopper.NativeMethods]::SystemParametersInfoBoolRef(
        $Action,
        0,
        [ref]$value,
        [uint32]$SPI_FLAGS
    )

    if ($ok) {
        Write-Host "    [SET] $Label"
    } else {
        Write-Host "    [WARN] Unable to set $Label" -ForegroundColor Yellow
    }
}

function Invoke-SpiAltBool {
    param(
        [uint32]$Action,
        [bool]$Enabled,
        [string]$Label
    )

    $ok = [WinDeslopper.NativeMethods]::SystemParametersInfo(
        $Action,
        [uint32]([int]$Enabled),
        [IntPtr]::Zero,
        [uint32]$SPI_FLAGS
    )

    if ($ok) {
        Write-Host "    [SET] $Label"
    } else {
        Write-Host "    [WARN] Unable to set $Label" -ForegroundColor Yellow
    }
}

function Set-StickyKeysDefaultOff {
    $key = 'HKCU:\Control Panel\Accessibility\StickyKeys'
    if (-not (Test-Path $key)) {
        New-Item -Path $key -Force | Out-Null
    }

    New-ItemProperty -Path $key -Name Flags -PropertyType String -Value '510' -Force | Out-Null

    $sticky = New-Object WinDeslopper.STICKYKEYS
    $sticky.cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type]([WinDeslopper.STICKYKEYS]))
    $sticky.dwFlags = $SKF_DEFAULT_OFF
    $ok = [WinDeslopper.NativeMethods]::SystemParametersInfo(
        $SPI_SETSTICKYKEYS,
        0,
        [ref]$sticky,
        [uint32]$SPI_FLAGS
    )

    if ($ok) {
        Write-Host "    [SET] Sticky Keys disabled"
    } else {
        Write-Host "    [WARN] Unable to disable Sticky Keys" -ForegroundColor Yellow
    }
}

function Set-VisualEffectsPreset {
    $desktop = 'HKCU:\Control Panel\Desktop'
    $metrics = 'HKCU:\Control Panel\Desktop\WindowMetrics'

    if (-not (Test-Path $desktop)) { New-Item -Path $desktop -Force | Out-Null }
    if (-not (Test-Path $metrics)) { New-Item -Path $metrics -Force | Out-Null }

    New-ItemProperty -Path $desktop -Name DragFullWindows -PropertyType String -Value '1' -Force | Out-Null
    New-ItemProperty -Path $desktop -Name FontSmoothing -PropertyType String -Value '2' -Force | Out-Null
    New-ItemProperty -Path $metrics -Name MinAnimate -PropertyType String -Value '0' -Force | Out-Null

    Invoke-SpiBoolRef -Action $SPI_SETCLIENTAREAANIMATION -Enabled $true -Label 'Visual Effects: animate controls and elements inside windows = on'
    Invoke-SpiBoolRef -Action $SPI_SETMENUANIMATION -Enabled $false -Label 'Visual Effects: fade or slide menus into view = off'
    Invoke-SpiBoolRef -Action $SPI_SETTOOLTIPANIMATION -Enabled $false -Label 'Visual Effects: fade or slide ToolTips into view = off'
    Invoke-SpiBoolRef -Action $SPI_SETSELECTIONFADE -Enabled $false -Label 'Visual Effects: fade out menu items after clicking = off'
    Invoke-SpiBoolRef -Action $SPI_SETCURSORSHADOW -Enabled $false -Label 'Visual Effects: show shadows under mouse pointer = off'
    Invoke-SpiBoolRef -Action $SPI_SETDROPSHADOW -Enabled $false -Label 'Visual Effects: show shadows under windows = off'
    Invoke-SpiBoolRef -Action $SPI_SETCOMBOBOXANIMATION -Enabled $false -Label 'Visual Effects: slide open combo boxes = off'
    Invoke-SpiBoolRef -Action $SPI_SETLISTBOXSMOOTHSCROLLING -Enabled $false -Label 'Visual Effects: smooth-scroll list boxes = off'
    Invoke-SpiAltBool -Action $SPI_SETDRAGFULLWINDOWS -Enabled $true -Label 'Visual Effects: show window contents while dragging = on'
    Invoke-SpiAltBool -Action $SPI_SETFONTSMOOTHING -Enabled $true -Label 'Visual Effects: smooth edges of screen fonts = on'

    $anim = New-Object WinDeslopper.ANIMATIONINFO
    $anim.cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type]([WinDeslopper.ANIMATIONINFO]))
    $anim.iMinAnimate = 0
    $ok = [WinDeslopper.NativeMethods]::SystemParametersInfo(
        $SPI_SETANIMATION,
        $anim.cbSize,
        [ref]$anim,
        [uint32]$SPI_FLAGS
    )

    if ($ok) {
        Write-Host "    [SET] Visual Effects: minimize/maximize animations = off"
    } else {
        Write-Host "    [WARN] Unable to disable minimize/maximize animations" -ForegroundColor Yellow
    }
}

function Disable-Magnifier {
    $key = 'HKCU:\Software\Microsoft\ScreenMagnifier'
    if (-not (Test-Path $key)) {
        New-Item -Path $key -Force | Out-Null
    }

    New-ItemProperty -Path $key -Name RunningState -PropertyType DWord -Value 0 -Force | Out-Null
    Get-Process -Name Magnify -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "    [SET] Magnifier disabled"
}

function Refresh-UserShell {
    Start-Process -FilePath "$env:SystemRoot\System32\rundll32.exe" `
        -ArgumentList 'user32.dll,UpdatePerUserSystemParameters' `
        -WindowStyle Hidden `
        -Wait
    Write-Host "    [SET] User shell parameters refreshed"
}

Set-StickyKeysDefaultOff
Set-VisualEffectsPreset
Disable-Magnifier
Refresh-UserShell

# --- Disable Windows Security Center service (not in 03_services.ps1) ---
$svc = Get-Service 'wscsvc' -ErrorAction SilentlyContinue
if ($svc) {
    Stop-Service  'wscsvc' -Force -ErrorAction SilentlyContinue
    Set-Service   'wscsvc' -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "    [DISABLED]   wscsvc (Windows Security Center)"
} else {
    Write-Host "    [NOT FOUND]  wscsvc" -ForegroundColor Gray
}
