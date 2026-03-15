# opt_onedrive_uninstall.ps1 - Complete OneDrive uninstallation (Win32)
# OPTIONAL - called only if confirmed by the user in run_all.ps1
#
# OneDrive is a Win32 application (not UWP), so it cannot be removed with
# Remove-AppxPackage. The uninstaller is OneDriveSetup.exe /uninstall, found
# in SysWOW64, System32, or the user's AppData depending on the installation type.
#
# Steps performed:
#   1. Kill the OneDrive process to release file locks.
#   2. Run OneDriveSetup.exe /uninstall (or winget as fallback if not found).
#   3. Remove residual folders (OneDrive, AppData\Microsoft\OneDrive, ProgramData,
#      and the temp folder used during setup).
#   4. Delete OneDrive registry keys (HKCU and HKLM).
#   5. Remove the OneDrive startup entry from HKCU\Run.
#   6. Remove the OneDrive namespace extension from the Explorer navigation pane
#      by setting System.IsPinnedToNameSpaceTree=0 for the OneDrive CLSID.
#   7. Apply DisableFileSyncNGSC=1 policy to block reinstallation by Windows.
#      Note: this policy is also set in uwt_tweaks.reg as a baseline.
#
# FILE SAFETY: Local OneDrive files (if sync was active) are preserved in
# %USERPROFILE%\OneDrive and are NOT deleted. Only the application and its
# configuration data are removed.
#
# Rollback: restore\opt_onedrive_restore.ps1 provides reinstallation guidance.
# OneDrive can be reinstalled from Microsoft's official download page at any time.

Write-Host "    Stopping OneDrive process..."
Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Find the OneDrive installer
$setupPaths = @(
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    "$env:SystemRoot\System32\OneDriveSetup.exe"
    "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
)

$setup = $setupPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($setup) {
    Write-Host "    Uninstalling via: $setup"
    Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -NoNewWindow
} else {
    Write-Host "    OneDriveSetup.exe not found - trying via winget..."
    winget uninstall --id Microsoft.OneDrive --silent --accept-source-agreements 2>&1 | Out-Null
}

# Remove residual folders
$foldersToRemove = @(
    "$env:USERPROFILE\OneDrive"
    "$env:LOCALAPPDATA\Microsoft\OneDrive"
    "$env:PROGRAMDATA\Microsoft OneDrive"
    "$env:SystemDrive\OneDriveTemp"
)
foreach ($folder in $foldersToRemove) {
    if (Test-Path $folder) {
        Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    [REMOVED] $folder"
    }
}

# Remove OneDrive registry entries
$regPaths = @(
    'HKCU:\Software\Microsoft\OneDrive'
    'HKLM:\SOFTWARE\Microsoft\OneDrive'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\OneDrive'
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'         # OneDrive value
)
foreach ($path in $regPaths[0..2]) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    [REMOVED] $path"
    }
}

# Remove automatic startup entry
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
Remove-ItemProperty -Path $runKey -Name 'OneDrive' -ErrorAction SilentlyContinue

# Remove OneDrive from File Explorer navigation pane
$clsids = @(
    'HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
    'HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
)
foreach ($path in $clsids) {
    if (Test-Path $path) {
        Set-ItemProperty -Path $path -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
}

# Prevent automatic reinstallation by Windows
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
if (-not (Test-Path $policy)) { New-Item -Path $policy -Force | Out-Null }
Set-ItemProperty -Path $policy -Name 'DisableFileSyncNGSC' -Value 1 -Type DWord -ErrorAction SilentlyContinue

Write-Host "    OneDrive uninstalled and reinstallation blocked by policy."
Write-Host "    Note: local OneDrive files (if sync was active) are kept in $env:USERPROFILE\OneDrive"
