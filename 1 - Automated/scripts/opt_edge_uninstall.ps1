# opt_edge_uninstall.ps1 - Microsoft Edge uninstall (WinUtil / EdgeRemover-aligned)
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
$edgeClientStateKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\ClientState\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\ClientState\{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
)
$edgeUpdateDevKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev'
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdateDev'
)
$policyFile = Join-Path $env:SystemRoot 'System32\IntegratedServicesRegionPolicySet.json'
$policyBackup = "$policyFile.win_deslopper.bak"
$edgePolicyGuid = '{1bca2783-0de6-4269-b2b2-4bfdd4e492e5}'

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
        "${env:ProgramFiles(x86)}\Microsoft\Edge*\Application\*\Installer\setup.exe"
        "$env:ProgramFiles\Microsoft\Edge*\Application\*\Installer\setup.exe"
        "$env:LOCALAPPDATA\Microsoft\Edge*\Application\*\Installer\setup.exe"
    )

    return Get-ChildItem -Path $patterns -ErrorAction SilentlyContinue |
        Sort-Object FullName -Unique
}

function Grant-AdminWriteAccess {
    param([Parameter(Mandatory = $true)][string]$Path)

    $originalAcl = Get-Acl -Path $Path
    $adminAccount = ([System.Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([System.Security.Principal.NTAccount]).Value

    $tempAcl = New-Object System.Security.AccessControl.FileSecurity
    $tempAcl.SetSecurityDescriptorSddlForm($originalAcl.Sddl)
    $tempAcl.SetOwner([System.Security.Principal.NTAccount]$adminAccount)
    $tempAcl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminAccount, 'FullControl', 'Allow')))
    Set-Acl -Path $Path -AclObject $tempAcl

    return $originalAcl
}

function Restore-OriginalAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Acl
    )

    if (Test-Path $Path) {
        Set-Acl -Path $Path -AclObject $Acl -ErrorAction SilentlyContinue
    }
}

function Get-PatchedRegionPolicyContent {
    param([Parameter(Mandatory = $true)][string]$Content)

    $index = $Content.IndexOf($edgePolicyGuid, [System.StringComparison]::OrdinalIgnoreCase)
    $regex = [regex]::new('"defaultState":"disabled"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    if ($index -lt 0) {
        return $regex.Replace($Content, '"defaultState":"enabled"', 1)
    }

    $head = $Content.Substring(0, $index)
    $tail = $Content.Substring($index)
    $tail = $regex.Replace($tail, '"defaultState":"enabled"', 1)
    return $head + $tail
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

function Invoke-EdgeUninstallCommand {
    param([Parameter(Mandatory = $true)][string]$CommandLine)

    Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" `
        -ArgumentList "/c start /wait `"`" $CommandLine" `
        -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
}

Write-Host "    Looking for Microsoft Edge..."

if (-not (Test-EdgeInstalled)) {
    Write-Host "    Edge not found (already removed or non-standard path)." -ForegroundColor Gray
    return
}

$uninstallInfo = Get-EdgeUninstallInfo
$policyAcl = $null
$policyPatched = $false
$msiChecked = $false

try {
    foreach ($procName in @('msedge', 'MicrosoftEdgeUpdate', 'widgets', 'msedgewebview2')) {
        Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

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

    if (Test-Path $policyBackup) {
        Remove-Item -Path $policyBackup -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $policyFile) {
        $policyAcl = Grant-AdminWriteAccess -Path $policyFile
        Rename-Item -Path $policyFile -NewName (Split-Path $policyBackup -Leaf) -Force

        $policyContent = Get-Content -Path $policyBackup -Raw -Encoding UTF8
        $patchedContent = Get-PatchedRegionPolicyContent -Content $policyContent
        Set-Content -Path $policyFile -Value $patchedContent -Encoding UTF8

        $policyPatched = $true
        Write-Host "    Policy file   : Edge uninstall gate patched"
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
        $proc = Invoke-EdgeUninstallCommand -CommandLine $commandLine
        Write-Host "    Exit code      : $($proc.ExitCode)"
    }

    if (Test-EdgeInstalled) {
        foreach ($setup in Get-EdgeSetupCandidates) {
            $scope = if ($setup.FullName -like "$env:LOCALAPPDATA*") { '--user-level' } else { '--system-level' }
            $commandLine = "`"$($setup.FullName)`" --uninstall --force-uninstall $scope --verbose-logging --delete-profile --msedge --channel=stable"

            Write-Host "    Fallback setup : $($setup.FullName)"
            $proc = Invoke-EdgeUninstallCommand -CommandLine $commandLine
            Write-Host "    Exit code      : $($proc.ExitCode)"

            if (-not (Test-EdgeInstalled)) {
                break
            }
        }
    }
} catch {
    Write-Host "    [WARNING] Edge uninstall hit an error: $($_.Exception.Message)" -ForegroundColor Yellow
} finally {
    if ($policyPatched -and (Test-Path $policyBackup)) {
        Remove-Item -Path $policyFile -Force -ErrorAction SilentlyContinue
        Rename-Item -Path $policyBackup -NewName (Split-Path $policyFile -Leaf) -Force -ErrorAction SilentlyContinue
    }

    if ($policyAcl) {
        Restore-OriginalAcl -Path $policyFile -Acl $policyAcl
    }
}

if (Test-EdgeInstalled) {
    Write-Host "    [WARNING] Edge is still present after the EdgeRemover-style uninstall flow." -ForegroundColor Yellow
    if (-not $msiChecked) {
        Write-Host "              MSI-based uninstall was not attempted." -ForegroundColor Yellow
    }
    Write-Host "              Current next step is to inspect the exact uninstall string and package state on the VM." -ForegroundColor Yellow
} else {
    Remove-EdgeShortcuts

    $edgeUpdatePath = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
    if (-not (Test-Path $edgeUpdatePath)) {
        New-Item -Path $edgeUpdatePath -Force | Out-Null
    }
    Set-ItemProperty -Path $edgeUpdatePath -Name 'DoNotUpdateToEdgeWithChromium' -Value 1 -Type DWord -ErrorAction SilentlyContinue

    Write-Host "    Edge removed   : Microsoft Edge is no longer detected."
    Write-Host "    Reinstall block: best-effort EdgeUpdate registry key applied."
}
