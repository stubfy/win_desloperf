# opt_edge_uninstall.ps1 - Desinstallation physique complete de Microsoft Edge
# OPTIONNEL - appele uniquement si l'utilisateur l'a confirme dans run_all.ps1

Write-Host "    Recherche de l'installateur Edge..."

$edgeBase = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
if (-not (Test-Path $edgeBase)) {
    $edgeBase = "$env:ProgramFiles\Microsoft\Edge\Application"
}

if (-not (Test-Path $edgeBase)) {
    Write-Host "    Edge introuvable (deja desinstalle ou chemin non standard)." -ForegroundColor Gray
    return
}

# Trouver le setup.exe dans le sous-dossier de version
$setupExe = Get-ChildItem "$edgeBase\*\Installer\setup.exe" -ErrorAction SilentlyContinue |
            Sort-Object { [version]($_.Directory.Parent.Name) } -Descending |
            Select-Object -First 1

if (-not $setupExe) {
    Write-Host "    setup.exe introuvable dans $edgeBase" -ForegroundColor Yellow
    Write-Host "    Tentative via winget..." -ForegroundColor Gray
    winget uninstall --id Microsoft.Edge --silent --accept-source-agreements 2>&1 | Out-Null
    Write-Host "    Desinstallation via winget lancee (verifier manuellement)." -ForegroundColor Gray
    return
}

Write-Host "    Lancement desinstallation Edge : $($setupExe.FullName)"
$args = '--uninstall --system-level --verbose-logging --force-uninstall'
Start-Process -FilePath $setupExe.FullName -ArgumentList $args -Wait -NoNewWindow

# Nettoyage registre post-desinstallation
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

# Empecher la reinstallation automatique par Windows Update
$noEdge = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
if (-not (Test-Path $noEdge)) { New-Item -Path $noEdge -Force | Out-Null }
Set-ItemProperty -Path $noEdge -Name 'DoNotUpdateToEdgeWithChromium' -Value 1 -Type DWord -ErrorAction SilentlyContinue

Write-Host "    Microsoft Edge desinstalle. Reinstallation bloquee via registre."
Write-Host "    Note: Edge peut etre reinstalle par Windows Update. Verifier dans 'Applications installees'."
