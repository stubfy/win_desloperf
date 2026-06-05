#Requires -Version 5.0

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$privacyPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\privacy.ps1'
$privacyTweaksPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\privacy_tweaks.reg'
$privacyDefaultsPath = Join-Path $repoRoot '1 - Automated\restore\ps1\privacy_defaults.reg'
$restorePrivacyPath = Join-Path $repoRoot '1 - Automated\restore\ps1\privacy.ps1'
$servicesPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\services.ps1'
$snapshotPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\snapshot.ps1'

function Assert-Contains {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Message
    )

    if ($Content -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContains {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Message
    )

    if ($Content -match $Pattern) {
        throw $Message
    }
}

$privacy = Get-Content -Path $privacyPath -Raw
$privacyTweaks = Get-Content -Path $privacyTweaksPath -Raw
$privacyDefaults = Get-Content -Path $privacyDefaultsPath -Raw
$restorePrivacy = Get-Content -Path $restorePrivacyPath -Raw
$services = Get-Content -Path $servicesPath -Raw
$snapshot = Get-Content -Path $snapshotPath -Raw

$disabledStart = $services.IndexOf('$disabled = @(')
$manualStart = $services.IndexOf('$manual = @(')
$automaticStart = $services.IndexOf('$automatic = @(')
if ($disabledStart -lt 0 -or $manualStart -lt 0 -or $automaticStart -lt 0) {
    throw 'services.ps1 catalog blocks could not be located.'
}
$disabledBlock = $services.Substring($disabledStart, $manualStart - $disabledStart)
$manualBlock = $services.Substring($manualStart, $automaticStart - $manualStart)

Assert-Contains $privacy 'Windows Hello / passkeys' 'privacy.ps1 must have an explicit Windows Hello / passkeys section.'
Assert-Contains $privacy "'HKLM:\\SOFTWARE\\Policies\\Microsoft\\PassportForWork'\s*=\s*@\{[^}]*'Enabled'\s*=\s*0[^}]*'DisablePostLogonProvisioning'\s*=\s*1" 'privacy.ps1 must disable Windows Hello for Business provisioning.'
Assert-Contains $privacy "'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Biometrics'\s*=\s*@\{[^}]*'Enabled'\s*=\s*0" 'privacy.ps1 must disable biometrics policy.'
Assert-Contains $privacy "'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WinBio\\Credential Provider'\s*=\s*@\{[^}]*'Domain Accounts'\s*=\s*0" 'privacy.ps1 must disable WinBio credential provider for domain accounts.'
Assert-Contains $privacy "'HKLM:\\SOFTWARE\\Policies\\Microsoft\\FIDO'\s*=\s*@\{[^}]*'EnableFIDODeviceLogon'\s*=\s*0" 'privacy.ps1 must disable FIDO device logon policy.'
Assert-Contains $privacy "'HKLM:\\SOFTWARE\\Microsoft\\Policies\\PassportForWork\\SecurityKey'\s*=\s*@\{[^}]*'UseSecurityKeyForSignin'\s*=\s*0" 'privacy.ps1 must disable PassportForWork security key sign-in.'
Assert-Contains $privacyTweaks '"LetAppsAccessPasskeys"=dword:00000002' 'privacy_tweaks.reg must force-deny app passkey creation/use.'
Assert-Contains $privacyTweaks '"LetAppsAccessPasskeysEnumeration"=dword:00000002' 'privacy_tweaks.reg must force-deny passkey autofill/enumeration.'
Assert-Contains $privacy "'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System'\s*=\s*@\{[^}]*'AllowDomainPINLogon'\s*=\s*0[^}]*'BlockDomainPicturePassword'\s*=\s*1" 'privacy.ps1 must block convenience PIN and picture password.'
Assert-Contains $privacy 'ExcludedCredentialProviders' 'privacy.ps1 must merge excluded credential providers.'
Assert-Contains $privacy 'windows_hello_state\.json' 'privacy.ps1 must write Windows Hello backup/quarantine metadata.'
Assert-Contains $privacy 'ServiceProfiles\\LocalService\\AppData\\Local\\Microsoft\\Ngc' 'privacy.ps1 must target the Windows Hello NGC credential store.'

