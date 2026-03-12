# restore\opt_onedrive_restore.ps1 - Reinstall OneDrive

# Remove blocking policy
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
if (Test-Path $policy) {
    Remove-ItemProperty -Path $policy -Name 'DisableFileSyncNGSC' -ErrorAction SilentlyContinue
    Write-Host "    OneDrive blocking policy removed."
}

# Restore OneDrive icon in File Explorer
$clsids = @(
    'HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
    'HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
)
foreach ($path in $clsids) {
    if (Test-Path $path) {
        Set-ItemProperty -Path $path -Name 'System.IsPinnedToNameSpaceTree' -Value 1 -Type DWord -ErrorAction SilentlyContinue
    }
}

# Attempt reinstallation via winget
Write-Host "    Reinstalling OneDrive via winget..."
$result = winget install --id Microsoft.OneDrive --silent --accept-package-agreements --accept-source-agreements 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    [OK] OneDrive reinstalled."
} else {
    Write-Host "    winget returned: $LASTEXITCODE" -ForegroundColor Yellow
    Write-Host "    Download OneDrive manually from the Microsoft Store or onedrive.live.com/about/download" -ForegroundColor Gray
}
