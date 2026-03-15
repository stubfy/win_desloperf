# 16_uwt.ps1 - Registry tweaks equivalent to Ultimate Windows Tweaker 5 (settings_v2.ini)
# Covers: privacy, context menu cleanup, security/UI defaults, visual effects preset
# Purely subjective shell/theme preferences live in 20_personal_settings.ps1.
# Also applies the remaining deterministic Control Panel user settings.
#
# Two-layer approach for visual effects:
#   1. uwt_tweaks.reg (imported first): writes the backing registry values that
#      persist across reboots and new logon sessions.
#   2. SystemParametersInfo (SPI) P/Invoke calls below: apply the same settings
#      to the live session immediately without requiring a logoff/reboot.
#   Both layers are needed: the registry alone requires a logoff to take effect;
#   SPI alone is lost at next logon. The combination gives immediate results and
#   persistent behavior.
#
# SPI calling conventions used here:
#   Invoke-SpiPvBool: For SPI flags that pass a BOOL directly as pvParam (not a pointer).
#     Signature: SystemParametersInfo(uiAction, 0, (IntPtr)(int)boolValue, flags)
#     Used for: menu/tooltip/selection fade animations, cursor shadow, drop shadow,
#               combo box animation, list box scrolling, client area animations.
#   Invoke-SpiAltBool: For SPI flags that use uiParam as the boolean (not pvParam).
#     Signature: SystemParametersInfo(uiAction, (uint)boolValue, IntPtr.Zero, flags)
#     Used for: drag full windows, font smoothing.
#   ANIMATIONINFO struct: For SPI_SETANIMATION which requires a pointer to a struct.
#     iMinAnimate=0 disables minimize/maximize window animation.
#   STICKYKEYS struct: For SPI_SETSTICKYKEYS which configures the Sticky Keys feature.
#
# SPIF flags: SPIF_UPDATEINIFILE (0x01) persists the change to the user profile.
#             SPIF_SENDCHANGE (0x02) broadcasts WM_SETTINGCHANGE to running processes.
#             Both are ORed together (0x03) so running applications update immediately.

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

        [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
        public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
    }
}
"@
}

# SPI action codes (from winuser.h)
$SPI_SETDRAGFULLWINDOWS    = 0x0025  # Show window contents while dragging
$SPI_SETSTICKYKEYS         = 0x003B  # Configure Sticky Keys
$SPI_SETANIMATION          = 0x0049  # Minimize/maximize animation (ANIMATIONINFO)
$SPI_SETMENUANIMATION      = 0x1003  # Fade/slide menus into view
$SPI_SETTOOLTIPANIMATION   = 0x1017  # Fade/slide tooltips into view
$SPI_SETSELECTIONFADE      = 0x1015  # Fade out menu items after clicking
$SPI_SETCURSORSHADOW       = 0x101B  # Shadow under the mouse pointer
$SPI_SETDROPSHADOW         = 0x1025  # Shadow under windows
$SPI_SETCOMBOBOXANIMATION  = 0x1005  # Slide-open combo box animation
$SPI_SETLISTBOXSMOOTHSCROLLING = 0x1007 # Smooth scroll in list boxes
$SPI_SETFONTSMOOTHING      = 0x004B  # ClearType / font antialiasing
$SPI_SETCLIENTAREAANIMATION= 0x1043  # Animate controls and elements inside windows
$SPIF_SENDCHANGE           = 0x02    # Broadcast WM_SETTINGCHANGE to all windows
$SPIF_UPDATEINIFILE        = 0x01    # Persist the change to the user profile
$SPI_FLAGS                 = $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE
# Sticky Keys default-off flags: disable the shortcut (Shift x5 = 0x0002)
# and set Sticky Keys to off by default. 0x000001FE = all default flags with
# SKF_STICKYKEYSON (0x0001) cleared.
$SKF_DEFAULT_OFF           = 0x000001FE

