# restore\01_registry.ps1 - Restore registry keys modified by opti pack

$RESTORE_DIR = $PSScriptRoot
$BACKUP_DIR  = Join-Path (Split-Path $PSScriptRoot) "backup"
$defaultsReg = Join-Path $RESTORE_DIR "tweaks_defaults.reg"

# Step 1: Apply Windows default values (reverse of tweaks_consolidated.reg)
if (Test-Path $defaultsReg) {
    Start-Process "regedit.exe" -ArgumentList "/s `"$defaultsReg`"" -Wait -Verb RunAs
    Write-Host "    Default values applied from tweaks_defaults.reg"
} else {
    Write-Host "    tweaks_defaults.reg not found." -ForegroundColor Yellow
}

# Step 2: Override with pre-tweak backup exports (if available)
if (Test-Path $BACKUP_DIR) {
    $regFiles = Get-ChildItem "$BACKUP_DIR\backup_*.reg" -ErrorAction SilentlyContinue
    foreach ($regFile in $regFiles) {
        Start-Process "regedit.exe" -ArgumentList "/s `"$($regFile.FullName)`"" -Wait -Verb RunAs
        Write-Host "    Backup restored: $($regFile.Name)"
    }
} else {
    Write-Host "    No backup folder found. Only default values were applied." -ForegroundColor Gray
}

Write-Host ""
Write-Host "    If the system has issues, use the system restore point:" -ForegroundColor Gray
Write-Host "    Control Panel > System > System Protection > System Restore" -ForegroundColor Gray
