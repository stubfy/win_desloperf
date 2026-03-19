#Requires -RunAsAdministrator
param(
    [switch]$PostUpdateRepair
)

$ErrorActionPreference = 'Continue'
$ROOT                  = Split-Path (Split-Path (Split-Path $MyInvocation.MyCommand.Path))
$TOOLS_ROOT            = Join-Path $ROOT 'tools\remove_windows_ai'
$PACKAGE_ROOT          = Join-Path $TOOLS_ROOT 'RemoveWindowsAIPackage'
$BACKUP_DIR            = Join-Path $ROOT 'backup'
$STATE_FILE            = Join-Path $BACKUP_DIR 'ai_debloat_state.json'
$REGION_POLICY_PATH    = Join-Path $env:windir 'System32\IntegratedServicesRegionPolicySet.json'
$TASK_NAME             = 'AI Cleanup Check'
$TASK_PATH             = '\win_desloperf\'
$TASK_FULL_NAME        = "$TASK_PATH$TASK_NAME"

function Write-Info {
    param([string]$Message)
    Write-Host "    [INFO] $Message" -ForegroundColor DarkGray
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    [OK]   $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Host "    [WARN] $Message" -ForegroundColor Yellow
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-BuildStamp {
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        return "{0}.{1}" -f $cv.CurrentBuild, $cv.UBR
    } catch {
        return [System.Environment]::OSVersion.Version.ToString()
    }
}

function Get-InitialState {
    return [ordered]@{
        LastBuild           = ''
        InstalledCabPackage = ''
        InstalledCabPath    = ''
        RegionPolicyBackup  = ''
        XboxSettingsBackup  = ''
        UpdateCleanupTask   = $false
        LastRunUtc          = ''
    }
}

function Load-State {
    if (-not (Test-Path -LiteralPath $STATE_FILE)) {
        return (Get-InitialState)
    }

    try {
        $raw = Get-Content -LiteralPath $STATE_FILE -Encoding UTF8 -Raw | ConvertFrom-Json -ErrorAction Stop
        $state = Get-InitialState
        foreach ($prop in $raw.PSObject.Properties) {
            $state[$prop.Name] = $prop.Value
        }
        return $state
    } catch {
        Write-Warn "Unable to read ai_debloat_state.json, recreating it: $($_.Exception.Message)"
        return (Get-InitialState)
    }
}

function Save-State {
    param([Parameter(Mandatory)][hashtable]$State)

    Ensure-Directory -Path $BACKUP_DIR
    $State['LastRunUtc'] = (Get-Date).ToUniversalTime().ToString('o')
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $STATE_FILE -Encoding UTF8
}

function Get-IsArm64 {
    try {
        return ((Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).SystemType -match 'ARM64') -or
            ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
    } catch {
        return $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'
    }
}

function Get-CabPath {
    $archFolder = if (Get-IsArm64) { 'arm64' } else { 'amd64' }
    $folder = Join-Path $PACKAGE_ROOT $archFolder
    if (-not (Test-Path -LiteralPath $folder)) {
        throw "AI package asset folder not found: $folder"
    }

    $cab = Get-ChildItem -LiteralPath $folder -Filter '*.cab' -File -ErrorAction Stop | Select-Object -First 1
    if (-not $cab) {
        throw "No CAB asset found under: $folder"
    }

    return $cab.FullName
}

function Backup-FileOnce {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$BackupPath,
        [Parameter(Mandatory)][string]$StateKey,
        [Parameter(Mandatory)][hashtable]$State
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($State[$StateKey]) -and (Test-Path -LiteralPath $State[$StateKey])) {
        return
    }

    Ensure-Directory -Path (Split-Path -Parent $BackupPath)
    Copy-Item -LiteralPath $SourcePath -Destination $BackupPath -Force
    $State[$StateKey] = $BackupPath
    Write-Ok "Backed up $(Split-Path -Leaf $SourcePath)"
}

