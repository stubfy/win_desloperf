# 05_power.ps1 - Ultimate Performance power plan + CPU parameters
#
# Power plan strategy:
#   Windows ships with a hidden "Ultimate Performance" plan (GUID ending in ...eb61)
#   that disables all CPU idle states (C-states), sets minimum processor frequency
#   to 100% and removes every power-saving behavior that could introduce latency.
#   This script duplicates it (creating a new named instance) and activates it.
#
# PPM setting - Processor Performance Increase Policy (Bitsum "Rocket"):
#   Subgroup: Processor power management (54533251-82be-4824-96c1-47b60b740d00)
#   Setting:  Processor performance increase policy (4d2b0152-7d5c-498b-88e2-34345392a2c5)
#   Value 5000 = "Rocket" (immediate maximum frequency on any load increase).
#   This controls how aggressively the PPM (Processor Power Manager) scales up
#   CPU frequency when it detects a demand spike. The default "Ideal" policy ramps
#   up gradually; "Rocket" jumps to maximum frequency immediately, eliminating the
#   latency of the ramp-up period during burst workloads (frame start, physics step).
#
# Sleep / hibernation:
#   standby-timeout 0 disables sleep on AC and DC.
#   powercfg -h off removes hiberfil.sys (also set via registry in tweaks_consolidated.reg
#   HibernateEnabled=0; both layers needed for full removal).
#
# Rollback: restore\07_power.ps1

# Duplicate the Ultimate Performance plan (built-in, fixed GUID)
$dupOutput = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-String
$planGuid  = [regex]::Match($dupOutput, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value

if (-not $planGuid) {
    Write-Host "    WARNING: unable to create Ultimate Performance plan." -ForegroundColor Yellow
    Write-Host "    Active plan unchanged. Apply manually if needed."
    # Apply the Bitsum parameter to the current active plan anyway
    $activeLine = powercfg -getactivescheme 2>&1 | Out-String
    $planGuid   = [regex]::Match($activeLine, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value
}

if ($planGuid) {
    # Activate the plan
    powercfg -setactive $planGuid 2>&1 | Out-Null
    Write-Host "    Active plan: $planGuid"

    # Processor Performance Increase Policy = 5000 (Rocket: immediate max frequency)
    # Subgroup: Processor power management | Setting: Increase policy
    powercfg /setacvalueindex $planGuid `
        54533251-82be-4824-96c1-47b60b740d00 `
        4d2b0152-7d5c-498b-88e2-34345392a2c5 `
        5000 2>&1 | Out-Null
    powercfg /setactive $planGuid 2>&1 | Out-Null
    Write-Host "    CPU frequency scaling policy: Rocket (5000)"

    # Disable sleep on AC and battery (standby-timeout 0 = never sleep)
    powercfg /change standby-timeout-ac 0 2>&1 | Out-Null
    powercfg /change standby-timeout-dc 0 2>&1 | Out-Null
    Write-Host "    Sleep disabled on AC and battery"

    # Disable hibernation: removes hiberfil.sys and prevents hybrid sleep.
    # Also set via registry (HibernateEnabled=0 in tweaks_consolidated.reg).
    powercfg -h off 2>&1 | Out-Null
    Write-Host "    Hibernation disabled (hiberfil.sys removed)"
} else {
    Write-Host "    ERROR: unable to determine active plan GUID." -ForegroundColor Red
}
