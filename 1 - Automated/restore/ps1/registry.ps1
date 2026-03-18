# restore\registry.ps1 - Restore registry keys modified by opti pack

$RESTORE_DIR = $PSScriptRoot
$BACKUP_DIR  = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "backup"
$defaultsReg = Join-Path $RESTORE_DIR "tweaks_defaults.reg"

# Step 1: Apply Windows default values (reverse of tweaks_consolidated.reg)
if (Test-Path $defaultsReg) {
    Start-Process "regedit.exe" -ArgumentList "/s `"$defaultsReg`"" -Wait -Verb RunAs
    Write-Host "    Default values applied from tweaks_defaults.reg"
} else {
    Write-Host "    tweaks_defaults.reg not found." -ForegroundColor Yellow
}

# Step 2: Override with pre-tweak backup exports (if available)
if (Test-Path $BACKUP_DIR) {
    $regFiles = Get-ChildItem "$BACKUP_DIR\backup_*.reg" -ErrorAction SilentlyContinue
    foreach ($regFile in $regFiles) {
        Start-Process "regedit.exe" -ArgumentList "/s `"$($regFile.FullName)`"" -Wait -Verb RunAs
        Write-Host "    Backup restored: $($regFile.Name)"
    }
} else {
    Write-Host "    No backup folder found. Only default values were applied." -ForegroundColor Gray
}

Write-Host ""
Write-Host "    If the system has issues, use the system restore point:" -ForegroundColor Gray
Write-Host "    Control Panel > System > System Protection > System Restore" -ForegroundColor Gray

# === SECTION: Visual effects SPI restore ===

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

        [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
        public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
    }
}
"@
}

$SPI_SETDRAGFULLWINDOWS     = 0x0025
$SPI_SETSTICKYKEYS          = 0x003B
$SPI_SETANIMATION           = 0x0049
$SPI_SETMENUANIMATION       = 0x1003
$SPI_SETTOOLTIPANIMATION    = 0x1017
$SPI_SETSELECTIONFADE       = 0x1015
$SPI_SETCURSORSHADOW        = 0x101B
$SPI_SETDROPSHADOW          = 0x1025
$SPI_SETCOMBOBOXANIMATION   = 0x1005
$SPI_SETLISTBOXSMOOTHSCROLLING = 0x1007
$SPI_SETFONTSMOOTHING       = 0x004B
$SPI_SETCLIENTAREAANIMATION = 0x1043
$SPIF_SENDCHANGE            = 0x02
$SPIF_UPDATEINIFILE         = 0x01
$SPI_FLAGS                  = $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE
$SKF_DEFAULT_OFF            = 0x000001FE

function Invoke-SpiPvBool {
    param(
        [uint32]$Action,
        [bool]$Enabled,
        [string]$Label
    )

    $ok = [WinDeslopper.NativeMethods]::SystemParametersInfo(
        $Action,
        0,
        [IntPtr]([int]$Enabled),
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

function Restore-StickyKeysDefaults {
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
        Write-Host "    [SET] Sticky Keys restored to default off"
    } else {
        Write-Host "    [WARN] Unable to restore Sticky Keys defaults" -ForegroundColor Yellow
    }
}

function Restore-VisualEffectsDefaults {
    $desktop = 'HKCU:\Control Panel\Desktop'
    $metrics = 'HKCU:\Control Panel\Desktop\WindowMetrics'

    if (-not (Test-Path $desktop)) { New-Item -Path $desktop -Force | Out-Null }
    if (-not (Test-Path $metrics)) { New-Item -Path $metrics -Force | Out-Null }

    New-ItemProperty -Path $desktop -Name DragFullWindows -PropertyType String -Value '1' -Force | Out-Null
    New-ItemProperty -Path $desktop -Name FontSmoothing -PropertyType String -Value '2' -Force | Out-Null
    New-ItemProperty -Path $metrics -Name MinAnimate -PropertyType String -Value '1' -Force | Out-Null

    Invoke-SpiPvBool -Action $SPI_SETCLIENTAREAANIMATION -Enabled $true -Label 'Visual Effects: animate controls and elements inside windows = on'
    Invoke-SpiPvBool -Action $SPI_SETMENUANIMATION -Enabled $true -Label 'Visual Effects: fade or slide menus into view = on'
    Invoke-SpiPvBool -Action $SPI_SETTOOLTIPANIMATION -Enabled $true -Label 'Visual Effects: fade or slide ToolTips into view = on'
    Invoke-SpiPvBool -Action $SPI_SETSELECTIONFADE -Enabled $true -Label 'Visual Effects: fade out menu items after clicking = on'
    Invoke-SpiPvBool -Action $SPI_SETCURSORSHADOW -Enabled $true -Label 'Visual Effects: show shadows under mouse pointer = on'
    Invoke-SpiPvBool -Action $SPI_SETDROPSHADOW -Enabled $true -Label 'Visual Effects: show shadows under windows = on'
    Invoke-SpiPvBool -Action $SPI_SETCOMBOBOXANIMATION -Enabled $true -Label 'Visual Effects: slide open combo boxes = on'
    Invoke-SpiPvBool -Action $SPI_SETLISTBOXSMOOTHSCROLLING -Enabled $true -Label 'Visual Effects: smooth-scroll list boxes = on'
    Invoke-SpiAltBool -Action $SPI_SETDRAGFULLWINDOWS -Enabled $true -Label 'Visual Effects: show window contents while dragging = on'
    Invoke-SpiAltBool -Action $SPI_SETFONTSMOOTHING -Enabled $true -Label 'Visual Effects: smooth edges of screen fonts = on'

    $anim = New-Object WinDeslopper.ANIMATIONINFO
    $anim.cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type]([WinDeslopper.ANIMATIONINFO]))
    $anim.iMinAnimate = 1
    $ok = [WinDeslopper.NativeMethods]::SystemParametersInfo(
        $SPI_SETANIMATION,
        $anim.cbSize,
        [ref]$anim,
        [uint32]$SPI_FLAGS
    )

    if ($ok) {
        Write-Host "    [SET] Visual Effects: minimize/maximize animations = on"
    } else {
        Write-Host "    [WARN] Unable to restore minimize/maximize animations" -ForegroundColor Yellow
    }
}

function Refresh-UserShell {
    Start-Process -FilePath "$env:SystemRoot\System32\rundll32.exe" `
        -ArgumentList 'user32.dll,UpdatePerUserSystemParameters' `
        -WindowStyle Hidden `
        -Wait
    Write-Host "    [SET] User shell parameters refreshed"
}

Restore-StickyKeysDefaults
Restore-VisualEffectsDefaults
Refresh-UserShell

# wscsvc is restored automatically via restore\services.ps1 (JSON backup)

# === SECTION: Restore mouse acceleration ===

$mouseDefaultReg = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "scripts\ps1\mouse_fix\Windows_10+8.x_Default.reg"

if (-not (Test-Path $mouseDefaultReg)) {
    Write-Host "    [ERROR] Default mouse reg not found: $mouseDefaultReg" -ForegroundColor Red
} else {
    $result = Start-Process regedit.exe -ArgumentList "/s `"$mouseDefaultReg`"" -Wait -PassThru
    if ($result.ExitCode -eq 0) {
        Write-Host "    [OK] Mouse acceleration curves restored to Windows default"
    } else {
        Write-Host "    [WARN] regedit exit code: $($result.ExitCode)"
    }
}
