# restore\opt_edge_restore.ps1 - Reinstall Microsoft Edge

# Remove reinstallation block
$noEdge = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
if (Test-Path $noEdge) {
    Remove-ItemProperty -Path $noEdge -Name 'DoNotUpdateToEdgeWithChromium' -ErrorAction SilentlyContinue
    Write-Host "    Edge reinstallation block removed."
}

# Attempt reinstallation via winget
Write-Host "    Reinstalling Microsoft Edge via winget..."
$result = winget install --id Microsoft.Edge --silent --accept-package-agreements --accept-source-agreements 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "    [OK] Edge reinstalled."
} else {
    Write-Host "    winget returned: $LASTEXITCODE" -ForegroundColor Yellow
    Write-Host "    Download Edge manually: https://www.microsoft.com/edge" -ForegroundColor Gray
}
