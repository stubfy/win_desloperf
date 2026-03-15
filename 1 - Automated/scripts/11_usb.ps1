# 11_usb.ps1 - Disable USB selective suspend on the active power plan
#
# USB selective suspend allows the USB host controller to suspend individual
# USB ports (cut power) when the connected device appears idle, to save energy.
# On a gaming PC this can cause:
#   - Input devices (mouse, keyboard, headset) to take a few milliseconds to
#     "wake up" after a period of no input, introducing a one-time latency spike.
#   - USB DACs / audio interfaces to briefly drop out when no audio is playing.
# Disabling selective suspend keeps USB ports powered at all times.
# Effect: USB devices respond at full speed instantly with no wake-up latency.
# Power cost: negligible on a desktop PC always plugged into mains.
#
# The setting is applied to both AC (on-power) and DC (battery) profiles via
# setacvalueindex and setdcvalueindex respectively, then the plan is re-activated
# to make the change take effect without a reboot.
#
# Subgroup GUID : 2a737441-1930-4402-8d77-b2bebba308a3  (USB settings)
# Setting GUID  : 48e6b7a6-50f5-4782-a5d4-53bb8f07e226  (USB selective suspend)
# Value         : 0 = Disabled, 1 = Enabled
#
# Rollback: restore\08_usb.ps1 re-enables selective suspend (value 1).

$activeLine = powercfg -getactivescheme 2>&1 | Out-String
$scheme     = [regex]::Match($activeLine, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value

if (-not $scheme) {
    Write-Host "    ERROR: unable to determine active plan GUID." -ForegroundColor Red
    return
}

powercfg /setacvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
powercfg /setdcvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
powercfg /setactive $scheme 2>&1 | Out-Null

Write-Host "    USB selective suspend disabled on plan: $scheme"