function Invoke-AsSystemScript {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ScriptBody,
        [int]$TimeoutSeconds = 300
    )

    $tempRoot   = Join-Path $env:TEMP 'win_desloperf_ai'
    $scriptPath = Join-Path $tempRoot "$Name.ps1"
    $outputPath = Join-Path $tempRoot "$Name.log"
    $taskName   = "win_desloperf-$Name-temp"

    Ensure-Directory -Path $tempRoot
    Set-Content -LiteralPath $scriptPath -Encoding UTF8 -Value $ScriptBody
    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
    }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" *> `"$outputPath`""
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest -LogonType ServiceAccount
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

    try {
        Register-ScheduledTask -TaskName $taskName -TaskPath $TASK_PATH -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskPath $TASK_PATH -TaskName $taskName

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        do {
            Start-Sleep -Seconds 2
            $info = Get-ScheduledTaskInfo -TaskPath $TASK_PATH -TaskName $taskName -ErrorAction SilentlyContinue
        } while ($info -and $info.LastRunTime -eq [datetime]::MinValue -and (Get-Date) -lt $deadline)

        do {
            Start-Sleep -Seconds 2
            $task = Get-ScheduledTask -TaskPath $TASK_PATH -TaskName $taskName -ErrorAction SilentlyContinue
        } while ($task.State -eq 'Running' -and (Get-Date) -lt $deadline)

        $info = Get-ScheduledTaskInfo -TaskPath $TASK_PATH -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $info) {
            throw 'Temporary SYSTEM task did not report status.'
        }

        if ($info.LastTaskResult -ne 0) {
            $output = if (Test-Path -LiteralPath $outputPath) { Get-Content -LiteralPath $outputPath -Raw -ErrorAction SilentlyContinue } else { '' }
            throw "SYSTEM task failed with exit code $($info.LastTaskResult). $output"
        }

        if (Test-Path -LiteralPath $outputPath) {
            foreach ($line in (Get-Content -LiteralPath $outputPath -ErrorAction SilentlyContinue)) {
                if ($line.Trim().Length -gt 0) {
                    Write-Info $line
                }
            }
        }
    } finally {
        Unregister-ScheduledTask -TaskPath $TASK_PATH -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
    }
}

function Remove-MatchedItem {
    param([Parameter(Mandatory)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return $false
    }

    try {
        Remove-Item -LiteralPath $LiteralPath -Recurse -Force -ErrorAction Stop
        return (-not (Test-Path -LiteralPath $LiteralPath))
    } catch {
        return $false
    }
}

function Get-AiPackagePatterns {
    return @(
        'MicrosoftWindows.Client.AIX',
        'MicrosoftWindows.Client.CoPilot',
        'Microsoft.Windows.Ai.Copilot.Provider',
        'MicrosoftWindows.Client.CoreAI',
        'Microsoft.Office.ActionsServer',
        'aimgr',
        'Microsoft.Edge.GameAssist',
        'Microsoft.WritingAssistant',
        'MicrosoftWindows.*.InpApp',
        'MicrosoftWindows.*.Filons',
        'MicrosoftWindows.*.Voiess',
        'WindowsWorkload.*'
    )
}

function Test-AiPackageName {
    param([Parameter(Mandatory)][string]$Name)

    foreach ($pattern in (Get-AiPackagePatterns)) {
        if ($Name -like $pattern) {
            return $true
        }
    }

    return $false
}

function Stop-AiProcesses {
    $names = @('ai', 'aihost', 'aicontext', 'aixhost', 'aimgr', 'Copilot', 'ClickToDo', 'M365Copilot', 'GameBar', 'GameBarFTServer')
    foreach ($name in $names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Patch-IntegratedServicesRegionPolicy {
    param([Parameter(Mandatory)][hashtable]$State)

    if (-not (Test-Path -LiteralPath $REGION_POLICY_PATH)) {
        Write-Info 'IntegratedServicesRegionPolicySet.json not found on this build'
        return
    }

    $backupPath = Join-Path $BACKUP_DIR 'ai_IntegratedServicesRegionPolicySet.json'
    Backup-FileOnce -SourcePath $REGION_POLICY_PATH -BackupPath $backupPath -StateKey 'RegionPolicyBackup' -State $State

    try {
        $json = Get-Content -LiteralPath $REGION_POLICY_PATH -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $patterns = @(
            '(?i)copilot',
            '(?i)recall',
            '(?i)search',
            '(?i)bing',
            '(?i)office mru',
            '(?i)vega search',
            '(?i)taskbar'
        )

        $changed = 0
        foreach ($policy in @($json.policies)) {
            $comment = [string]$policy.'$comment'
            if ([string]::IsNullOrWhiteSpace($comment)) {
                continue
            }

            if ($patterns | Where-Object { $comment -match $_ }) {
                if ($policy.defaultState -ne 'disabled') {
                    $policy.defaultState = 'disabled'
                    $changed++
                }
            }
        }

        if ($changed -gt 0) {
            $json | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $REGION_POLICY_PATH -Encoding UTF8
            Write-Ok "Integrated services region policy patched ($changed policy entries)"
        } else {
            Write-Info 'Integrated services region policy already aligned'
        }
    } catch {
        Write-Warn "Direct region policy patch failed, retrying as SYSTEM: $($_.Exception.Message)"
        $escapedJson = $REGION_POLICY_PATH.Replace("'", "''")
        $escapedBackup = $backupPath.Replace("'", "''")
        $systemScript = @"
`$jsonPath = '$escapedJson'
`$backupPath = '$escapedBackup'
if (-not (Test-Path -LiteralPath `$backupPath)) {
    Copy-Item -LiteralPath `$jsonPath -Destination `$backupPath -Force
}
`$data = Get-Content -LiteralPath `$jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
`$patterns = @('copilot', 'recall', 'search', 'bing', 'office mru', 'vega search', 'taskbar')
`$changed = 0
foreach (`$policy in @(`$data.policies)) {
    `$comment = [string]`$policy.'`$comment'
    foreach (`$pattern in `$patterns) {
        if (`$comment -match `$pattern) {
            if (`$policy.defaultState -ne 'disabled') {
                `$policy.defaultState = 'disabled'
                `$changed++
            }
            break
        }
    }
}
`$data | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath `$jsonPath -Encoding UTF8
Write-Output "Patched policies: `$changed"
"@
        Invoke-AsSystemScript -Name 'region-policy-patch' -ScriptBody $systemScript
        Write-Ok 'Integrated services region policy patched via SYSTEM task'
    }
}

function Install-AntiReinstallPackage {
    param([Parameter(Mandatory)][hashtable]$State)

    $existing = Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -like '*ZoicwareRemoveWindowsAI*' }
    if ($existing) {
        $State['InstalledCabPackage'] = $existing[0].PackageName
        Write-Info 'Custom anti-reinstall package already installed'
        return
    }

    $cabPath = Get-CabPath
    try {
        Add-WindowsPackage -Online -PackagePath $cabPath -NoRestart -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 2
        $installed = Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -like '*ZoicwareRemoveWindowsAI*' } | Select-Object -First 1
        if ($installed) {
            $State['InstalledCabPackage'] = $installed.PackageName
            $State['InstalledCabPath'] = $cabPath
            Write-Ok 'Custom anti-reinstall package installed'
        } else {
            Write-Warn 'Custom anti-reinstall package install did not report a package identity'
        }
    } catch {
        Write-Warn "Failed to install anti-reinstall CAB: $($_.Exception.Message)"
    }
}

