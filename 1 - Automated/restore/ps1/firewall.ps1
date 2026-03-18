# restore\firewall.ps1 - Restore Windows Firewall profile states

$BACKUP_DIR = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "backup"
$stateFile  = Join-Path $BACKUP_DIR "firewall_state.json"

$defaults = [ordered]@{
    Domain  = $true
    Private = $true
    Public  = $true
}

function Convert-ToFirewallEnabledArgument {
    param([bool]$Enabled)

    if ($Enabled) {
        return 'True'
    }

    return 'False'
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
        $enabledArgument = Convert-ToFirewallEnabledArgument -Enabled $defaults[$profileName]
        Set-NetFirewallProfile -Profile $profileName -Enabled $enabledArgument -ErrorAction Stop
        $currentState = (Get-NetFirewallProfile -Profile $profileName -ErrorAction Stop).Enabled
        $currentEnabled = "$currentState" -ieq 'True'
        $stateLabel = if ($defaults[$profileName]) { 'Enabled' } else { 'Disabled' }
        if ($currentEnabled -eq $defaults[$profileName]) {
            Write-Host "    [RESTORED]  $profileName -> $stateLabel"
        } else {
            $currentLabel = if ($currentEnabled) { 'Enabled' } else { 'Disabled' }
            Write-Host "    [WARN] Unable to verify $profileName firewall profile: current=$currentLabel wanted=$stateLabel" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    [WARN] Unable to restore $profileName firewall profile: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
