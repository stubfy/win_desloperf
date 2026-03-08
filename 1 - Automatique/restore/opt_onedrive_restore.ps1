# restore\opt_onedrive_restore.ps1 - Reinstallation de OneDrive

# Supprimer la politique de blocage
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
if (Test-Path $policy) {
    Remove-ItemProperty -Path $policy -Name 'DisableFileSyncNGSC' -ErrorAction SilentlyContinue
    Write-Host "    Politique de blocage OneDrive supprimee."
}

# Restaurer l'icone OneDrive dans l'Explorateur
$clsids = @(
    'HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
    'HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
)
foreach ($path in $clsids) {
    if (Test-Path $path) {
        Set-ItemProperty -Path $path -Name 'System.IsPinnedToNameSpaceTree' -Value 1 -Type DWord -ErrorAction SilentlyContinue
    }
}

# Tentative de reinstallation via winget
Write-Host "    Reinstallation de OneDrive via winget..."
$result = winget install --id Microsoft.OneDrive --silent --accept-package-agreements --accept-source-agreements 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    [OK] OneDrive reinstalle."
} else {
    Write-Host "    winget a retourne : $LASTEXITCODE" -ForegroundColor Yellow
    Write-Host "    Telecharger OneDrive manuellement depuis le Microsoft Store ou onedrive.live.com/about/download" -ForegroundColor Gray
}
