#Requires -Version 5.0

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$servicesPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\services.ps1'
$privacyPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\privacy.ps1'
$wuPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\set_windows_update.ps1'

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

$services = Get-Content -Path $servicesPath -Raw
$privacy = Get-Content -Path $privacyPath -Raw
$wu = Get-Content -Path $wuPath -Raw

Assert-NotContains $services "(?s)\`$disabled\s*=\s*@\([^)]*'DoSvc'" 'services.ps1 must not disable DoSvc; Windows Update downloads need it.'
Assert-NotContains $services "TriggerlessDisabled\s*=\s*@\('DoSvc'\)" 'services.ps1 must not treat DoSvc as a triggerless disabled service.'
Assert-NotContains $services "Set-ServiceStartupTypeExact\s+-Name\s+'DoSvc'\s+-StartupType\s+'Disabled'" 'services.ps1 must not force DoSvc Disabled.'
Assert-NotContains $services "Remove-Item\s+\`$triggerPath" 'services.ps1 must not delete DoSvc TriggerInfo.'

Assert-Contains $privacy "'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DeliveryOptimization'\s*=\s*@\{[^}]*'DODownloadMode'\s*=\s*0" 'privacy.ps1 must keep Delivery Optimization P2P disabled with DODownloadMode=0.'
Assert-Contains $privacy "'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System'\s*=\s*@\{[^}]*'AllowClipboardHistory'\s*=\s*0" 'privacy.ps1 must re-apply AllowClipboardHistory=0 after OOSU10 privacy sweep.'
Assert-Contains $wu "Ensure-DeliveryOptimizationHttpOnly" 'set_windows_update.ps1 must enforce HTTP-only Delivery Optimization for WU profiles.'
Assert-Contains $wu "Repair-DeliveryOptimizationService" 'set_windows_update.ps1 must repair stale DoSvc Disabled state from older pack runs.'
Assert-Contains $wu "Ensure-WindowsUpdateStableOnly" 'set_windows_update.ps1 must provide a stable-only Windows Update policy helper.'
Assert-Contains $wu "Set-ItemProperty\s+-Path\s+\`$path\s+-Name\s+'ManagePreviewBuilds'\s+-Type\s+DWord\s+-Value\s+0" 'Security profile must disable Windows Insider preview builds.'
Assert-Contains $wu "Set-ItemProperty\s+-Path\s+\`$path\s+-Name\s+'SetAllowOptionalContent'\s+-Type\s+DWord\s+-Value\s+0" 'Security profile must block automatic optional preview updates.'
Assert-Contains $wu "(?s)'2'\s*\{(?:(?!\r?\n\s*'3'\s*\{).)*Ensure-WindowsUpdateStableOnly" 'Security profile must apply stable-only Windows Update policy.'
Assert-NotContains $wu "(?s)'1'\s*\{(?:(?!\r?\n\s*'2'\s*\{).)*Ensure-WindowsUpdateStableOnly" 'Default profile must not apply Security-only preview blocking.'
Assert-Contains $wu "Ensure-WindowsUpdateDriverBlocking" 'set_windows_update.ps1 must provide a strict driver blocking helper.'
Assert-Contains $wu "Set-ItemProperty\s+-Path\s+\`$wuPath\s+-Name\s+'ExcludeWUDriversInQualityUpdate'\s+-Type\s+DWord\s+-Value\s+1" 'Security profile must exclude drivers from Windows Update quality updates.'
Assert-Contains $wu "Set-ItemProperty\s+-Path\s+\`$driverSearchPath\s+-Name\s+'SearchOrderConfig'\s+-Type\s+DWord\s+-Value\s+0" 'Security profile must disable Windows driver search order.'
Assert-Contains $wu "Hide-PendingWindowsUpdateDrivers" 'set_windows_update.ps1 must hide already offered optional driver updates in Security profile.'
Assert-Contains $wu "Restore-PackHiddenWindowsUpdateDrivers" 'set_windows_update.ps1 must restore pack-hidden optional drivers when Default profile is selected.'
Assert-Contains $wu "Read-PackHiddenDriverState" 'set_windows_update.ps1 must normalize pack-hidden driver state JSON before matching updates.'
Assert-NotContains $wu "\`$state\s*=\s*@\(Get-Content\s+-Path\s+\`$statePath\s+-Raw\s*\|\s*ConvertFrom-Json\)" 'set_windows_update.ps1 must not wrap ConvertFrom-Json directly; Windows PowerShell can create a nested Object[] state.'
Assert-Contains $wu "Refresh-WindowsUpdateUiState" 'set_windows_update.ps1 must refresh Windows Update UI state after changing hidden driver updates.'
Assert-Contains $wu "UsoClient\.exe" 'Windows Update UI refresh must use the inbox UsoClient refresh/scan entrypoint.'
Assert-Contains $wu "Reset-WindowsUpdateUxStore" 'set_windows_update.ps1 must reset the USO UX store when hidden optional drivers remain cached in Settings.'
Assert-Contains $wu "USOPrivate\\UpdateStore" 'Windows Update UX store reset must target the USOPrivate UpdateStore cache.'
Assert-Contains $wu "Move-Item\s+-Path\s+\`$path\s+-Destination\s+\`$destination" 'Windows Update UX store reset must move cache files to a backup instead of deleting them.'
Assert-Contains $wu "win_desloperf\\windows_update_ux_store_backup" 'Windows Update UX store backup must be kept under the pack appdata folder.'
Assert-Contains $wu "StartInteractiveScan" 'Windows Update UI refresh must use an interactive scan after cache reset.'
Assert-Contains $wu "(?s)'1'\s*\{(?:(?!\r?\n\s*'2'\s*\{).)*Restore-PackHiddenWindowsUpdateDrivers" 'Default profile must unhide driver updates hidden by the pack.'
Assert-Contains $wu "(?s)'2'\s*\{(?:(?!\r?\n\s*'3'\s*\{).)*Ensure-WindowsUpdateDriverBlocking(?:(?!\r?\n\s*'3'\s*\{).)*Hide-PendingWindowsUpdateDrivers(?:(?!\r?\n\s*'3'\s*\{).)*Reset-WindowsUpdateUxStore(?:(?!\r?\n\s*'3'\s*\{).)*Refresh-WindowsUpdateUiState" 'Security profile must enforce strict driver blocking, hide pending optional drivers, reset the cached WU UX store, and refresh WU UI state.'

Write-Host 'Windows Update Delivery Optimization contract OK'
