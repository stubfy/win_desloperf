# 08_debloat.ps1 - Supprime les applications UWP bloatware de Windows 11 25H2

$appsToRemove = @(
    # Xbox / Gaming
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.GamingApp'
    # Bloatware Microsoft
    'Microsoft.Getstarted'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.GetHelp'
    'Microsoft.People'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.BingSearch'
    'Microsoft.549981C3F5F10'           # Cortana
    'Microsoft.MicrosoftTeams'
    'MicrosoftTeams'
    'Microsoft.Todos'
    'Microsoft.WindowsMaps'
    'Microsoft.ZuneMusic'               # Groove Music / Media Player legacy
    'Microsoft.ZuneVideo'               # Films et TV legacy
    'Microsoft.YourPhone'               # Phone Link
    'Microsoft.Phone'
    'Clipchamp.Clipchamp'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.Copilot'
    'Microsoft.OutlookForWindows'
)

$removed = 0
$errors  = 0

foreach ($appName in $appsToRemove) {
    $pkg = Get-AppxPackage -Name $appName -AllUsers -ErrorAction SilentlyContinue
    if ($pkg) {
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            $removed++
            Write-Host "    [SUPPRIME] $appName"
        } catch {
            $errors++
            Write-Host "    [ERREUR]   $appName - $_" -ForegroundColor Yellow
        }
    }

    # Supprimer aussi le provisioned package pour empecher la reinstallation apres reset
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $appName }
    if ($prov) {
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
    }
}

Write-Host "    Bilan: $removed supprime(s), $errors erreur(s), $($appsToRemove.Count - $removed - $errors) absent(s)"
