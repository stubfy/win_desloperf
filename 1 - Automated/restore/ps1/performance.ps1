# restore\performance.ps1 - Restore BCD, power plan, USB selective suspend
# Combines: restore\bcdedit.ps1, restore\power.ps1, restore\usb.ps1
#
# Rollback: undoes performance.ps1 tweaks (disabledynamictick, power plan, USB suspend)

# === SECTION: Restore boot configuration ===

bcdedit /deletevalue disabledynamictick 2>&1 | Out-Null
Write-Host "    disabledynamictick removed (dynamic tick re-enabled)"

bcdedit /set bootmenupolicy standard 2>&1 | Out-Null
Write-Host "    bootmenupolicy = standard (graphical recovery options restored)"

# === SECTION: Restore power plan ===

# Re-enable hibernation
powercfg -h on 2>&1 | Out-Null
Write-Host "    Hibernation re-enabled."

# Activate the Balanced plan (built-in Windows GUID, always present)
powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null
Write-Host "    Balanced plan activated (381b4222-f694-41f0-9685-ff5bb260df2e)"

# Note about the created Ultimate Performance plan (not automatically deleted)
Write-Host "    Note: the created 'Ultimate Performance' plan remains available in power options." -ForegroundColor Gray
Write-Host "    Delete it manually if desired: powercfg -delete <GUID>" -ForegroundColor Gray

# === SECTION: Restore USB selective suspend ===

$activeLine = powercfg -getactivescheme 2>&1 | Out-String
$scheme     = [regex]::Match($activeLine, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value

if (-not $scheme) {
    Write-Host "    ERROR: unable to determine active plan GUID." -ForegroundColor Red
} else {
    powercfg /setacvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>&1 | Out-Null
    powercfg /setdcvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>&1 | Out-Null
    powercfg /setactive $scheme 2>&1 | Out-Null
    Write-Host "    USB selective suspend re-enabled on: $scheme"
}
