# opt_edge_uninstall.ps1 - Microsoft Edge + WebView2 Runtime uninstall
# OPTIONAL - called only if confirmed by the user in run_all.ps1

$edgeRoots = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
    "$env:ProgramFiles\Microsoft\Edge\Application"
    "$env:LOCALAPPDATA\Microsoft\Edge\Application"
)
$edgeUninstallKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
)
$edgeUpdateDevKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev'
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdateDev'
)
$dummyEdgePath = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"
$dummyEdgeExe  = Join-Path $dummyEdgePath 'MicrosoftEdge.exe'
$webView2DisplayName = 'Microsoft Edge WebView2 Runtime'
$webView2AppGuid     = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
$webView2Roots = @(
    "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application"
    "$env:ProgramFiles\Microsoft\EdgeWebView\Application"
    "$env:LOCALAPPDATA\Microsoft\EdgeWebView\Application"
)
$webView2ClientKeys = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$webView2AppGuid"
    "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$webView2AppGuid"
    "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$webView2AppGuid"
)
$webView2BlockPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
$webView2InstallPolicy   = "Install$webView2AppGuid"
$webView2UpdatePolicy    = "Update$webView2AppGuid"

function Get-UninstallEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue
}

function Get-UninstallEntryByName {
    param([Parameter(Mandatory = $true)][string]$DisplayNamePattern)

    Get-UninstallEntries |
        Where-Object { $_.DisplayName -like $DisplayNamePattern } |
        Select-Object -First 1
}

function Test-EdgeInstalled {
    foreach ($root in $edgeRoots) {
        if (-not (Test-Path $root)) { continue }

        if (Test-Path (Join-Path $root 'msedge.exe')) {
            return $true
        }

        $exe = Get-ChildItem -Path $root -Filter 'msedge.exe' -Recurse -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($exe) {
            return $true
        }
    }

    return $false
}

function Get-EdgeUninstallInfo {
    foreach ($key in $edgeUninstallKeys) {
        if (-not (Test-Path $key)) { continue }

        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
        } catch {
            continue
        }

        if ($props.UninstallString) {
            return [PSCustomObject]@{
                Key             = $key
                UninstallString = [string]$props.UninstallString
            }
        }
    }

    return $null
}

function Get-EdgeSetupCandidates {
    $patterns = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe"
        "$env:ProgramFiles\Microsoft\Edge\Application\*\Installer\setup.exe"
        "$env:LOCALAPPDATA\Microsoft\Edge\Application\*\Installer\setup.exe"
    )

    return Get-ChildItem -Path $patterns -ErrorAction SilentlyContinue |
        Sort-Object FullName -Unique
}

function Test-WebView2Installed {
    foreach ($key in $webView2ClientKeys) {
        if (-not (Test-Path $key)) { continue }

        try {
            $version = [string](Get-ItemPropertyValue -Path $key -Name 'pv' -ErrorAction Stop)
        } catch {
            $version = $null
        }

        if ($version -and $version -ne '0.0.0.0') {
            return $true
        }
    }

    foreach ($root in $webView2Roots) {
        if (-not (Test-Path $root)) { continue }

        if (Test-Path (Join-Path $root 'msedgewebview2.exe')) {
            return $true
        }

        $exe = Get-ChildItem -Path $root -Filter 'msedgewebview2.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($exe) {
            return $true
        }
    }

    if (Get-UninstallEntryByName -DisplayNamePattern "$webView2DisplayName*") {
        return $true
    }

    return $false
}

function Get-WebView2UninstallInfo {
    $entry = Get-UninstallEntryByName -DisplayNamePattern "$webView2DisplayName*"
    if (-not $entry) {
        return $null
    }

    $uninstallString = if ($entry.QuietUninstallString) {
        [string]$entry.QuietUninstallString
    } else {
        [string]$entry.UninstallString
    }

    if (-not $uninstallString) {
        return $null
    }

    return [PSCustomObject]@{
        DisplayName     = [string]$entry.DisplayName
        Key             = [string]$entry.PSPath
        UninstallString = $uninstallString
    }
}

function Get-WebView2SetupCandidates {
    $patterns = @(
        "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application\*\Installer\setup.exe"
        "$env:ProgramFiles\Microsoft\EdgeWebView\Application\*\Installer\setup.exe"
        "$env:LOCALAPPDATA\Microsoft\EdgeWebView\Application\*\Installer\setup.exe"
    )

    return Get-ChildItem -Path $patterns -ErrorAction SilentlyContinue |
        Sort-Object FullName -Unique
}

