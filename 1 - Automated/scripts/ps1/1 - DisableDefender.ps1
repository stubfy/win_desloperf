#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'
$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services'
$services = @(
    'WinDefend',
    'Sense',
    'WdFilter',
    'WdNisDrv',
    'WdNisSvc',
    'WdBoot'
)

$updated = 0

foreach ($service in $services) {
    $path = Join-Path $regPath $service
    if (-not (Test-Path $path)) {
        Write-Host "Skipping $service (service key not found)." -ForegroundColor Yellow
        continue
    }

    Set-ItemProperty -Path $path -Name Start -Value 4 -Type DWord
    Write-Host "Disabled $service (Start=4)." -ForegroundColor Green
    $updated++
}

if ($updated -eq 0) {
    throw "No Defender service keys were updated."
}

Write-Host ""
Write-Host "Windows Defender service startup values updated." -ForegroundColor Cyan

# Smart App Control
# VerifiedAndReputablePolicyState: 0=Off, 1=Evaluation, 2=Enforcing
# WARNING: setting to 0 is one-way -- re-enabling requires a full Windows reinstall.
# Safe Mode is required because Tamper Protection blocks writes to CI\Policy in normal mode.
$ciPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy'
Write-Host ""
if (Test-Path $ciPath) {
    try {
        Set-ItemProperty -Path $ciPath -Name 'VerifiedAndReputablePolicyState' -Value 0 -Type DWord -Force
        Write-Host "Smart App Control set to Off (VerifiedAndReputablePolicyState=0)." -ForegroundColor Green
        Write-Host "  NOTE: one-way change -- re-enabling requires reinstalling Windows." -ForegroundColor Yellow
    } catch {
        Write-Host "Failed to set Smart App Control: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Smart App Control key not found ($ciPath) -- skipping." -ForegroundColor Yellow
}