function Prepare-AiAppxForRemoval {
    param([Parameter(Mandatory)][string]$PackageFamilyName)

    $familyEscaped = $PackageFamilyName.Replace("'", "''")
    $systemScript = @"
`$family = '$familyEscaped'
`$deprovPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned'
if (-not (Test-Path -LiteralPath `$deprovPath)) {
    New-Item -Path `$deprovPath -Force | Out-Null
}
New-Item -Path (Join-Path `$deprovPath `$family) -Force | Out-Null
`$inboxPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\InboxApplications'
if (Test-Path -LiteralPath `$inboxPath) {
    Remove-Item -LiteralPath (Join-Path `$inboxPath `$family) -Recurse -Force -ErrorAction SilentlyContinue
}
try {
    & dism.exe /Online /Set-NonRemovableAppsPolicy /PackageFamily:`$family /NonRemovable:0 | Out-Null
} catch {
}
Write-Output "Prepared `$family for deprovision/removal"
"@
    try {
        Invoke-AsSystemScript -Name ("prep-appx-" + ([guid]::NewGuid().ToString('N'))) -ScriptBody $systemScript -TimeoutSeconds 180
    } catch {
        Write-Warn "Unable to prepare $PackageFamilyName for advanced AppX removal: $($_.Exception.Message)"
    }
}

function Remove-AdvancedAiAppxPackages {
    Write-Info 'Stopping AI-related processes'
    Stop-AiProcesses

    $installed = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { Test-AiPackageName -Name $_.Name })
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { Test-AiPackageName -Name $_.DisplayName })

    foreach ($pkg in $installed) {
        Prepare-AiAppxForRemoval -PackageFamilyName $pkg.PackageFamilyName
    }

    foreach ($pkg in $installed) {
        try {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            Write-Ok "Removed AppX package $($pkg.Name)"
        } catch {
            Write-Warn "Remove-AppxPackage failed for $($pkg.PackageFullName): $($_.Exception.Message)"
        }
    }

    foreach ($prov in $provisioned) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
            Write-Ok "Deprovisioned $($prov.DisplayName)"
        } catch {
            Write-Warn "Remove-AppxProvisionedPackage failed for $($prov.PackageName): $($_.Exception.Message)"
        }
    }

    if ($installed.Count -eq 0 -and $provisioned.Count -eq 0) {
        Write-Info 'No additional AI AppX packages found'
    }
}