function Invoke-SpiPvBool {
    param(
        [uint32]$Action,
        [bool]$Enabled,
        [string]$Label
    )

    # These SPI_SET* flags expect a BOOL value cast to pvParam, not a pointer to BOOL.
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

    # These SPI_SET* flags pass the boolean as uiParam, with pvParam=IntPtr.Zero.
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
    # Disables the Sticky Keys accessibility shortcut (Shift x5).
    # The registry key persists the setting; the SPI call applies it live.
    # dwFlags value 510 (decimal) = 0x1FE: all default flags except SKF_STICKYKEYSON.
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
    # Applies a curated visual effects preset:
    # - Animations that convey no information (menu/tooltip fade, shadows) are disabled.
    # - Animations that aid spatial awareness (drag full windows, font smoothing,
    #   client area animation for scroll/expand) are kept enabled.
    # - Minimize/maximize animations (window collapsing to taskbar) are disabled
    #   via both registry (MinAnimate=0 in uwt_tweaks.reg) and SPI_SETANIMATION.

    $desktop = 'HKCU:\Control Panel\Desktop'
    $metrics = 'HKCU:\Control Panel\Desktop\WindowMetrics'

    if (-not (Test-Path $desktop)) { New-Item -Path $desktop -Force | Out-Null }
    if (-not (Test-Path $metrics)) { New-Item -Path $metrics -Force | Out-Null }

    New-ItemProperty -Path $desktop -Name DragFullWindows -PropertyType String -Value '1' -Force | Out-Null
    New-ItemProperty -Path $desktop -Name FontSmoothing -PropertyType String -Value '2' -Force | Out-Null
    New-ItemProperty -Path $metrics -Name MinAnimate -PropertyType String -Value '0' -Force | Out-Null

    Invoke-SpiPvBool -Action $SPI_SETCLIENTAREAANIMATION -Enabled $true -Label 'Visual Effects: animate controls and elements inside windows = on'
    Invoke-SpiPvBool -Action $SPI_SETMENUANIMATION -Enabled $false -Label 'Visual Effects: fade or slide menus into view = off'
    Invoke-SpiPvBool -Action $SPI_SETTOOLTIPANIMATION -Enabled $false -Label 'Visual Effects: fade or slide ToolTips into view = off'
    Invoke-SpiPvBool -Action $SPI_SETSELECTIONFADE -Enabled $false -Label 'Visual Effects: fade out menu items after clicking = off'
    Invoke-SpiPvBool -Action $SPI_SETCURSORSHADOW -Enabled $false -Label 'Visual Effects: show shadows under mouse pointer = off'
    Invoke-SpiPvBool -Action $SPI_SETDROPSHADOW -Enabled $false -Label 'Visual Effects: show shadows under windows = off'
    Invoke-SpiPvBool -Action $SPI_SETCOMBOBOXANIMATION -Enabled $false -Label 'Visual Effects: slide open combo boxes = off'
    Invoke-SpiPvBool -Action $SPI_SETLISTBOXSMOOTHSCROLLING -Enabled $false -Label 'Visual Effects: smooth-scroll list boxes = off'
    Invoke-SpiAltBool -Action $SPI_SETDRAGFULLWINDOWS -Enabled $true -Label 'Visual Effects: show window contents while dragging = on'
    Invoke-SpiAltBool -Action $SPI_SETFONTSMOOTHING -Enabled $true -Label 'Visual Effects: smooth edges of screen fonts = on'

    # SPI_SETANIMATION requires a pointer to an ANIMATIONINFO struct.
    # iMinAnimate=0 disables the minimize/restore animation for all windows.
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
    # Ensures the Windows Magnifier is not running and its registry state is off.
    $key = 'HKCU:\Software\Microsoft\ScreenMagnifier'
    if (-not (Test-Path $key)) {
        New-Item -Path $key -Force | Out-Null
    }

    New-ItemProperty -Path $key -Name RunningState -PropertyType DWord -Value 0 -Force | Out-Null
    Get-Process -Name Magnify -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "    [SET] Magnifier disabled"
}

function Refresh-UserShell {
    # Calls UpdatePerUserSystemParameters via rundll32 to force Windows to re-read
    # the user's SystemParameters registry values. This triggers Windows Explorer
    # and other shell components to pick up the SPI changes applied above without
    # requiring a logoff. Equivalent to the broadcast sent by SPIF_SENDCHANGE but
    # via the full shell refresh path.
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

# Windows Security Center (wscsvc) is not in 03_services.ps1 because it is a
# protected service that requires additional steps to modify on some builds.
# Disabled here as a final step after all other tweaks are applied.
# wscsvc monitors the state of security products (antivirus, firewall, WU)
# and generates Action Center alerts when it detects a gap. With Defender
# deliberately disabled and the firewall off, wscsvc would generate constant
# alerts. Disabling it suppresses these false alarms.
$svc = Get-Service 'wscsvc' -ErrorAction SilentlyContinue
if ($svc) {
    Stop-Service  'wscsvc' -Force -ErrorAction SilentlyContinue
    Set-Service   'wscsvc' -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "    [DISABLED]   wscsvc (Windows Security Center)"
} else {
    Write-Host "    [NOT FOUND]  wscsvc" -ForegroundColor Gray
}
