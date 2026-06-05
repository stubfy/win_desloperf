# restore\privacy.ps1 - Restore privacy registry defaults + AI/Copilot policies
# Combines: restore\ai_restore.ps1 + privacy_defaults.reg import
#
# Note: OOSU10, telemetry tasks, and wscsvc are NOT auto-restored here.
#   - OOSU10: use the system restore point created by backup.ps1
#   - Telemetry tasks: re-enable manually via Task Scheduler
#     (Microsoft\Windows\Customer Experience Improvement Program, etc.)
#   - wscsvc: restored automatically via restore\services.ps1 (JSON backup)

$AUTOMATED_ROOT = Split-Path (Split-Path $PSScriptRoot)
$BACKUP_DIR = Join-Path $AUTOMATED_ROOT "backup"
$WINDOWS_HELLO_STATE_FILE = Join-Path $BACKUP_DIR "windows_hello_state.json"
$WINDOWS_HELLO_PROVIDER_EXCLUSIONS = [ordered]@{
    "{F8A1793B-7873-4046-B2A7-1F318747F427}" = "FIDO Credential Provider"
    "{D6886603-9D2F-4EB2-B667-1971041FA96B}" = "NGC Credential Provider"
    "{cb82ea12-9f71-446d-89e1-8d0924e1256e}" = "PINLogonProvider"
    "{8AF662BF-65A0-4D0A-A540-A338A999D36F}" = "FaceCredentialProvider"
    "{BEC09223-B018-416D-A0AC-523971B639F5}" = "WinBio Credential Provider"
    "{2135f72a-90b5-4ed3-a7f1-8bb705ac276a}" = "PicturePasswordLogonProvider"
    "{27FBDB57-B613-4AF2-9D7E-4FA7A66C21AD}" = "TrustedSignal Credential Provider"
    "{48B4E58D-2791-456C-9091-D524C6C706F2}" = "Secondary Authentication Factor Credential Provider"
}

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
    'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\ai'
    'HKCU:\Software\Policies\Microsoft\office\16.0\common\privacy'
    'HKCU:\Software\Microsoft\VoiceAccess'
    # Additional Copilot keys
    'HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat'
    # Paint and Notepad AI settings
    'HKCU:\Software\Microsoft\MSPaint\Settings'
    'HKCU:\Software\Microsoft\Notepad\Settings'
    'HKLM:\SOFTWARE\Policies\WindowsNotepad'
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
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';           Name = 'AllowDomainPINLogon' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';           Name = 'BlockDomainPicturePassword' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI';         Name = 'DisableSettingsAgent' }
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'; Name = 'AutoOpenCopilotLargeScreens' }
    @{ Path = 'HKCU:\Software\Microsoft\Office\16.0\Word\Options'; Name = 'EnableCopilot' }
    @{ Path = 'HKCU:\Software\Microsoft\Office\16.0\Excel\Options'; Name = 'EnableCopilot' }
    @{ Path = 'HKCU:\Software\Microsoft\Office\16.0\OneNote\Options\Copilot'; Name = 'CopilotEnabled' }
    @{ Path = 'HKCU:\Software\Microsoft\Office\16.0\OneNote\Options\Copilot'; Name = 'CopilotNotebooksEnabled' }
    @{ Path = 'HKCU:\Software\Microsoft\Office\16.0\OneNote\Options\Copilot'; Name = 'CopilotSkittleEnabled' }
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
    # Windows Hello / passkeys
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'; Name = 'Enabled' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'; Name = 'DisablePostLogonProvisioning' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'; Name = 'EnablePinRecovery' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'; Name = 'UseCertificateForOnPremAuth' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'; Name = 'UseCloudTrustForOnPremAuth' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'; Name = 'DisableSmartCardNode' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork'; Name = 'UseHelloCertificatesAsSmartCardCertificates' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Biometrics'; Name = 'Enabled' }
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WinBio\Credential Provider'; Name = 'Domain Accounts' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\FIDO'; Name = 'EnableFIDODeviceLogon' }
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Policies\PassportForWork\SecurityKey'; Name = 'UseSecurityKeyForSignin' }
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\SecondaryAuthenticationFactor'; Name = 'AllowSecondaryAuthenticationDevice' }
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Authentication\EnableWebSignIn'; Name = 'value' }
)
foreach ($v in $values) {
    if (Test-Path $v.Path) {
        Remove-ItemProperty -Path $v.Path -Name $v.Name -ErrorAction SilentlyContinue
        Write-Host "    [REMOVED]   $($v.Name)  ($($v.Path))"
    }
}

# === SECTION: Windows Hello / passkeys restore ===

function ConvertTo-Hashtable {
    param($Object)

    if ($null -eq $Object) { return $null }

    if ($Object -is [System.Collections.IDictionary]) {
        $hash = [ordered]@{}
        foreach ($key in $Object.Keys) {
            $hash[$key] = ConvertTo-Hashtable $Object[$key]
        }
        return $hash
    }

    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string])) {
        $items = @()
        foreach ($item in $Object) {
            $items += ConvertTo-Hashtable $item
        }
        return $items
    }

    if ($Object.PSObject.Properties.Count -gt 0 -and $Object -isnot [string]) {
        $hash = [ordered]@{}
        foreach ($prop in $Object.PSObject.Properties) {
            $hash[$prop.Name] = ConvertTo-Hashtable $prop.Value
        }
        return $hash
    }

    return $Object
}