$requiredProviderGuids = @(
    '\{F8A1793B-7873-4046-B2A7-1F318747F427\}', # FIDO Credential Provider
    '\{D6886603-9D2F-4EB2-B667-1971041FA96B\}', # NGC Credential Provider
    '\{cb82ea12-9f71-446d-89e1-8d0924e1256e\}', # PINLogonProvider
    '\{8AF662BF-65A0-4D0A-A540-A338A999D36F\}', # FaceCredentialProvider
    '\{BEC09223-B018-416D-A0AC-523971B639F5\}', # WinBio Credential Provider
    '\{2135f72a-90b5-4ed3-a7f1-8bb705ac276a\}', # PicturePasswordLogonProvider
    '\{27FBDB57-B613-4AF2-9D7E-4FA7A66C21AD\}', # TrustedSignal Credential Provider
    '\{48B4E58D-2791-456C-9091-D524C6C706F2\}'  # Secondary Authentication Factor Credential Provider
)
foreach ($guid in $requiredProviderGuids) {
    Assert-Contains $privacy $guid "privacy.ps1 must exclude credential provider $guid."
}
Assert-NotContains $privacy '\{60b78e88-ead8-445c-9cfd-0b87f74ea6cd\}' 'privacy.ps1 must not exclude the password credential provider.'

foreach ($svc in @('NgcSvc', 'NgcCtnrSvc', 'NaturalAuthentication', 'WbioSrvc')) {
    Assert-Contains $disabledBlock "'$svc'" "services.ps1 must disable $svc."
    Assert-NotContains $manualBlock "'$svc'" "services.ps1 must not keep $svc in Manual."
}
foreach ($svc in @('VaultSvc', 'KeyIso', 'TokenBroker', 'wlidsvc')) {
    Assert-NotContains $disabledBlock "'$svc'" "services.ps1 must not disable $svc."
}

Assert-Contains $restorePrivacy 'windows_hello_state\.json' 'restore privacy must read Windows Hello backup metadata.'
Assert-Contains $restorePrivacy 'ExcludedCredentialProviders' 'restore privacy must remove only pack-added credential provider exclusions.'
Assert-Contains $restorePrivacy 'UseSecurityKeyForSignin' 'restore privacy must remove security key sign-in policy.'
Assert-Contains $restorePrivacy 'EnableFIDODeviceLogon' 'restore privacy must remove FIDO device logon policy.'
Assert-Contains $privacyDefaults '"LetAppsAccessPasskeys"=-' 'privacy defaults must remove app passkey access policy.'
Assert-Contains $privacyDefaults '"LetAppsAccessPasskeysEnumeration"=-' 'privacy defaults must remove app passkey enumeration policy.'
Assert-Contains $restorePrivacy 'DisablePostLogonProvisioning' 'restore privacy must remove WHfB provisioning policy.'
Assert-Contains $restorePrivacy 'Restore-WindowsHelloNgcStore' 'restore privacy must restore quarantined NGC store when available.'

Assert-Contains $snapshot 'EnableFIDODeviceLogon' 'snapshot.ps1 must track FIDO device logon policy.'
Assert-Contains $snapshot 'UseSecurityKeyForSignin' 'snapshot.ps1 must track PassportForWork security key sign-in policy.'
Assert-Contains $snapshot 'DisablePostLogonProvisioning' 'snapshot.ps1 must track WHfB provisioning policy.'
Assert-Contains $snapshot 'ExcludedCredentialProviders' 'snapshot.ps1 must track credential provider exclusions.'

Write-Host 'Windows Hello / passkey disable contract OK'
