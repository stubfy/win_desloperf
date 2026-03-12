# 08_debloat.ps1 - Remove bloatware UWP apps from Windows 11 25H2

$appsToRemove = @(
    # Xbox / Gaming
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.GamingApp'
    # Microsoft bloatware
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
    'Microsoft.ZuneVideo'               # Movies & TV legacy
    'Microsoft.YourPhone'               # Phone Link
    'Microsoft.Phone'
    'Clipchamp.Clipchamp'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.Copilot'
    'Microsoft.OutlookForWindows'
    # Widgets (disabled via registry in 02_registry, packages removed here)
    'MicrosoftWindows.Client.WebExperience'
    'Microsoft.WidgetsPlatformRuntime'
)

$removed = 0
$errors  = 0

foreach ($appName in $appsToRemove) {
    $pkg = Get-AppxPackage -Name $appName -AllUsers -ErrorAction SilentlyContinue
    if ($pkg) {
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            $removed++
            Write-Host "    [REMOVED] $appName"
        } catch {
            $errors++
            Write-Host "    [ERROR]   $appName - $_" -ForegroundColor Yellow
        }
    }

    # Also remove the provisioned package to prevent reinstallation after reset
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $appName }
    if ($prov) {
        Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
    }
}

Write-Host "    Summary: $removed removed, $errors error(s), $($appsToRemove.Count - $removed - $errors) not found"
