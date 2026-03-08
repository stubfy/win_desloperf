# 05_power.ps1 - Plan d'alimentation Ultimate Performance + parametres CPU

# Dupliquer le plan Ultimate Performance (integre a Windows, GUID fixe)
$dupOutput = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-String
$planGuid  = [regex]::Match($dupOutput, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value

if (-not $planGuid) {
    Write-Host "    AVERTISSEMENT: impossible de creer Ultimate Performance." -ForegroundColor Yellow
    Write-Host "    Le plan actif reste inchange. Appliquer manuellement si necessaire."
    # Appliquer quand meme le parametre Bitsum sur le plan actif
    $activeLine = powercfg -getactivescheme 2>&1 | Out-String
    $planGuid   = [regex]::Match($activeLine, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value
}

if ($planGuid) {
    # Activer le plan
    powercfg -setactive $planGuid 2>&1 | Out-Null
    Write-Host "    Plan actif : $planGuid"

    # Politique de montee en frequence CPU aggressive (mode "Rocket" Bitsum)
    # GUID subgroup : Gestion de l'alimentation du processeur (54533251-...)
    # GUID setting  : Politique d'augmentation des performances (4d2b0152-...)
    powercfg /setacvalueindex $planGuid `
        54533251-82be-4824-96c1-47b60b740d00 `
        4d2b0152-7d5c-498b-88e2-34345392a2c5 `
        5000 2>&1 | Out-Null
    powercfg /setactive $planGuid 2>&1 | Out-Null
    Write-Host "    Politique montee frequence CPU : Rocket (5000)"

    # Desactiver l'hibernation (supprime hiberfil.sys, libere espace)
    powercfg -h off 2>&1 | Out-Null
    Write-Host "    Hibernation desactivee (hiberfil.sys supprime)"
} else {
    Write-Host "    ERREUR: impossible de determiner le GUID du plan actif." -ForegroundColor Red
}
