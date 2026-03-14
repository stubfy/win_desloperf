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

$removedPackages      = 0
$removedProvisioned   = 0
$errors               = 0
$notFound             = 0
$perAppTimeoutSeconds = 90
$perProvTimeoutSeconds = 120

function Remove-AppxPackageWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$PackageFullName,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $job = Start-Job -ScriptBlock {
        param($pkg)
        Remove-AppxPackage -Package $pkg -AllUsers -ErrorAction Stop
    } -ArgumentList $PackageFullName

    if (Wait-Job -Job $job -Timeout $TimeoutSeconds) {
        try {
            Receive-Job -Job $job -ErrorAction Stop | Out-Null
            return $true
        } finally {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    throw "timeout after $TimeoutSeconds seconds"
}

function Remove-AppxProvisionedPackageWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $job = Start-Job -ScriptBlock {
        param($pkg)
        Remove-AppxProvisionedPackage -Online -PackageName $pkg -ErrorAction Stop | Out-Null
    } -ArgumentList $PackageName

    if (Wait-Job -Job $job -Timeout $TimeoutSeconds) {
        try {
            Receive-Job -Job $job -ErrorAction Stop | Out-Null
            return $true
        } finally {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    throw "timeout after $TimeoutSeconds seconds"
}

foreach ($appName in $appsToRemove) {
    Write-Host "    [CHECK]   $appName" -ForegroundColor DarkGray

    $packages = @(Get-AppxPackage -Name $appName -AllUsers -ErrorAction SilentlyContinue)
    $foundPackage = $packages.Count -gt 0

    if ($foundPackage) {
        foreach ($pkg in $packages) {
            try {
                Write-Host "    [REMOVE]  $($pkg.PackageFullName)"
                Remove-AppxPackageWithTimeout -PackageFullName $pkg.PackageFullName -TimeoutSeconds $perAppTimeoutSeconds
                $removedPackages++
                Write-Host "    [REMOVED] $($pkg.PackageFullName)"
            } catch {
                $errors++
                Write-Host "    [ERROR]   $($pkg.PackageFullName) - $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $appName })

    if ($provisioned.Count -gt 0) {
        foreach ($prov in $provisioned) {
            try {
                Write-Host "    [DEPROV]  $($prov.PackageName)"
                Remove-AppxProvisionedPackageWithTimeout -PackageName $prov.PackageName -TimeoutSeconds $perProvTimeoutSeconds
                $removedProvisioned++
                Write-Host "    [REMOVED] $($prov.PackageName)"
            } catch {
                $errors++
                Write-Host "    [ERROR]   $($prov.PackageName) - $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }

    if (-not $foundPackage -and $provisioned.Count -eq 0) {
        $notFound++
        Write-Host "    [NOT FOUND] $appName" -ForegroundColor Gray
    }
}

Write-Host "    Summary: $removedPackages installed package(s) removed, $removedProvisioned provisioned package(s) removed, $errors error(s), $notFound app id(s) not found"
