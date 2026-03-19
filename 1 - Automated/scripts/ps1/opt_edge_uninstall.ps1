# opt_edge_uninstall.ps1 - Microsoft Edge + WebView2 Runtime uninstall
# OPTIONAL - called only if confirmed by the user in run_all.ps1
#
# Uninstall strategy (WinUtil method, Jan 2026+):
#   Microsoft protects Chromium Edge from being uninstalled by its own setup.exe
#   using two mechanisms:
#     1. The uninstall registry key has a NoRemove=1 flag.
#     2. The setup.exe checks for the presence of the legacy UWP Edge binary
#        (C:\Windows\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe)
#        before allowing itself to proceed.
#
#   This script:
#     a. Clears NoRemove and experiment_control_labels flags from the uninstall key.
#     b. Creates AllowUninstall='' in EdgeUpdateDev registry keys to unlock removal.
#     c. Creates a zero-byte dummy file at the legacy UWP Edge path -- Edge's
#        Chromium installer interprets this as "legacy UWP Edge is present" and
#        allows itself to be uninstalled. The dummy file is intentionally left in
#        place after removal (same behavior as WinUtil); opt_edge_restore.ps1 deletes
#        it during rollback.
#     d. Attempts MSI-based uninstall, then setup.exe --force-uninstall, then
#        enumerates all setup.exe candidates as a fallback.
#
# WebView2 Runtime removal strategy:
#   WebView2 is distributed both as a Win32 package (setup.exe) and as an AppX
#   package (Win32WebViewHost). This script:
#     a. Uses DISM to mark Win32WebViewHost as removable (clears non-removable flag).
#     b. Directly deletes the WebView2 file tree using takeown + icacls to override
#        any access restrictions.
#     c. Cleans up EdgeUpdate client registry keys and uninstall entries.
#     d. Applies a reinstall block (EdgeUpdate policy values Install=0, Update=0).
#
# Reinstall note: Windows 11 and many apps (Teams, Office, some games) depend on
# WebView2. The reinstall block is best-effort; a Microsoft Store update or an
# app installer can restore WebView2 at any time.
#
# Rollback: restore\opt_edge_restore.ps1 opens the browser download page for
# reinstallation; there is no automated rollback for Edge/WebView2 uninstall.

$edgeRoots = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
    "$env:ProgramFiles\Microsoft\Edge\Application"
    "$env:LOCALAPPDATA\Microsoft\Edge\Application"
    # EdgeCore split-install layout introduced in recent Windows 11 builds:
    # Microsoft moved versioned binaries (msedge.exe) out of Edge\Application
    # into a sibling EdgeCore\ directory, leaving Edge\Application empty/absent.
    "${env:ProgramFiles(x86)}\Microsoft\EdgeCore"
    "$env:ProgramFiles\Microsoft\EdgeCore"
    "$env:LOCALAPPDATA\Microsoft\EdgeCore"
)
$edgeUninstallKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
)
$edgeUpdateDevKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev'
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdateDev'
)
$edgeUpdateRoots = @(
    "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate"
    "$env:ProgramFiles\Microsoft\EdgeUpdate"
    "$env:LOCALAPPDATA\Microsoft\EdgeUpdate"
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
    return (@(Get-EdgePresenceEvidence).Count -gt 0)
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
        # EdgeCore split-install layout
        "${env:ProgramFiles(x86)}\Microsoft\EdgeCore\*\Installer\setup.exe"
        "$env:ProgramFiles\Microsoft\EdgeCore\*\Installer\setup.exe"
        "$env:LOCALAPPDATA\Microsoft\EdgeCore\*\Installer\setup.exe"
    )

    return Get-ChildItem -Path $patterns -ErrorAction SilentlyContinue |
        Sort-Object FullName -Unique
}

function Get-EdgePresenceEvidence {
    $evidence = [System.Collections.Generic.List[string]]::new()

    foreach ($root in $edgeRoots) {
        if (-not (Test-Path $root)) { continue }

        if (Test-Path (Join-Path $root 'msedge.exe')) {
            $evidence.Add("launcher under $root")
        }

        $exe = Get-ChildItem -Path $root -Filter 'msedge.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($exe) {
            $evidence.Add("binary $($exe.FullName)")
        }
    }

    foreach ($root in $edgeUpdateRoots) {
        if (Test-Path $root) {
            $evidence.Add("update files under $root")
        }
    }

    foreach ($setup in Get-EdgeSetupCandidates) {
        $evidence.Add("installer $($setup.FullName)")
    }

    foreach ($key in Get-EdgeClientKeys) {
        $evidence.Add("client key $key")
    }

    if (Get-UninstallEntryByName -DisplayNamePattern 'Microsoft Edge*') {
        $evidence.Add('uninstall entry Microsoft Edge')
    }

    return @($evidence | Select-Object -Unique)
}

