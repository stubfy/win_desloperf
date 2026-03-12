# restore\08_usb.ps1 - Restore USB selective suspend to its default value (enabled)

$activeLine = powercfg -getactivescheme 2>&1 | Out-String
$scheme     = [regex]::Match($activeLine, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value

if (-not $scheme) {
    Write-Host "    ERROR: unable to determine active plan GUID." -ForegroundColor Red
    return
}

powercfg /setacvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>&1 | Out-Null
powercfg /setdcvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>&1 | Out-Null
powercfg /setactive $scheme 2>&1 | Out-Null

Write-Host "    USB selective suspend re-enabled on: $scheme"
