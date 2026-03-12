# restore\10_debloat_restore.ps1 - Help reinstalling removed UWP apps

Write-Host ""
Write-Host "    Automatic reinstallation of UWP apps is not possible for all of them." -ForegroundColor Cyan
Write-Host "    Open the Microsoft Store and search for the following apps:"
Write-Host ""

$appsInfo = @{
    'Xbox Game Bar'                   = 'Microsoft.XboxGamingOverlay'
    'Microsoft Teams'                 = 'MicrosoftTeams'
    'Clipchamp'                       = 'Clipchamp.Clipchamp'
    'Microsoft Solitaire Collection'  = 'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft Copilot'               = 'Microsoft.Copilot'
    'Cortana'                         = 'Microsoft.549981C3F5F10'
    'MSN Weather'                     = 'Microsoft.BingWeather'
    'Microsoft To Do'                 = 'Microsoft.Todos'
    'Phone Link'                      = 'Microsoft.YourPhone'
    'Outlook'                         = 'Microsoft.OutlookForWindows'
}

foreach ($app in $appsInfo.Keys) {
    Write-Host "    - $app (ID: $($appsInfo[$app]))"
}

Write-Host ""
Write-Host "    winget commands for reinstallation (examples):" -ForegroundColor Gray
Write-Host "      winget install 9NBLGGH4NNS1   (Xbox Game Bar)" -ForegroundColor Gray
Write-Host "      winget install 9WZDNCRFJ3PZ   (Microsoft Teams)" -ForegroundColor Gray
Write-Host ""
Write-Host "    For Xbox specifically, reinstall from the Xbox Store page." -ForegroundColor Gray