function Remove-RecallOptionalFeature {
    $features = @(Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | Where-Object {
        $_.FeatureName -match 'Recall'
    })

    if ($features.Count -eq 0) {
        Write-Info 'No Recall optional feature found'
        return
    }

    foreach ($feature in $features) {
        if ($feature.State -eq 'DisabledWithPayloadRemoved') {
            Write-Info "$($feature.FeatureName) already disabled with payload removed"
            continue
        }

        try {
            Disable-WindowsOptionalFeature -Online -FeatureName $feature.FeatureName -Remove -NoRestart -ErrorAction Stop | Out-Null
            Write-Ok "Disabled optional feature $($feature.FeatureName) with payload removal"
        } catch {
            Write-Warn "Failed to disable optional feature $($feature.FeatureName): $($_.Exception.Message)"
        }
    }
}

function Remove-AiCbsPackages {
    $cbsRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
    if (-not (Test-Path -LiteralPath $cbsRoot)) {
        Write-Info 'CBS package registry root not found'
        return
    }

    $targets = @(Get-ChildItem -LiteralPath $cbsRoot -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -match '(?i)AIX|Recall|Copilot|CoreAI'
    })

    if ($targets.Count -eq 0) {
        Write-Info 'No AI CBS packages found'
        return
    }

    $systemRetry = [System.Collections.Generic.List[string]]::new()
    foreach ($target in $targets) {
        try {
            Remove-WindowsPackage -Online -PackageName $target.PSChildName -NoRestart -ErrorAction Stop | Out-Null
            Write-Ok "Removed CBS package $($target.PSChildName)"
        } catch {
            Write-Warn "Failed to remove CBS package $($target.PSChildName): $($_.Exception.Message)"
            if ($_.Exception.Message -match '(?i)access is denied') {
                [void]$systemRetry.Add($target.PSChildName)
            }
        }
    }

    if ($systemRetry.Count -eq 0) {
        return
    }

    $quotedPackages = ($systemRetry | Select-Object -Unique | ForEach-Object { "'" + ($_.Replace("'", "''")) + "'" }) -join ', '
    $systemScript = @"
