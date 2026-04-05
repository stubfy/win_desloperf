# restore\performance.ps1 - Restore BCD, power plan, USB selective suspend, Memory Compression
# Combines: restore\bcdedit.ps1, restore\power.ps1, restore\usb.ps1
#
# Rollback: undoes performance.ps1 tweaks (disabledynamictick, power plan, USB suspend, memory compression)

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

# Note: the Bitsum Highest Performance plan (5a39c962-...) is kept available in
# power options after restore. Duplicate "Ultimate Performance" plans were already
# cleaned up by performance.ps1 during the original run.
Write-Host "    Note: Bitsum Highest Performance plan (5a39c962-...) remains available in power options." -ForegroundColor Gray
Write-Host "    Delete it manually if desired: powercfg -delete 5a39c962-8fb2-4c72-8843-936f1d325503" -ForegroundColor Gray

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

# === SECTION: Restore Memory Compression ===

Enable-MMAgent -MemoryCompression
Write-Host "    Memory Compression re-enabled"
