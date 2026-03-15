# 17_mouse_accel.ps1 - MarkC mouse acceleration fix (1:1 scaling, auto-detect DPI)
# Source: http://donewmouseaccel.blogspot.com/2010/03/markc-windows-7-mouse-acceleration-fix.html
#
# Problem: Windows "Enhanced Pointer Precision" applies a non-linear curve to raw
# HID input counts. At slow speeds the cursor moves less than 1 count per pixel;
# at fast speeds it moves more. This creates inconsistent muscle memory because
# the same physical mouse distance produces different on-screen distances depending
# on speed. Competitive gamers need a perfectly linear 1:1 mapping.
#
# Solution: MarkC's fix provides pre-computed SmoothMouseXCurve / SmoothMouseYCurve
# registry values that produce an exactly linear 1:1 transfer function. A separate
# .reg file exists for each common DPI scaling level (100%, 125%, 150%, etc.) because
# the curve values must compensate for the DPI scaling applied by the display stack.
#
# Note: tweaks_consolidated.reg (imported by 02_registry.ps1) contains the 100%
# scaling variant as a fallback. This script overrides it with the correct variant
# for the actual display scaling detected at runtime.
#
# DPI detection: LogPixels in HKCU\Control Panel\Desktop stores the DPI value
# set for the current user. 96 DPI = 100% scaling (default when key is absent),
# 120 = 125%, 144 = 150%, etc. The map covers all standard Windows scaling steps.
#
# Rollback: restore\17_mouse_accel.ps1 imports the Windows default curves.

$MOUSE_FIX_DIR = Join-Path $PSScriptRoot "mouse_fix"

# Map LogPixels value -> DPI scale percentage string (used in filename lookup)
$scaleMap = @{
    96  = '100'
    120 = '125'
    144 = '150'
    168 = '175'
    192 = '200'
    216 = '225'
    240 = '250'
    288 = '300'
    336 = '350'
}

# Detect display scaling from registry (LogPixels absent = 96 DPI = 100% scaling)
$logPixels = 96
try {
    $val = (Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'LogPixels' -ErrorAction Stop).LogPixels
    $logPixels = [int]$val
} catch {}

$scale = if ($scaleMap.ContainsKey($logPixels)) { $scaleMap[$logPixels] } else { '100' }
Write-Host "    Detected display scaling: $scale% (LogPixels=$logPixels)"

# The MarkC filenames follow the pattern:
# Windows_10+8.x_MouseFix_ItemsSize=<scale>%_Scale=1-to-1_@6-of-11.reg
# "@6-of-11" refers to the 6th pointer speed setting out of 11 (the default
# Windows pointer speed slider position). The fix assumes the slider is at 6/11.
$regFile = Join-Path $MOUSE_FIX_DIR "Windows_10+8.x_MouseFix_ItemsSize=$scale%_Scale=1-to-1_@6-of-11.reg"

if (-not (Test-Path $regFile)) {
    Write-Host "    [WARN] No MarkC fix found for $scale%, falling back to 100%"
    $regFile = Join-Path $MOUSE_FIX_DIR "Windows_10+8.x_MouseFix_ItemsSize=100%_Scale=1-to-1_@6-of-11.reg"
}

if (-not (Test-Path $regFile)) {
    Write-Host "    [ERROR] MarkC fix .reg not found: $regFile" -ForegroundColor Red
    exit 1
}

$result = Start-Process regedit.exe -ArgumentList "/s `"$regFile`"" -Wait -PassThru
if ($result.ExitCode -eq 0) {
    Write-Host "    [OK] MarkC mouse fix applied (scale: $scale%)"
} else {
    Write-Host "    [WARN] regedit exit code: $($result.ExitCode)"
}
