# opt_edge_uninstall.ps1 - Microsoft Edge uninstall (WinUtil-inspired method)
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
$geoPaths = @(
    'Registry::HKEY_USERS\.DEFAULT\Control Panel\International\Geo'
    'HKCU:\Control Panel\International\Geo'
)
$tempGeoNation = '68' # Ireland / EEA
$policyFile = Join-Path $env:SystemRoot 'System32\IntegratedServicesRegionPolicySet.json'
$policyTemp = "$policyFile.win_deslopper.bak"

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

function Get-EdgeUninstallCommand {
    foreach ($key in $edgeClientStateKeys) {
        if (-not (Test-Path $key)) { continue }

        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
        } catch {
            continue
        }

        if ($props.UninstallString) {
            $filePath = ([string]$props.UninstallString).Trim('"')
            if (-not (Test-Path $filePath)) {
                continue
            }

            return [PSCustomObject]@{
                FilePath  = $filePath
                Arguments = [string]$props.UninstallArguments
            }
        }
    }

    foreach ($root in $edgeRoots) {
        if (-not (Test-Path $root)) { continue }

        $setup = Get-ChildItem -Path (Join-Path $root '*\Installer\setup.exe') -ErrorAction SilentlyContinue |
                 Sort-Object { [version]($_.Directory.Parent.Name) } -Descending |
                 Select-Object -First 1
        if ($setup) {
            return [PSCustomObject]@{
                FilePath  = $setup.FullName
                Arguments = '--uninstall --msedge --system-level --force-uninstall --delete-profile'
            }
        }
    }

    return $null
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

Write-Host "    Looking for Microsoft Edge..."

if (-not (Test-EdgeInstalled)) {
    Write-Host "    Edge not found (already removed or non-standard path)." -ForegroundColor Gray
    return
}

$uninstallCommand = Get-EdgeUninstallCommand
if (-not $uninstallCommand) {
    Write-Host "    Unable to locate Edge uninstall metadata." -ForegroundColor Yellow
    return
}

$originalGeoNation = @{}
foreach ($geoPath in $geoPaths) {
    if (Test-Path $geoPath) {
        try {
            $originalGeoNation[$geoPath] = [string](Get-ItemProperty -Path $geoPath -Name Nation -ErrorAction Stop).Nation
        } catch {}
    }
}

$policyAcl = $null
$policyMoved = $false

try {
    foreach ($procName in @('msedge', 'MicrosoftEdgeUpdate', 'widgets', 'msedgewebview2')) {
        Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    foreach ($geoPath in $originalGeoNation.Keys) {
        Set-ItemProperty -Path $geoPath -Name Nation -Value $tempGeoNation -Type String -Force
    }
    if ($originalGeoNation.Count -gt 0) {
        Write-Host "    Region forced : Ireland (EEA) during Edge uninstall"
    }

    foreach ($key in $edgeUpdateDevKeys) {
        if (-not (Test-Path $key)) {
            New-Item -Path $key -Force | Out-Null
        }
        Set-ItemProperty -Path $key -Name AllowUninstall -Value 1 -Type DWord -Force
    }

    foreach ($key in $edgeUninstallKeys) {
        if (Test-Path $key) {
            Remove-ItemProperty -Path $key -Name NoRemove -ErrorAction SilentlyContinue
        }
    }

    if ((-not (Test-Path $policyFile)) -and (Test-Path $policyTemp)) {
        Rename-Item -Path $policyTemp -NewName (Split-Path $policyFile -Leaf) -Force -ErrorAction SilentlyContinue
    } elseif (Test-Path $policyTemp) {
        Remove-Item -Path $policyTemp -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $policyFile) {
        $policyAcl = Get-Acl -Path $policyFile

        $adminAccount = ([System.Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([System.Security.Principal.NTAccount]).Value
        $tempAcl = New-Object System.Security.AccessControl.FileSecurity
        $tempAcl.SetSecurityDescriptorSddlForm($policyAcl.Sddl)
        $tempAcl.SetOwner([System.Security.Principal.NTAccount]$adminAccount)
        $tempAcl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adminAccount, 'FullControl', 'Allow')))
        Set-Acl -Path $policyFile -AclObject $tempAcl

        Rename-Item -Path $policyFile -NewName (Split-Path $policyTemp -Leaf) -Force
        $policyMoved = $true
        Write-Host "    Policy file   : temporarily hidden during uninstall"
    }

    $filePath = $uninstallCommand.FilePath.Trim('"')
    $argumentList = [string]$uninstallCommand.Arguments
    if ($argumentList -notmatch '(?i)--force-uninstall') {
        $argumentList = ($argumentList + ' --force-uninstall').Trim()
    }
    if ($argumentList -notmatch '(?i)--delete-profile') {
        $argumentList = ($argumentList + ' --delete-profile').Trim()
    }

    Write-Host "    Launching Edge uninstall..."
    $proc = Start-Process -FilePath $filePath -ArgumentList $argumentList -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    Write-Host "    Exit code      : $($proc.ExitCode)"
} catch {
    Write-Host "    [WARNING] Edge uninstall hit an error: $($_.Exception.Message)" -ForegroundColor Yellow
} finally {
    if ($policyMoved -and (Test-Path $policyTemp)) {
        Rename-Item -Path $policyTemp -NewName (Split-Path $policyFile -Leaf) -Force -ErrorAction SilentlyContinue
    }

    if ($policyAcl -and (Test-Path $policyFile)) {
        Set-Acl -Path $policyFile -AclObject $policyAcl -ErrorAction SilentlyContinue
    }

    foreach ($geoPath in $originalGeoNation.Keys) {
        Set-ItemProperty -Path $geoPath -Name Nation -Value $originalGeoNation[$geoPath] -Type String -Force -ErrorAction SilentlyContinue
    }
}

if (Test-EdgeInstalled) {
    Write-Host "    [WARNING] Edge is still present after the WinUtil-style uninstall flow." -ForegroundColor Yellow
    Write-Host "              Edge has been unlocked for removal, so retrying from Settings may now work." -ForegroundColor Yellow
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
