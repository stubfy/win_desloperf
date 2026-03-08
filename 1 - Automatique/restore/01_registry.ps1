# restore\01_registry.ps1 - Restaure les cles de registre modifiees par opti pack

$RESTORE_DIR = $PSScriptRoot
$BACKUP_DIR  = Join-Path (Split-Path $PSScriptRoot) "backup"
$defaultsReg = Join-Path $RESTORE_DIR "tweaks_defaults.reg"

# Etape 1 : Appliquer les valeurs par defaut Windows (inverse de tweaks_consolidated.reg)
if (Test-Path $defaultsReg) {
    Start-Process "regedit.exe" -ArgumentList "/s `"$defaultsReg`"" -Wait -Verb RunAs
    Write-Host "    Valeurs par defaut appliquees depuis tweaks_defaults.reg"
} else {
    Write-Host "    tweaks_defaults.reg introuvable." -ForegroundColor Yellow
}

# Etape 2 : Surcharger avec les exports de sauvegarde pre-tweaks (si disponibles)
if (Test-Path $BACKUP_DIR) {
    $regFiles = Get-ChildItem "$BACKUP_DIR\backup_*.reg" -ErrorAction SilentlyContinue
    foreach ($regFile in $regFiles) {
        Start-Process "regedit.exe" -ArgumentList "/s `"$($regFile.FullName)`"" -Wait -Verb RunAs
        Write-Host "    Sauvegarde restauree : $($regFile.Name)"
    }
} else {
    Write-Host "    Aucun dossier backup trouve. Seules les valeurs par defaut ont ete appliquees." -ForegroundColor Gray
}

Write-Host ""
Write-Host "    Si le systeme presente des problemes, utiliser le point de restauration systeme :" -ForegroundColor Gray
Write-Host "    Panneau de configuration > Systeme > Protection du systeme > Restauration du systeme" -ForegroundColor Gray
