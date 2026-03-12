# opt_edge_uninstall.ps1 - Complete physical uninstallation of Microsoft Edge
# OPTIONAL - called only if confirmed by the user in run_all.ps1

Write-Host "    Looking for Edge installer..."

$edgeBase = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
if (-not (Test-Path $edgeBase)) {
    $edgeBase = "$env:ProgramFiles\Microsoft\Edge\Application"
}

if (-not (Test-Path $edgeBase)) {
    Write-Host "    Edge not found (already uninstalled or non-standard path)." -ForegroundColor Gray
    return
}

# Find setup.exe in the version subfolder
$setupExe = Get-ChildItem "$edgeBase\*\Installer\setup.exe" -ErrorAction SilentlyContinue |
            Sort-Object { [version]($_.Directory.Parent.Name) } -Descending |
            Select-Object -First 1

if (-not $setupExe) {
    Write-Host "    setup.exe not found in $edgeBase" -ForegroundColor Yellow
    Write-Host "    Trying via winget..." -ForegroundColor Gray
    winget uninstall --id Microsoft.Edge --silent --accept-source-agreements 2>&1 | Out-Null
    Write-Host "    Uninstallation via winget launched (verify manually)." -ForegroundColor Gray
    return
}

Write-Host "    Launching Edge uninstall: $($setupExe.FullName)"
$args = '--uninstall --system-level --verbose-logging --force-uninstall'
Start-Process -FilePath $setupExe.FullName -ArgumentList $args -Wait -NoNewWindow

# Post-uninstall registry cleanup
$edgeRegPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
)
foreach ($path in $edgeRegPaths) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Prevent automatic reinstallation via Windows Update
$noEdge = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
if (-not (Test-Path $noEdge)) { New-Item -Path $noEdge -Force | Out-Null }
Set-ItemProperty -Path $noEdge -Name 'DoNotUpdateToEdgeWithChromium' -Value 1 -Type DWord -ErrorAction SilentlyContinue

Write-Host "    Microsoft Edge uninstalled. Reinstallation blocked via registry."
Write-Host "    Note: Edge may be reinstalled by Windows Update. Check 'Installed apps'."
