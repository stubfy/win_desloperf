# restore\14_network_tweaks.ps1 - Restore additional network tweaks

# Restore Teredo to its Windows default state
netsh interface teredo set state default 2>&1 | ForEach-Object { Write-Host "    $_" }
Write-Host "    Teredo restored (default state)"
