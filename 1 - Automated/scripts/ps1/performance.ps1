# performance.ps1 - System performance: power plan, BCD, USB selective suspend
# Combines: power.ps1, bcdedit.ps1, usb.ps1
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
# BCD:
#   disabledynamictick: Forces a constant TSC-based tick at the full requested
#     timer resolution, reducing jitter in frame-to-frame timing.
#   bootmenupolicy legacy: Classic text-mode boot menu rendered by the bootloader.
#     WARNING: Graphical Recovery Environment not available via boot menu afterwards.
#     Recovery: Settings > Recovery > Advanced startup, or F8/Shift+F8 during boot.
#
# USB selective suspend:
#   Keeps USB ports powered at all times to avoid input device wake-up latency.
#   Reuses $planGuid obtained in the power section (no redundant powercfg query).
#
# Rollback: restore\performance.ps1

# === SECTION: Ultimate Performance power plan ===

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

# === SECTION: Boot configuration (bcdedit) ===

# Force constant TSC tick (reduces timer latency jitter in games)
bcdedit /set disabledynamictick yes 2>&1 | Out-Null
Write-Host "    disabledynamictick = yes"

# Classic boot menu (faster to display; loses graphical recovery entry)
bcdedit /set bootmenupolicy legacy 2>&1 | Out-Null
Write-Host "    bootmenupolicy = legacy"

# === SECTION: USB selective suspend ===
# Reuses $planGuid from the power section above (no redundant powercfg query).
# Keeps USB ports powered at all times to avoid input device wake-up latency.
# Subgroup: 2a737441-1930-4402-8d77-b2bebba308a3 (USB settings)
# Setting:  48e6b7a6-50f5-4782-a5d4-53bb8f07e226 (USB selective suspend)
# Value: 0 = Disabled

if (-not $planGuid) {
    Write-Host "    ERROR: unable to determine active plan GUID for USB suspend." -ForegroundColor Red
} else {
    powercfg /setacvalueindex $planGuid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    powercfg /setdcvalueindex $planGuid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    powercfg /setactive $planGuid 2>&1 | Out-Null
    Write-Host "    USB selective suspend disabled on plan: $planGuid"
}