function Get-WebView2PresenceEvidence {
    $evidence = [System.Collections.Generic.List[string]]::new()

    foreach ($key in $webView2ClientKeys) {
        if (-not (Test-Path $key)) { continue }

        try {
            $version = [string](Get-ItemPropertyValue -Path $key -Name 'pv' -ErrorAction Stop)
        } catch {
            $version = $null
        }

        if ($version -and $version -ne '0.0.0.0') {
            $evidence.Add("client key $key (pv=$version)")
        }
    }

    foreach ($root in $webView2Roots) {
        if (-not (Test-Path $root)) { continue }

        if (Test-Path (Join-Path $root 'msedgewebview2.exe')) {
            $evidence.Add("files under $root")
            continue
        }

        $exe = Get-ChildItem -Path $root -Filter 'msedgewebview2.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($exe) {
            $evidence.Add("files under $root")
        }
    }

    $appxPackages = @(Get-WebView2AppxPackages)
    foreach ($pkg in $appxPackages) {
        $installLocation = [string]$pkg.InstallLocation
        if ($installLocation -and (Test-Path -LiteralPath $installLocation)) {
            $evidence.Add("AppX $($pkg.PackageFullName)")
        }
    }

    try {
        $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*Win32WebViewHost*' })
        foreach ($pkg in $provisioned) {
            $evidence.Add("provisioned $($pkg.PackageName)")
        }
    } catch {
    }

    if (Get-UninstallEntryByName -DisplayNamePattern "$webView2DisplayName*") {
        $evidence.Add("uninstall entry $webView2DisplayName")
    }

    return @($evidence | Select-Object -Unique)
}

function Test-WebView2Installed {
    return (@(Get-WebView2PresenceEvidence).Count -gt 0)
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

function Get-EdgeClientKeys {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\*'
        'HKCU:\Software\Microsoft\EdgeUpdate\Clients\*'
    )

    return @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.name -in @('Microsoft Edge', 'Microsoft Edge Update') } |
        Select-Object -ExpandProperty PSPath -Unique)
}

function Get-WebView2AppxPackages {
    try {
        return @(Get-AppxPackage -AllUsers -Name '*Win32WebViewHost*' -ErrorAction Stop)
    } catch {
        return @()
    }
}

function Remove-RegistryKeys {
    param([Parameter(Mandatory = $true)][string[]]$Keys)

    foreach ($key in $Keys | Select-Object -Unique) {
        if (-not $key) { continue }
        if (Test-Path -LiteralPath $key) {
            Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "    Reg removed    : $key"
        }
    }
}

function Remove-OwnedTree {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }

    Write-Host "    Deleting $Label : $Path"
    & takeown.exe /f "$Path" /r /d y 2>$null | Out-Null
    & icacls.exe "$Path" /grant '*S-1-5-32-544:(F)' /t /c /q 2>$null | Out-Null
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $Path) {
        Write-Host "    [WARNING] Could not fully remove : $Path" -ForegroundColor Yellow
    } else {
        Write-Host "    Deleted        : $Path"
    }
}

function Invoke-InstallerCommand {
    param([Parameter(Mandatory = $true)][string]$CommandLine)

    $trimmed = $CommandLine.Trim()
    $exePath = $null
    $arguments = ''

    if ($trimmed.StartsWith('"')) {
        $endQuote = $trimmed.IndexOf('"', 1)
        if ($endQuote -gt 1) {
            $exePath = $trimmed.Substring(1, $endQuote - 1)
            $arguments = $trimmed.Substring($endQuote + 1).Trim()
        }
    } else {
        $match = [regex]::Match($trimmed, '^(?<exe>\S+\.exe)\s*(?<args>.*)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            $exePath = $match.Groups['exe'].Value
            $arguments = $match.Groups['args'].Value.Trim()
        }
    }

    if (-not $exePath) {
        throw "Unable to parse installer command line: $CommandLine"
    }
    if (-not (Test-Path -LiteralPath $exePath)) {
        throw "Installer not found: $exePath"
    }

    Start-Process -FilePath $exePath -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
}

