# 04_bcdedit.ps1 - Configuration boot pour reduire la latence

# Force le tick TSC constant (reduit la latence des timers en jeu)
bcdedit /set disabledynamictick yes 2>&1 | Out-Null
Write-Host "    disabledynamictick = yes"

# Menu de demarrage classique (plus rapide au boot)
# ATTENTION: desactive l'acces aux options de recuperation graphiques (F8 fonctionne toujours)
bcdedit /set bootmenupolicy legacy 2>&1 | Out-Null
Write-Host "    bootmenupolicy = legacy"

# Desactiver HPET (High Precision Event Timer) - peut reduire la latence DPC sur certains systemes
bcdedit /set useplatformclock false 2>&1 | Out-Null
Write-Host "    useplatformclock = false (HPET desactive)"
