# opt_onedrive_uninstall.ps1 - Desinstallation complete de OneDrive (Win32)
# OPTIONNEL - appele uniquement si l'utilisateur l'a confirme dans run_all.ps1

Write-Host "    Arret du processus OneDrive..."
Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Chercher l'installateur OneDrive
$setupPaths = @(
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    "$env:SystemRoot\System32\OneDriveSetup.exe"
    "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
)

$setup = $setupPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($setup) {
    Write-Host "    Desinstallation via : $setup"
    Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -NoNewWindow
} else {
    Write-Host "    OneDriveSetup.exe introuvable - tentative via winget..."
    winget uninstall --id Microsoft.OneDrive --silent --accept-source-agreements 2>&1 | Out-Null
}

# Suppression des dossiers residuels
$foldersToRemove = @(
    "$env:USERPROFILE\OneDrive"
    "$env:LOCALAPPDATA\Microsoft\OneDrive"
    "$env:PROGRAMDATA\Microsoft OneDrive"
    "$env:SystemDrive\OneDriveTemp"
)
foreach ($folder in $foldersToRemove) {
    if (Test-Path $folder) {
        Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    [SUPPRIME] $folder"
    }
}

# Suppression des entrees registre OneDrive
$regPaths = @(
    'HKCU:\Software\Microsoft\OneDrive'
    'HKLM:\SOFTWARE\Microsoft\OneDrive'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\OneDrive'
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'         # valeur OneDrive
)
foreach ($path in $regPaths[0..2]) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    [SUPPRIME] $path"
    }
}

# Supprimer l'entree de demarrage automatique
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
Remove-ItemProperty -Path $runKey -Name 'OneDrive' -ErrorAction SilentlyContinue

# Supprimer OneDrive du panneau de navigation Explorateur
$clsids = @(
    'HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
    'HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
)
foreach ($path in $clsids) {
    if (Test-Path $path) {
        Set-ItemProperty -Path $path -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
}

# Empecher la reinstallation automatique par Windows
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
if (-not (Test-Path $policy)) { New-Item -Path $policy -Force | Out-Null }
Set-ItemProperty -Path $policy -Name 'DisableFileSyncNGSC' -Value 1 -Type DWord -ErrorAction SilentlyContinue

Write-Host "    OneDrive desinstalle et reinstallation bloquee par politique."
Write-Host "    Note: les fichiers OneDrive locaux (si sync active) sont conserves dans $env:USERPROFILE\OneDrive"
