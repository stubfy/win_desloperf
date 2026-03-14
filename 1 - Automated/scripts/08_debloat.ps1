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
    'MSTeams'
    'Microsoft.MicrosoftOfficeHub'      # Microsoft 365 / Office hub
    'MicrosoftCorporationII.MicrosoftFamily'
    'MicrosoftCorporationII.QuickAssist'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.MicrosoftStickyNotes'
    'Microsoft.WindowsAlarms'           # Clock / Alarms
    'Microsoft.WindowsCamera'
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

$removedPackages       = 0
$removedProvisioned    = 0
$errors                = 0
$notFound              = 0
$perAppTimeoutSeconds  = 30
$perProvTimeoutSeconds = 45

function Invoke-WithTimeout {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $true)][object[]]$Arguments,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $ps = [PowerShell]::Create()
    $ps.AddScript($ScriptBlock) | Out-Null
    foreach ($arg in $Arguments) { $ps.AddArgument($arg) | Out-Null }

    $async = $ps.BeginInvoke()
    if ($async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
        try {
            $ps.EndInvoke($async) | Out-Null
            if ($ps.HadErrors) { throw $ps.Streams.Error[0].Exception }
            return $true
        } finally {
            $ps.Dispose()
        }
    }

    $ps.Stop()
    $ps.Dispose()
    throw "timeout after $TimeoutSeconds seconds"
}

$knownProcesses = @{
    'Microsoft.XboxGamingOverlay'           = @('GameBar', 'GameBarFTServer', 'GameBarPresenceWriter', 'XboxPcApp')
    'Microsoft.GamingApp'                   = @('XboxPcApp')
    'Microsoft.MicrosoftTeams'              = @('ms-teams', 'Teams')
    'MicrosoftTeams'                        = @('ms-teams', 'Teams')
    'MSTeams'                               = @('ms-teams', 'Teams')
    'MicrosoftCorporationII.QuickAssist'    = @('QuickAssist')
    'Microsoft.YourPhone'                   = @('YourPhone', 'PhoneExperienceHost')
    'Microsoft.Copilot'                     = @('Copilot')
    'Microsoft.OutlookForWindows'           = @('olk')
    'MicrosoftWindows.Client.WebExperience' = @('Widgets', 'WidgetService')
    'Microsoft.BingSearch'                  = @('SearchApp')
}

function Stop-KnownAppProcesses {
    param([Parameter(Mandatory = $true)][string]$AppName)

    if ($knownProcesses.ContainsKey($AppName)) {
        foreach ($procName in $knownProcesses[$AppName]) {
            Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-AppxRemovalTargets {
    param([Parameter(Mandatory = $true)][string]$AppName)

    $bundles = @($script:packageCache | Where-Object { $_.Name -eq $AppName -and $_.IsBundle })
    if ($bundles.Count -gt 0) { return $bundles }

    return @($script:packageCache | Where-Object { $_.Name -eq $AppName -and -not $_.IsBundle })
}

# Upfront cache: single queries for all installed and provisioned packages
Write-Host "    [CACHE]   Loading installed packages..." -ForegroundColor DarkGray
$script:packageCache = @(Get-AppxPackage -ErrorAction SilentlyContinue)
Write-Host "    [CACHE]   $($script:packageCache.Count) installed package(s) loaded" -ForegroundColor DarkGray

Write-Host "    [CACHE]   Loading provisioned packages..." -ForegroundColor DarkGray
$script:provisionedCache = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
Write-Host "    [CACHE]   $($script:provisionedCache.Count) provisioned package(s) loaded" -ForegroundColor DarkGray

foreach ($appName in $appsToRemove) {
    Write-Host "    [CHECK]   $appName" -ForegroundColor DarkGray

    $packages    = @(Get-AppxRemovalTargets -AppName $appName)
    $provisioned = @($script:provisionedCache | Where-Object { $_.DisplayName -eq $appName })

    if ($packages.Count -eq 0 -and $provisioned.Count -eq 0) {
        $notFound++
        Write-Host "    [NOT FOUND] $appName" -ForegroundColor Gray
        continue
    }

    Stop-KnownAppProcesses -AppName $appName

    foreach ($pkg in $packages) {
        try {
            Write-Host "    [REMOVE]  $($pkg.PackageFullName)"
            Invoke-WithTimeout -ScriptBlock {
                param($pfn)
                Remove-AppxPackage -Package $pfn -ErrorAction Stop
            } -Arguments @($pkg.PackageFullName) -TimeoutSeconds $perAppTimeoutSeconds
            $removedPackages++
            Write-Host "    [REMOVED] $($pkg.PackageFullName)"
        } catch {
            $errors++
            Write-Host "    [ERROR]   $($pkg.PackageFullName) - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    foreach ($prov in $provisioned) {
        try {
            Write-Host "    [DEPROV]  $($prov.PackageName)"
            Invoke-WithTimeout -ScriptBlock {
                param($pkg)
                Remove-AppxProvisionedPackage -Online -PackageName $pkg -ErrorAction Stop | Out-Null
            } -Arguments @($prov.PackageName) -TimeoutSeconds $perProvTimeoutSeconds
            $removedProvisioned++
            Write-Host "    [REMOVED] $($prov.PackageName)"
        } catch {
            $errors++
            Write-Host "    [ERROR]   $($prov.PackageName) - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host "    Summary: $removedPackages installed package(s) removed, $removedProvisioned provisioned package(s) removed, $errors error(s), $notFound app id(s) not found"
