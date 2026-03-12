# 05_power.ps1 - Ultimate Performance power plan + CPU parameters

# Duplicate the Ultimate Performance plan (built into Windows, fixed GUID)
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

    # Aggressive CPU frequency scaling policy (Bitsum "Rocket" mode)
    # Subgroup GUID: Processor power management (54533251-...)
    # Setting GUID:  Processor performance increase policy (4d2b0152-...)
    powercfg /setacvalueindex $planGuid `
        54533251-82be-4824-96c1-47b60b740d00 `
        4d2b0152-7d5c-498b-88e2-34345392a2c5 `
        5000 2>&1 | Out-Null
    powercfg /setactive $planGuid 2>&1 | Out-Null
    Write-Host "    CPU frequency scaling policy: Rocket (5000)"

    # Disable hibernation (removes hiberfil.sys, frees disk space)
    powercfg -h off 2>&1 | Out-Null
    Write-Host "    Hibernation disabled (hiberfil.sys removed)"
} else {
    Write-Host "    ERROR: unable to determine active plan GUID." -ForegroundColor Red
}