function Uninstall-Edge {
    $uninstallInfo = Get-EdgeUninstallInfo
    $msiChecked = $false
    $edgeExitCodes = [System.Collections.Generic.List[int]]::new()

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
            $edgeExitCodes.Add([int]$proc.ExitCode)
            Write-Host "    Exit code      : $($proc.ExitCode)"
            # Cancel any pending OS reboot that setup.exe may have scheduled so the
            # parent script can continue to the Defender prompt at the end.
            & shutdown.exe /a 2>$null
        }

        if (Test-EdgeInstalled) {
            foreach ($setup in Get-EdgeSetupCandidates) {
                $scope = if ($setup.FullName -like "$env:LOCALAPPDATA*") { '--user-level' } else { '--system-level' }
                $commandLine = "`"$($setup.FullName)`" --uninstall --force-uninstall $scope --verbose-logging --delete-profile --msedge --channel=stable"

                Write-Host "    Fallback setup : $($setup.FullName)"
                $proc = Invoke-InstallerCommand -CommandLine $commandLine
                $edgeExitCodes.Add([int]$proc.ExitCode)
                Write-Host "    Exit code      : $($proc.ExitCode)"
                & shutdown.exe /a 2>$null

                if (-not (Test-EdgeInstalled)) {
                    break
                }
            }
        }

        Get-Process -Name @('msedge', 'MicrosoftEdgeUpdate', 'widgets', 'msedgewebview2') -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue

        foreach ($dir in $edgeRoots) {
            Remove-OwnedTree -Path $dir -Label 'Edge files'
        }
        foreach ($dir in $edgeUpdateRoots) {
            Remove-OwnedTree -Path $dir -Label 'EdgeUpdate files'
        }

        Remove-RegistryKeys -Keys $edgeUninstallKeys
        Remove-RegistryKeys -Keys (Get-EdgeClientKeys)
        Unregister-ScheduledTask -TaskName 'MicrosoftEdgeUpdate*' -Confirm:$false -ErrorAction SilentlyContinue
    } catch {
        Write-Host "    [WARNING] Edge uninstall hit an error: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if (Test-EdgeInstalled) {
        Write-Host "    [WARNING] Edge is still present after the uninstall flow." -ForegroundColor Yellow
        if (-not $msiChecked) {
            Write-Host "              MSI-based uninstall was not attempted." -ForegroundColor Yellow
        }
        if ($edgeExitCodes.Count -gt 0 -and ($edgeExitCodes | Select-Object -Unique) -contains 0) {
            Write-Host "              Installer exited 0, but Edge is still detected." -ForegroundColor Yellow
        }

        $presenceEvidence = @(Get-EdgePresenceEvidence)
        foreach ($item in ($presenceEvidence | Select-Object -First 3)) {
            Write-Host "              Still detected via: $item" -ForegroundColor Yellow
        }
        if ($presenceEvidence.Count -gt 3) {
            Write-Host "              (+$($presenceEvidence.Count - 3) more evidence point(s))" -ForegroundColor Yellow
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

function Remove-WebView2AppxPackage {
    # Win32WebViewHost is the AppX package that delivers WebView2 on Windows 11.
    # It is marked non-removable by default; DISM can unlock it, then Remove-AppxPackage works.
    $packages = @(Get-WebView2AppxPackages)
    if (-not $packages) { return }

    foreach ($pkg in $packages) {
        Write-Host "    AppX found     : $($pkg.PackageFullName)"

        # Unlock via DISM (set-nonremovableapppolicy)
        $dismArgs = "/online /set-nonremovableapppolicy /packagefamily:$($pkg.PackageFamilyName) /nonremovable:0"
        $dismProc = Start-Process -FilePath dism.exe -ArgumentList $dismArgs -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
        if ($dismProc.ExitCode -eq 0) {
            Write-Host "    DISM unlock    : OK"
        } else {
            Write-Host "    DISM unlock    : exit $($dismProc.ExitCode)" -ForegroundColor Yellow
        }

        # Remove provisioned package (prevents reinstall on new user profiles)
        try {
            $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like '*Win32WebViewHost*' }
            foreach ($p in $prov) {
                Remove-AppxProvisionedPackage -PackageName $p.PackageName -Online -AllUsers -ErrorAction SilentlyContinue | Out-Null
                Write-Host "    Deprovisioned  : $($p.PackageName)"
            }
        } catch {
            Write-Host "    Deprovision    : skipped ($($_.Exception.Message))" -ForegroundColor DarkGray
        }

        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            Write-Host "    AppX removed   : $($pkg.PackageFullName)"
        } catch {
            Write-Host "    AppX removal   : still registered (system app or pending reboot)" -ForegroundColor DarkGray
        }

        $installLocation = [string]$pkg.InstallLocation
        if ($installLocation) {
            Remove-OwnedTree -Path $installLocation -Label 'WebView2 AppX files'
        }
    }
}

function Uninstall-WebView2 {
    $webView2Info = Get-WebView2UninstallInfo
    $webView2ExitCodes = [System.Collections.Generic.List[int]]::new()

    # Kill lingering WebView2 and EdgeUpdate processes before attempting
    Get-Process -Name @('msedgewebview2', 'MicrosoftEdgeUpdate', 'widgets', 'msedge') -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    if ($webView2Info) {
        $commandLine = $webView2Info.UninstallString
        if ($commandLine -notmatch '(?i)--force-uninstall') {
            $commandLine += ' --force-uninstall'
        }

        Write-Host "    Launching WebView2 uninstall..."
        $proc = Invoke-InstallerCommand -CommandLine $commandLine
        $webView2ExitCodes.Add([int]$proc.ExitCode)
        Write-Host "    Exit code      : $($proc.ExitCode)"
        & shutdown.exe /a 2>$null
    }

    if (Test-WebView2Installed) {
        foreach ($setup in Get-WebView2SetupCandidates) {
            $scope = if ($setup.FullName -like "$env:LOCALAPPDATA*") { '--user-level' } else { '--system-level' }
            $commandLine = "`"$($setup.FullName)`" --uninstall --force-uninstall $scope --verbose-logging --msedgewebview"

            Write-Host "    Fallback setup : $($setup.FullName)"
            $proc = Invoke-InstallerCommand -CommandLine $commandLine
            $webView2ExitCodes.Add([int]$proc.ExitCode)
            Write-Host "    Exit code      : $($proc.ExitCode)"
            & shutdown.exe /a 2>$null

            if (-not (Test-WebView2Installed)) {
                break
            }
        }
    }

    # Step 1: DISM unlock + AppX removal (best-effort complement)
    Remove-WebView2AppxPackage

    # Step 2: Direct file deletion — bypass setup.exe entirely
    foreach ($dir in $webView2Roots) {
        if (-not (Test-Path $dir)) { continue }

        Write-Host "    Deleting files : $dir"
        & takeown.exe /f "$dir" /r /d y 2>$null | Out-Null
        & icacls.exe "$dir" /grant '*S-1-5-32-544:(F)' /t /c /q 2>$null | Out-Null
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue

        if (Test-Path $dir) {
            Write-Host "    [WARNING] Could not fully remove : $dir" -ForegroundColor Yellow
        } else {
            Write-Host "    Deleted        : $dir"
        }
    }

    # Step 3: Registry cleanup — EdgeUpdate client keys
    foreach ($key in $webView2ClientKeys) {
        if (Test-Path $key) {
            Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "    Reg removed    : $key"
        }
    }

    $uninstallKeys = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView'
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView'
    )
    foreach ($key in $uninstallKeys) {
        if (Test-Path $key) {
            Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "    Reg removed    : $key"
        }
    }

    # Step 4: Unregister EdgeUpdate scheduled tasks
    Unregister-ScheduledTask -TaskName 'MicrosoftEdgeUpdate*' -Confirm:$false -ErrorAction SilentlyContinue

    # Step 5: Apply reinstall block regardless of whether uninstall succeeded
    $allHives = @('HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node', 'HKCU:\Software')
    foreach ($sw in $allHives) {
        $euPath = "$sw\Microsoft\EdgeUpdate"
        if (-not (Test-Path $euPath)) { New-Item -Path $euPath -Force | Out-Null }
        Set-ItemProperty -Path $euPath -Name "Install$webView2AppGuid" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $euPath -Name "Update$webView2AppGuid" -Value 2 -Type DWord -Force
    }
    if (-not (Test-Path $webView2BlockPolicyPath)) {
        New-Item -Path $webView2BlockPolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $webView2BlockPolicyPath -Name $webView2InstallPolicy -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $webView2BlockPolicyPath -Name $webView2UpdatePolicy -Value 0 -Type DWord -Force

    $presenceEvidence = @(Get-WebView2PresenceEvidence)
    if ($presenceEvidence.Count -gt 0) {
        Write-Host "    [WARNING] WebView2 Runtime is still present after the uninstall flow." -ForegroundColor Yellow
        if ($webView2ExitCodes.Count -gt 0 -and ($webView2ExitCodes | Select-Object -Unique) -contains 0) {
            Write-Host "              Installer exited 0, but WebView2 is still detected." -ForegroundColor Yellow
        }
        foreach ($item in ($presenceEvidence | Select-Object -First 3)) {
            Write-Host "              Still detected via: $item" -ForegroundColor Yellow
        }
        if ($presenceEvidence.Count -gt 3) {
            Write-Host "              (+$($presenceEvidence.Count - 3) more evidence point(s))" -ForegroundColor Yellow
        }
        Write-Host "              You may need to retry after a reboot." -ForegroundColor Yellow
        return $false
    }

    Write-Host "    WebView2 removed: Microsoft Edge WebView2 Runtime is no longer detected."
    Write-Host "    Reinstall block: EdgeUpdate policy values applied."
    return $true
}

