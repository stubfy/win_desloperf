# restore\opt_edge_restore.ps1 - Reinstallation de Microsoft Edge

# Supprimer le blocage de reinstallation
$noEdge = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
if (Test-Path $noEdge) {
    Remove-ItemProperty -Path $noEdge -Name 'DoNotUpdateToEdgeWithChromium' -ErrorAction SilentlyContinue
    Write-Host "    Blocage reinstallation Edge supprime."
}

# Tentative de reinstallation via winget
Write-Host "    Reinstallation de Microsoft Edge via winget..."
$result = winget install --id Microsoft.Edge --silent --accept-package-agreements --accept-source-agreements 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    [OK] Edge reinstalle."
} else {
    Write-Host "    winget a retourne : $LASTEXITCODE" -ForegroundColor Yellow
    Write-Host "    Telecharger Edge manuellement : https://www.microsoft.com/edge" -ForegroundColor Gray
}
