# restore\03_bcdedit.ps1 - Restaure la configuration boot par defaut

bcdedit /deletevalue disabledynamictick 2>&1 | Out-Null
Write-Host "    disabledynamictick supprime (dynamique reactiver)"

bcdedit /set bootmenupolicy standard 2>&1 | Out-Null
Write-Host "    bootmenupolicy = standard (options de recuperation graphiques restaurees)"

bcdedit /deletevalue useplatformclock 2>&1 | Out-Null
Write-Host "    useplatformclock supprime (HPET gere automatiquement par Windows)"
