# restore\privacy.ps1 - Restore privacy registry defaults + AI/Copilot policies
# Combines: restore\ai_restore.ps1 + privacy_defaults.reg import
#
# Note: OOSU10, telemetry tasks, and wscsvc are NOT auto-restored here.
#   - OOSU10: use the system restore point created by backup.ps1
#   - Telemetry tasks: re-enable manually via Task Scheduler
#     (Microsoft\Windows\Customer Experience Improvement Program, etc.)
#   - wscsvc: restored automatically via restore\services.ps1 (JSON backup)

# === SECTION: Privacy registry defaults ===

$PRIVACY_DEFAULTS = Join-Path $PSScriptRoot "privacy_defaults.reg"

if (Test-Path $PRIVACY_DEFAULTS) {
    $result = Start-Process regedit.exe -ArgumentList "/s `"$PRIVACY_DEFAULTS`"" -Wait -PassThru
    if ($result.ExitCode -eq 0) {
        Write-Host "    [OK] privacy_defaults.reg imported"
    } else {
        Write-Host "    [WARN] regedit exit code: $($result.ExitCode)"
    }
} else {
    Write-Host "    [WARN] privacy_defaults.reg not found: $PRIVACY_DEFAULTS" -ForegroundColor Yellow
}

# === SECTION: AI / Recall / Copilot restore ===
# Removes policy keys written by the AI disable section of privacy.ps1.

$paths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
    'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\ChatIcon'
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
    # Additional Copilot keys
    'HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat'
    # Paint and Notepad AI settings (user-level, safe to delete entire key)
    'HKCU:\Software\Microsoft\MSPaint\Settings'
    'HKCU:\Software\Microsoft\Notepad\Settings'
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    [REMOVED]   $path"
    } else {
        Write-Host "    [NOT FOUND] $path" -ForegroundColor Gray
    }
}

# Remove individual values (shared keys - do not delete the entire path)
$values = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot';             Name = 'IsCopilotAvailable'  }
    @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot'; Name = 'AllowCopilotRuntime' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';           Name = 'EnableCdp'           }
    # Click to Do user-level key (HKCU shared path - remove value only)
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ClickToDo'; Name = 'DisableClickToDo' }
    # Edge AI features (shared key - remove individual values only, not the entire key)
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'CopilotCDPPageContext'               }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'CopilotPageContext'                  }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'HubsSidebarEnabled'                  }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'EdgeEntraCopilotPageContext'          }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'EdgeHistoryAISearchEnabled'           }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'ComposeInlineEnabled'                }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'GenAILocalFoundationalModelSettings' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'NewTabPageBingChatEnabled'           }
)
foreach ($v in $values) {
    if (Test-Path $v.Path) {
        Remove-ItemProperty -Path $v.Path -Name $v.Name -ErrorAction SilentlyContinue
        Write-Host "    [REMOVED]   $($v.Name)  ($($v.Path))"
    }
}

# Remove the Copilot shell extension block
$blockedPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
$clsid = "{CB5571B1-A131-4C41-BFEF-57696FCE7CA2}"
if ((Test-Path $blockedPath) -and (Get-ItemProperty -Path $blockedPath -Name $clsid -ErrorAction SilentlyContinue)) {
    Remove-ItemProperty -Path $blockedPath -Name $clsid -ErrorAction SilentlyContinue
    Write-Host "    [REMOVED]   Copilot shell extension unblocked"
}