function Uninstall-MsiexecAppByName {
    param([Parameter(Mandatory = $true)][string]$Name)

    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $apps = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq $Name -and $_.UninstallString -match 'MsiExec\.exe' }

    foreach ($app in $apps) {
        Write-Host "    MSI uninstall : $($app.DisplayName)"
        Start-Process -FilePath msiexec.exe -ArgumentList "/X$($app.PSChildName) /quiet" -Wait -NoNewWindow -ErrorAction SilentlyContinue
    }
}

function Remove-EdgeShortcuts {
    $shortcutPaths = @(
        (Join-Path $env:PUBLIC 'Desktop\Microsoft Edge.lnk')
        (Join-Path $env:USERPROFILE 'Desktop\Microsoft Edge.lnk')
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk')
    )

    foreach ($path in $shortcutPaths) {
        if (Test-Path $path) {
            Remove-Item $path -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-InstallerCommand {
    param([Parameter(Mandatory = $true)][string]$CommandLine)

    Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
        -ArgumentList "/c start /wait `"`" $CommandLine" `
        -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
}

function Uninstall-Edge {
    $uninstallInfo = Get-EdgeUninstallInfo
    $msiChecked = $false

    try {
        foreach ($key in $edgeUpdateDevKeys) {
            if (-not (Test-Path $key)) {
                New-Item -Path $key -Force | Out-Null
            }

            Set-ItemProperty -Path $key -Name AllowUninstall -Value '' -Type String -Force
        }

        foreach ($key in $edgeUninstallKeys) {
            if (Test-Path $key) {
                Set-ItemProperty -Path $key -Name NoRemove -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }

        if ($uninstallInfo) {
            Remove-ItemProperty -Path $uninstallInfo.Key -Name experiment_control_labels -ErrorAction SilentlyContinue
        }

        # Create a dummy legacy UWP Edge file to unlock the Chromium Edge uninstaller (WinUtil method)
        if (-not (Test-Path $dummyEdgePath)) {
            New-Item -Path $dummyEdgePath -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path $dummyEdgeExe)) {
            New-Item -Path $dummyEdgeExe -ItemType File -Force | Out-Null
            Write-Host "    Dummy UWP file : created to unlock Edge uninstaller"
        }

        Uninstall-MsiexecAppByName -Name 'Microsoft Edge'
        $msiChecked = $true

        if ($uninstallInfo -and (Test-EdgeInstalled)) {
            $commandLine = $uninstallInfo.UninstallString
            if ($commandLine -notmatch '(?i)--force-uninstall') {
                $commandLine += ' --force-uninstall'
            }
            if ($commandLine -notmatch '(?i)--delete-profile') {
                $commandLine += ' --delete-profile'
            }

            Write-Host "    Launching Edge uninstall..."
            $proc = Invoke-InstallerCommand -CommandLine $commandLine
            Write-Host "    Exit code      : $($proc.ExitCode)"
        }

        if (Test-EdgeInstalled) {
            foreach ($setup in Get-EdgeSetupCandidates) {
                $scope = if ($setup.FullName -like "$env:LOCALAPPDATA*") { '--user-level' } else { '--system-level' }
                $commandLine = "`"$($setup.FullName)`" --uninstall --force-uninstall $scope --verbose-logging --delete-profile --msedge --channel=stable"

                Write-Host "    Fallback setup : $($setup.FullName)"
                $proc = Invoke-InstallerCommand -CommandLine $commandLine
                Write-Host "    Exit code      : $($proc.ExitCode)"

                if (-not (Test-EdgeInstalled)) {
                    break
                }
            }
        }
    } catch {
        Write-Host "    [WARNING] Edge uninstall hit an error: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if (Test-EdgeInstalled) {
        Write-Host "    [WARNING] Edge is still present after the uninstall flow." -ForegroundColor Yellow
        if (-not $msiChecked) {
            Write-Host "              MSI-based uninstall was not attempted." -ForegroundColor Yellow
        }
        Write-Host "              You can retry removal manually from Settings > Apps." -ForegroundColor Yellow
        return $false
    }

    Remove-EdgeShortcuts

    $edgeUpdatePath = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
    if (-not (Test-Path $edgeUpdatePath)) {
        New-Item -Path $edgeUpdatePath -Force | Out-Null
    }
    Set-ItemProperty -Path $edgeUpdatePath -Name 'DoNotUpdateToEdgeWithChromium' -Value 1 -Type DWord -ErrorAction SilentlyContinue

    Write-Host "    Edge removed   : Microsoft Edge is no longer detected."
    Write-Host "    Reinstall block: best-effort EdgeUpdate registry key applied."
    return $true
}

function Invoke-WebView2Setup {
    param(
        [Parameter(Mandatory = $true)][string]$SetupExe,
        [Parameter(Mandatory = $true)][string]$Scope
    )

    $argList = "--uninstall --msedgewebview $Scope --verbose-logging --force-uninstall"
    $proc = Start-Process -FilePath $SetupExe -ArgumentList $argList -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    return $proc
}

function Uninstall-WebView2 {
    # Kill lingering WebView2 and EdgeUpdate processes before attempting
    Get-Process -Name @('msedgewebview2', 'MicrosoftEdgeUpdate') -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    $tried = $false

    try {
        $uninstallInfo = Get-WebView2UninstallInfo

        if ($uninstallInfo) {
            $raw   = $uninstallInfo.UninstallString
            $scope = if ($uninstallInfo.Key -like '*HKEY_CURRENT_USER*') { '--user-level' } else { '--system-level' }

            # Extract setup.exe path cleanly and call it directly (avoids cmd.exe quoting issues)
            $setupExe = $null
            if ($raw -match '^"([^"]+)"') {
                $setupExe = $Matches[1]
            } elseif ($raw -match '^([^\s]+setup\.exe)') {
                $setupExe = $Matches[1]
            }

            if ($setupExe -and (Test-Path $setupExe)) {
                Write-Host "    Launching WebView2 uninstall..."
                $proc = Invoke-WebView2Setup -SetupExe $setupExe -Scope $scope
                Write-Host "    Exit code      : $($proc.ExitCode)"
                $tried = $true
            }
        }

        if (-not $tried -or (Test-WebView2Installed)) {
            foreach ($setup in Get-WebView2SetupCandidates) {
                $scope = if ($setup.FullName -like "$env:LOCALAPPDATA*") { '--user-level' } else { '--system-level' }

                Write-Host "    Fallback setup : $($setup.FullName)"
                $proc = Invoke-WebView2Setup -SetupExe $setup.FullName -Scope $scope
                Write-Host "    Exit code      : $($proc.ExitCode)"

                if (-not (Test-WebView2Installed)) {
                    break
                }
            }
        }
    } catch {
        Write-Host "    [WARNING] WebView2 uninstall hit an error: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if (Test-WebView2Installed) {
        Write-Host "    [WARNING] WebView2 Runtime is still present after the uninstall flow." -ForegroundColor Yellow
        Write-Host "              Windows 11 or apps that depend on WebView2 can reinstall it." -ForegroundColor Yellow
        return $false
    }

    if (-not (Test-Path $webView2BlockPolicyPath)) {
        New-Item -Path $webView2BlockPolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $webView2BlockPolicyPath -Name $webView2InstallPolicy -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $webView2BlockPolicyPath -Name $webView2UpdatePolicy -Value 0 -Type DWord -Force

    Write-Host "    WebView2 removed: Microsoft Edge WebView2 Runtime is no longer detected."
    Write-Host "    Reinstall block: best-effort EdgeUpdate policy values applied."
    Write-Host "    Note           : Windows 11 or WebView2-dependent apps may still bring it back." -ForegroundColor DarkGray
    return $true
}

foreach ($procName in @('msedge', 'MicrosoftEdgeUpdate', 'widgets', 'msedgewebview2')) {
    Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

$edgeInstalled = Test-EdgeInstalled
$webView2Installed = Test-WebView2Installed

if (-not $edgeInstalled -and -not $webView2Installed) {
    Write-Host "    Edge / WebView2 not found (already removed or non-standard path)." -ForegroundColor Gray
    return
}

if ($edgeInstalled) {
    Write-Host "    Looking for Microsoft Edge..."
    Uninstall-Edge | Out-Null
} else {
    Write-Host "    Edge not found (already removed or non-standard path)." -ForegroundColor Gray
}

if ($webView2Installed) {
    Write-Host "    Looking for Microsoft Edge WebView2 Runtime..."
    Uninstall-WebView2 | Out-Null
} else {
    Write-Host "    WebView2 Runtime not found." -ForegroundColor Gray
}
