# restore\12_firewall.ps1 - Restore Windows Firewall profile states

$BACKUP_DIR = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "backup"
$stateFile  = Join-Path $BACKUP_DIR "firewall_state.json"

$defaults = [ordered]@{
    Domain  = $true
    Private = $true
    Public  = $true
}

if (Test-Path $stateFile) {
    $saved = Get-Content $stateFile -Encoding UTF8 | ConvertFrom-Json
    foreach ($prop in $saved.PSObject.Properties) {
        $defaults[$prop.Name] = [bool]$prop.Value
    }
    Write-Host "    Saved firewall state loaded from: $stateFile"
} else {
    Write-Host "    No firewall backup found, using Windows default values." -ForegroundColor Gray
}

foreach ($profileName in $defaults.Keys) {
    try {
        Set-NetFirewallProfile -Profile $profileName -Enabled $defaults[$profileName] -ErrorAction Stop
        $stateLabel = if ($defaults[$profileName]) { 'Enabled' } else { 'Disabled' }
        Write-Host "    [RESTORED]  $profileName -> $stateLabel"
    } catch {
        Write-Host "    [WARN] Unable to restore $profileName firewall profile: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
