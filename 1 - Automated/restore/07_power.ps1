# restore\07_power.ps1 - Restore the default Balanced power plan

# Re-enable hibernation
powercfg -h on 2>&1 | Out-Null
Write-Host "    Hibernation re-enabled."

# Activate the Balanced plan (built-in Windows GUID, always present)
powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null
Write-Host "    Balanced plan activated (381b4222-f694-41f0-9685-ff5bb260df2e)"

# Note about the created Ultimate Performance plan (not automatically deleted)
Write-Host "    Note: the created 'Ultimate Performance' plan remains available in power options." -ForegroundColor Gray
Write-Host "    Delete it manually if desired: powercfg -delete <GUID>" -ForegroundColor Gray
