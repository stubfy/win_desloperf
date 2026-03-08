# restore\07_power.ps1 - Restaure le plan d'alimentation equilibre par defaut

# Reactiver l'hibernation
powercfg -h on 2>&1 | Out-Null
Write-Host "    Hibernation reactivee."

# Activer le plan Equilibre (GUID Windows integre, toujours present)
powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-Null
Write-Host "    Plan Equilibre active (381b4222-f694-41f0-9685-ff5bb260df2e)"

# Informer l'utilisateur du plan Ultimate Performance cree (pas supprime automatiquement)
Write-Host "    Note: le plan 'Ultimate Performance' cree reste disponible dans les options d'alimentation." -ForegroundColor Gray
Write-Host "    Le supprimer manuellement si souhaite : powercfg -delete <GUID>" -ForegroundColor Gray