foreach ($procName in @('msedge', 'MicrosoftEdgeUpdate', 'widgets', 'msedgewebview2')) {
    Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

# Stop EdgeUpdate services so they cannot re-protect files or restart processes during uninstall
foreach ($svcName in @('edgeupdate', 'edgeupdatem')) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "    Service stopped: $svcName"
    }
}

# Apply EdgeUpdate blocking policies early so they survive a reboot triggered by Edge's setup.exe.
# If setup.exe reboots the system mid-uninstall, these policies prevent Edge/WebView2 from
# reinstalling on the next boot before the script can complete.
$edgeUpdatePath = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
if (-not (Test-Path $edgeUpdatePath)) { New-Item -Path $edgeUpdatePath -Force | Out-Null }
Set-ItemProperty -Path $edgeUpdatePath -Name 'DoNotUpdateToEdgeWithChromium' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

foreach ($key in $edgeUpdateDevKeys) {
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    Set-ItemProperty -Path $key -Name AllowUninstall -Value '' -Type String -Force -ErrorAction SilentlyContinue
}

$allHives = @('HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node', 'HKCU:\Software')
foreach ($sw in $allHives) {
    $euPath = "$sw\Microsoft\EdgeUpdate"
    if (-not (Test-Path $euPath)) { New-Item -Path $euPath -Force | Out-Null }
    Set-ItemProperty -Path $euPath -Name "Install$webView2AppGuid" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $euPath -Name "Update$webView2AppGuid" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path $webView2BlockPolicyPath)) { New-Item -Path $webView2BlockPolicyPath -Force | Out-Null }
Set-ItemProperty -Path $webView2BlockPolicyPath -Name $webView2InstallPolicy -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path $webView2BlockPolicyPath -Name $webView2UpdatePolicy -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "    Reinstall block : EdgeUpdate policies applied."

$edgeInstalled = Test-EdgeInstalled
$webView2Installed = Test-WebView2Installed

if (-not $edgeInstalled -and -not $webView2Installed) {
    Write-Host "    Edge / WebView2 not found (already removed or non-standard path)." -ForegroundColor Gray
    return
}

$edgeOk = $true
$webView2Ok = $true

if ($edgeInstalled) {
    Write-Host "    Looking for Microsoft Edge..."
    $edgeOk = Uninstall-Edge
} else {
    Write-Host "    Edge not found (already removed or non-standard path)." -ForegroundColor Gray
}

if ($webView2Installed) {
    Write-Host "    Looking for Microsoft Edge WebView2 Runtime..."
    $webView2Ok = Uninstall-WebView2
} else {
    Write-Host "    WebView2 Runtime not found." -ForegroundColor Gray
}

if (-not $edgeOk -or -not $webView2Ok) {
    throw 'Edge/WebView2 uninstall incomplete.'
}