`$packages = @($quotedPackages)
foreach (`$package in `$packages) {
    try {
        Remove-WindowsPackage -Online -PackageName `$package -NoRestart -ErrorAction Stop | Out-Null
        Write-Output ("Removed CBS package as SYSTEM: {0}" -f `$package)
        continue
    } catch {
    }
    try {
        & dism.exe /Online /Remove-Package /PackageName:`$package /NoRestart | Out-Null
        Write-Output ("Requested CBS removal via DISM as SYSTEM: {0}" -f `$package)
    } catch {
        Write-Output ("CBS removal warning for {0}: {1}" -f `$package, `$_.Exception.Message)
    }
}
"@

    try {
        Invoke-AsSystemScript -Name 'remove-ai-cbs' -ScriptBody $systemScript -TimeoutSeconds 600
        Write-Ok 'Retried AI CBS package removal as SYSTEM'
    } catch {
        Write-Warn "SYSTEM retry for AI CBS packages failed: $($_.Exception.Message)"
    }
}

function Remove-AiFiles {
    $patterns = @(
        "$env:ProgramFiles\WindowsApps\MicrosoftWindows.Client.AIX*",
        "$env:ProgramFiles\WindowsApps\MicrosoftWindows.Client.CoPilot*",
        "$env:ProgramFiles\WindowsApps\Microsoft.Windows.Ai.Copilot.Provider*",
        "$env:ProgramFiles\WindowsApps\MicrosoftWindows.Client.CoreAI*",
        "$env:ProgramFiles\WindowsApps\Microsoft.Office.ActionsServer*",
        "$env:ProgramFiles\WindowsApps\aimgr*",
        "$env:ProgramFiles\WindowsApps\Microsoft.WritingAssistant*",
        "$env:ProgramFiles\WindowsApps\MicrosoftWindows.*.InpApp*",
        "$env:ProgramFiles\WindowsApps\MicrosoftWindows.*.Filons*",
        "$env:ProgramFiles\WindowsApps\MicrosoftWindows.*.Voiess*",
        "$env:ProgramFiles\WindowsApps\WindowsWorkload.*"
    )

    $removed = 0
    $systemRetry = [System.Collections.Generic.List[string]]::new()
    foreach ($pattern in $patterns) {
        foreach ($item in @(Get-ChildItem -Path $pattern -Force -ErrorAction SilentlyContinue)) {
            try {
                if (Remove-MatchedItem -LiteralPath $item.FullName) {
                    $removed++
                    Write-Ok "Removed AI file path $($item.FullName)"
                } else {
                    [void]$systemRetry.Add($item.FullName)
                    Write-Warn "Direct removal failed for $($item.FullName), queued SYSTEM retry"
                }
            } catch {
                [void]$systemRetry.Add($item.FullName)
                Write-Warn "Failed to remove $($item.FullName): $($_.Exception.Message)"
            }
        }
    }

    if ($systemRetry.Count -gt 0) {
        $targets = @($systemRetry | Select-Object -Unique)
        $quotedTargets = ($targets | ForEach-Object { "'" + ($_.Replace("'", "''")) + "'" }) -join ', '
        $systemScript = @"
`$targets = @($quotedTargets)
foreach (`$target in `$targets) {
    try {
        if (Test-Path -LiteralPath `$target) {
            Remove-Item -LiteralPath `$target -Recurse -Force -ErrorAction Stop
        }
        Write-Output ("SYSTEM file cleanup attempted: {0}" -f `$target)
    } catch {
        Write-Output ("SYSTEM file cleanup warning for {0}: {1}" -f `$target, `$_.Exception.Message)
    }
}
"@
        try {
            Invoke-AsSystemScript -Name 'remove-ai-files' -ScriptBody $systemScript -TimeoutSeconds 600
            foreach ($target in $targets) {
                if (-not (Test-Path -LiteralPath $target)) {
                    $removed++
                    Write-Ok "Removed AI file path via SYSTEM $target"
                } else {
                    Write-Warn "Residual AI file path still present: $target"
                }
            }
        } catch {
            Write-Warn "SYSTEM retry for AI file cleanup failed: $($_.Exception.Message)"
        }
    }

    if ($removed -eq 0) {
        Write-Info 'No residual AI file paths matched the cleanup list'
    }
}

function Remove-RecallTasks {
    $systemScript = @"
`$patterns = 'Recall', 'ClickToDo', 'Copilot'
try {
    Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        `$full = ("{0}{1}" -f `$_.TaskPath, `$_.TaskName)
        foreach (`$pattern in `$patterns) {
            if (`$full -match `$pattern) { return `$true }
        }
        return `$false
    } | ForEach-Object {
        Unregister-ScheduledTask -TaskPath `$_.TaskPath -TaskName `$_.TaskName -Confirm:`$false -ErrorAction SilentlyContinue | Out-Null
        Write-Output ("Removed task: {0}{1}" -f `$_.TaskPath, `$_.TaskName)
    }
} catch {
    Write-Output ("Task unregister warning: {0}" -f `$_.Exception.Message)
}

`$taskRoot = Join-Path `$env:windir 'System32\Tasks'
foreach (`$pattern in `$patterns) {
    Get-ChildItem -LiteralPath `$taskRoot -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {
        `$_.FullName -match `$pattern
    } | ForEach-Object {
        Remove-Item -LiteralPath `$_.FullName -Force -ErrorAction SilentlyContinue
        Write-Output ("Removed task file: {0}" -f `$_.FullName)
    }
}
"@
    try {
        Invoke-AsSystemScript -Name 'remove-recall-tasks' -ScriptBody $systemScript -TimeoutSeconds 180
        Write-Ok 'Aggressive Recall/Copilot task cleanup completed'
    } catch {
        Write-Warn "Recall/Copilot task cleanup failed: $($_.Exception.Message)"
    }
}

function Disable-GamingCopilot {
    $settingsPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.XboxGamingOverlay_8wekyb3d8bbwe\LocalState\profileDataSettings.txt'
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        Write-Info 'Xbox Game Bar settings not found, Gaming Copilot patch skipped'
        return
    }

    $state = $script:StateRef
    $backupPath = Join-Path $BACKUP_DIR 'ai_gamebar_profileDataSettings.txt'
    Backup-FileOnce -SourcePath $settingsPath -BackupPath $backupPath -StateKey 'XboxSettingsBackup' -State $state

    try {
        Get-Process -Name '*gamebar*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $json = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $containers = @($json.profile.settingsStorage.PSObject.Properties | Where-Object { $_.Name -like '*GamingCompanionWidget*' })
        foreach ($container in $containers) {
            foreach ($prop in @($container.Value.PSObject.Properties)) {
                if ($prop.Name -ne 'suppressFirstFavorite' -and $prop.Value -is [bool]) {
                    $container.Value.$($prop.Name) = $false
                }
            }
            Add-Member -InputObject $container.Value -NotePropertyName 'homeMenuVisibleUser' -NotePropertyValue $false -Force
        }
        if ($containers.Count -gt 0) {
            $json | ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $settingsPath -Encoding UTF8
            Write-Ok 'Gaming Copilot disabled in Xbox Game Bar settings'
        } else {
            Write-Info 'No Gaming Copilot widget payload found in Xbox Game Bar settings'
        }
    } catch {
        Write-Warn "Unable to patch Xbox Game Bar Gaming Copilot settings: $($_.Exception.Message)"
    }
}

