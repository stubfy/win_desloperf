# restore\10_debloat_restore.ps1 - Aide a la reinstallation des apps UWP supprimees

Write-Host ""
Write-Host "    La reinstallation automatique des apps UWP n'est pas possible pour toutes." -ForegroundColor Cyan
Write-Host "    Ouvrir le Microsoft Store et rechercher les applications suivantes :"
Write-Host ""

$appsInfo = @{
    'Xbox Game Bar'                   = 'Microsoft.XboxGamingOverlay'
    'Microsoft Teams'                 = 'MicrosoftTeams'
    'Clipchamp'                       = 'Clipchamp.Clipchamp'
    'Microsoft Solitaire Collection'  = 'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft Copilot'               = 'Microsoft.Copilot'
    'Cortana'                         = 'Microsoft.549981C3F5F10'
    'MSN Meteo'                       = 'Microsoft.BingWeather'
    'Microsoft To Do'                 = 'Microsoft.Todos'
    'Phone Link'                      = 'Microsoft.YourPhone'
    'Outlook'                         = 'Microsoft.OutlookForWindows'
}

foreach ($app in $appsInfo.Keys) {
    Write-Host "    - $app (ID: $($appsInfo[$app]))"
}

Write-Host ""
Write-Host "    Commande winget pour reinstaller (exemples) :" -ForegroundColor Gray
Write-Host "      winget install 9NBLGGH4NNS1   (Xbox Game Bar)" -ForegroundColor Gray
Write-Host "      winget install 9WZDNCRFJ3PZ   (Microsoft Teams)" -ForegroundColor Gray
Write-Host ""
Write-Host "    Pour Xbox en particulier, reinstaller depuis la page Xbox du Store." -ForegroundColor Gray
