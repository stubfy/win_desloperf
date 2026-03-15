# 08_debloat.ps1 - Remove bloatware UWP apps from Windows 11 25H2
#
# Two removal steps per app:
#   1. Remove-AppxPackage: removes the installed package for the current user.
#   2. Remove-AppxProvisionedPackage: removes the provisioned (staged) package
#      so that the app is not reinstalled when a new user account is created.
#
# Timeout wrapper: AppX removal calls can silently hang forever on some builds.
# Invoke-WithTimeout runs each removal in a separate PowerShell runspace and
# aborts it after the configured deadline, preventing a single stuck app from
# blocking the entire script.
#
# Known-process kill: Some apps hold open file handles that block DISM from
# removing the package. Stop-KnownAppProcesses terminates the relevant processes
# by name before attempting removal. The process list in $knownProcesses covers
# the common cases; unknown processes are left running (removal will still succeed
# for most packages as long as the app is not actively executing code in the target).
#
# Rollback: removed packages are NOT automatically restored (UWP packages are not
# backed up). To reinstall: Settings > Apps > Get more apps, or
# Get-AppxPackage -AllUsers | Remove-AppxPackage -AllUsers (full reinstall via Store).
# restore\10_debloat_restore.ps1 provides reinstall guidance.

$appsToRemove = @(
    # ----- Xbox / Gaming Overlay -----
    # These are the Xbox Game Bar components. Game Bar injects hooks into DX apps;
    # disabled via registry in 02_registry.ps1 (GameDVR) but packages removed here
    # to fully eliminate the background processes and injection surface.
    'Microsoft.XboxGamingOverlay'       # Xbox Game Bar (the overlay itself)
    'Microsoft.XboxGameOverlay'         # Xbox Game Overlay renderer helper
    'Microsoft.XboxSpeechToTextOverlay' # Xbox speech-to-text overlay
    'Microsoft.Xbox.TCUI'               # Xbox Title-callable UI framework
    'Microsoft.XboxIdentityProvider'    # Xbox identity/sign-in provider
    'Microsoft.GamingApp'               # Xbox app / Microsoft Gaming Services launcher

    # ----- Microsoft Bloatware -----
    'Microsoft.Getstarted'              # "Get Started" / Tips app
    'Microsoft.WindowsFeedbackHub'      # Feedback Hub (telemetry collection UI)
    'Microsoft.GetHelp'                 # Get Help virtual assistant
    'Microsoft.People'                  # People / Contacts app
    'Microsoft.MicrosoftSolitaireCollection' # Solitaire (ad-supported)
    'Microsoft.BingNews'                # News app (Bing-powered)
    'Microsoft.BingWeather'             # Weather app (Bing-powered)
    'Microsoft.BingSearch'              # Bing Search integration
    'Microsoft.549981C3F5F10'           # Cortana voice assistant
    'Microsoft.MicrosoftTeams'          # Teams (classic consumer / personal)
    'MicrosoftTeams'                    # Teams alternate package name
    'MSTeams'                           # Teams new package name (25H2+)
    'Microsoft.MicrosoftOfficeHub'      # Microsoft 365 / Office marketing hub
    'MicrosoftCorporationII.MicrosoftFamily' # Microsoft Family Safety
    'MicrosoftCorporationII.QuickAssist'     # Quick Assist remote support tool
    'Microsoft.WindowsSoundRecorder'    # Sound Recorder / Voice Recorder
    'Microsoft.MicrosoftStickyNotes'    # Sticky Notes
    'Microsoft.WindowsAlarms'           # Clock and Alarms
    'Microsoft.WindowsCamera'           # Camera app (replaced by camsvc if needed)
    'Microsoft.Todos'                   # Microsoft To Do
    'Microsoft.WindowsMaps'             # Maps app (requires internet; offline useless)
    'Microsoft.ZuneMusic'               # Groove Music / Media Player (legacy package)
    'Microsoft.ZuneVideo'               # Movies & TV (legacy package)
    'Microsoft.YourPhone'               # Phone Link (Android/iPhone companion app)
    'Microsoft.Phone'                   # Phone companion alternate package
    'Clipchamp.Clipchamp'               # Clipchamp video editor
    'Microsoft.PowerAutomateDesktop'    # Power Automate Desktop (RPA tool)
    'Microsoft.Copilot'                 # Copilot AI assistant UWP package
    'Microsoft.OutlookForWindows'       # New Outlook (web-wrapped)

    # ----- Widgets -----
    # Also disabled via AllowNewsAndInterests policy in 02_registry.ps1.
    # Both layers (policy + package removal) are applied because the policy
    # can be overridden by a Windows Update that re-provisions the package,
    # while removing the package eliminates the WidgetService background process.
    'MicrosoftWindows.Client.WebExperience' # Widgets panel (news feed)
    'Microsoft.WidgetsPlatformRuntime'      # Widgets platform runtime
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

    # Prefer bundle packages over individual sub-packages: removing a bundle
    # removes all contained packages in one operation. Fall back to individual
    # packages only if no bundle is found.
    $bundles = @($script:packageCache | Where-Object { $_.Name -eq $AppName -and $_.IsBundle })
    if ($bundles.Count -gt 0) { return $bundles }

    return @($script:packageCache | Where-Object { $_.Name -eq $AppName -and -not $_.IsBundle })
}

# Upfront cache: single queries for all installed and provisioned packages.
# Avoids repeated WMI/DISM calls that are slow on large package sets.
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