function Register-UpdateCleanupTask {
    param([Parameter(Mandatory)][hashtable]$State)

    $scriptPath = $MyInvocation.MyCommand.Path
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -PostUpdateRepair"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest -LogonType ServiceAccount
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden

    try {
        Register-ScheduledTask -TaskPath $TASK_PATH -TaskName $TASK_NAME -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        $State['UpdateCleanupTask'] = $true
        Write-Ok "Registered $TASK_FULL_NAME"
    } catch {
        Write-Warn "Unable to register ${TASK_FULL_NAME}: $($_.Exception.Message)"
    }
}

function Write-Summary {
    $remaining = @()
    $remaining += @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { Test-AiPackageName -Name $_.Name } | Select-Object -ExpandProperty Name -Unique)
    $remaining += @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { Test-AiPackageName -Name $_.DisplayName } | Select-Object -ExpandProperty DisplayName -Unique)
    $remaining = @($remaining | Sort-Object -Unique)

    if ($remaining.Count -eq 0) {
        Write-Ok 'No tracked advanced AI AppX packages remain'
        return
    }

    Write-Warn ("Remaining AI package targets: {0}" -f ($remaining -join ', '))
}

Ensure-Directory -Path $BACKUP_DIR
$state = Load-State
$script:StateRef = $state
$currentBuild = Get-BuildStamp

if ($PostUpdateRepair -and $state['LastBuild'] -eq $currentBuild) {
    Write-Info "Windows build unchanged ($currentBuild), AI post-update repair skipped"
    exit 0
}

Write-Host ''
if ($PostUpdateRepair) {
    Write-Host '>>> AI deep debloat post-update repair' -ForegroundColor Yellow
} else {
    Write-Host '>>> AI deep debloat' -ForegroundColor Yellow
}

Patch-IntegratedServicesRegionPolicy -State $state
Install-AntiReinstallPackage -State $state
Disable-GamingCopilot
Remove-AdvancedAiAppxPackages
Remove-RecallOptionalFeature
Remove-AiCbsPackages
Remove-AiFiles
Remove-RecallTasks
Register-UpdateCleanupTask -State $state
Write-Summary

$state['LastBuild'] = $currentBuild
Save-State -State $state
Write-Ok "AI deep debloat state saved for build $currentBuild"