function Read-WindowsHelloState {
    if (-not (Test-Path $WINDOWS_HELLO_STATE_FILE)) {
        return [ordered]@{}
    }

    try {
        $raw = Get-Content -LiteralPath $WINDOWS_HELLO_STATE_FILE -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return [ordered]@{} }
        return ConvertTo-Hashtable ($raw | ConvertFrom-Json)
    } catch {
        Write-Host "    [WARN] Could not read Windows Hello backup metadata: $($_.Exception.Message)" -ForegroundColor Yellow
        return [ordered]@{}
    }
}

function Split-CredentialProviderList {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @($Value -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Restore-WindowsHelloCredentialProviderExclusions {
    $policyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $valueName = 'ExcludedCredentialProviders'
    if (-not (Test-Path $policyPath)) { return }

    $state = Read-WindowsHelloState
    if ($state.Contains('ExcludedCredentialProviders')) {
        $providerState = $state['ExcludedCredentialProviders']
        if ($providerState['OriginalValueExists']) {
            $originalValue = [string]$providerState['OriginalValue']
            $props = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
            if ($props -and ($props.PSObject.Properties.Name -contains $valueName)) {
                Set-ItemProperty -Path $policyPath -Name $valueName -Value $originalValue -ErrorAction SilentlyContinue
            } else {
                New-ItemProperty -Path $policyPath -Name $valueName -Value $originalValue -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            }
            Write-Host "    [RESTORED]  ExcludedCredentialProviders"
        } else {
            Remove-ItemProperty -Path $policyPath -Name $valueName -ErrorAction SilentlyContinue
            Write-Host "    [REMOVED]   ExcludedCredentialProviders"
        }
        return
    }

    $currentValue = try { [string](Get-ItemProperty -Path $policyPath -Name $valueName -ErrorAction Stop).$valueName } catch { $null }
    if ([string]::IsNullOrWhiteSpace($currentValue)) { return }

    $packGuids = @($WINDOWS_HELLO_PROVIDER_EXCLUSIONS.Keys | ForEach-Object { $_.ToLowerInvariant() })
    $filtered = @(Split-CredentialProviderList $currentValue | Where-Object {
        $_.ToLowerInvariant() -notin $packGuids
    })

    if ($filtered.Count -gt 0) {
        Set-ItemProperty -Path $policyPath -Name $valueName -Value ($filtered -join ';') -ErrorAction SilentlyContinue
        Write-Host "    [RESTORED]  ExcludedCredentialProviders (pack entries removed)"
    } else {
        Remove-ItemProperty -Path $policyPath -Name $valueName -ErrorAction SilentlyContinue
        Write-Host "    [REMOVED]   ExcludedCredentialProviders"
    }
}

function Restore-WindowsHelloNgcStore {
    $state = Read-WindowsHelloState
    if (-not $state.Contains('Ngc')) { return }

    $ngc = $state['Ngc']
    if (-not ($ngc.Contains('Quarantined') -and $ngc['Quarantined'])) { return }

    $quarantinePath = [string]$ngc['QuarantinePath']
    $originalPath = if ($ngc.Contains('OriginalPath')) {
        [string]$ngc['OriginalPath']
    } else {
        Join-Path $env:SystemRoot 'ServiceProfiles\LocalService\AppData\Local\Microsoft\Ngc'
    }

    if (-not (Test-Path -LiteralPath $quarantinePath)) {
        Write-Host "    [WARN] Windows Hello NGC quarantine not found: $quarantinePath" -ForegroundColor Yellow
        return
    }

    if (Test-Path -LiteralPath $originalPath -ErrorAction SilentlyContinue) {
        Write-Host "    [WARN] Windows Hello NGC restore skipped; destination already exists: $originalPath" -ForegroundColor Yellow
        return
    }

    try {
        $parent = Split-Path $originalPath -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Move-Item -LiteralPath $quarantinePath -Destination $originalPath -Force -ErrorAction Stop
        Write-Host "    [RESTORED]  Windows Hello NGC store"
    } catch {
        Write-Host "    [WARN] Could not restore Windows Hello NGC store: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Restore-WindowsHelloCredentialProviderExclusions
Restore-WindowsHelloNgcStore

# Remove the Copilot shell extension block
$blockedPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
$clsid = "{CB5571B1-A131-4C41-BFEF-57696FCE7CA2}"
if ((Test-Path $blockedPath) -and (Get-ItemProperty -Path $blockedPath -Name $clsid -ErrorAction SilentlyContinue)) {
    Remove-ItemProperty -Path $blockedPath -Name $clsid -ErrorAction SilentlyContinue
    Write-Host "    [REMOVED]   Copilot shell extension unblocked"
}

# Remove AI components hide tokens if this pack added them
$visibilityPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$currentVisibility = try { Get-ItemPropertyValue -Path $visibilityPath -Name 'SettingsPageVisibility' -ErrorAction Stop } catch { $null }
if (-not [string]::IsNullOrWhiteSpace($currentVisibility) -and $currentVisibility -like 'hide:*') {
    $tokens = @($currentVisibility.Substring(5) -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $filtered = @($tokens | Where-Object { $_ -notin @('aicomponents', 'appactions') })
    if ($filtered.Count -gt 0) {
        $newVisibility = 'hide:' + ($filtered -join ';') + ';'
        Set-ItemProperty -Path $visibilityPath -Name 'SettingsPageVisibility' -Value $newVisibility -Type String -ErrorAction SilentlyContinue
        Write-Host "    [RESTORED]  SettingsPageVisibility -> $newVisibility"
    } else {
        Remove-ItemProperty -Path $visibilityPath -Name 'SettingsPageVisibility' -ErrorAction SilentlyContinue
        Write-Host '    [REMOVED]   SettingsPageVisibility (AI Components hide)'
    }
}
