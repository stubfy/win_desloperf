#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configuration du profil Windows Update

.DESCRIPTION
    Trois profils disponibles (inspires de WinUtil / Chris Titus Tech) :
      1 - Maximum    : tous les mises a jour (securite, qualite, pilotes, fonctionnalites)
      2 - Securite   : mises a jour securite/qualite uniquement (pas de maj fonctionnalites, pas de pilotes via WU)
      3 - Desactiver : desactive completement Windows Update (services + politiques)

.PARAMETER Profil
    1, 2 ou 3. Si absent, affiche un menu interactif.

.EXAMPLE
    .\15_windows_update.ps1 -Profil 2
    .\15_windows_update.ps1          # menu interactif
#>

param(
    [ValidateSet('1','2','3')]
    [string]$Profil
)

$ErrorActionPreference = 'Continue'

$WU_PATH    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$AU_PATH    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$DRV_META   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'
$DRV_SEARCH = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching'

# ── Menu interactif si -Profil non fourni ─────────────────────────────────────
if (-not $Profil) {
    Write-Host ""
    Write-Host "  PROFIL WINDOWS UPDATE" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Maximum    - Toutes les MAJ (securite, qualite, pilotes, fonctionnalites)" -ForegroundColor Green
    Write-Host "  [2] Securite   - MAJ securite/qualite uniquement (pas de fonctionnalites, pas de pilotes)" -ForegroundColor Yellow
    Write-Host "  [3] Desactiver - Desactive completement Windows Update" -ForegroundColor Red
    Write-Host ""
    do {
        $Profil = Read-Host "  Choix (1/2/3)"
    } while ($Profil -notin @('1','2','3'))
}

# ── Fonctions utilitaires ──────────────────────────────────────────────────────
function Set-RegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

function Remove-WUPolicies {
    # Supprime toutes les politiques WU restrictives
    Remove-Item -Path $WU_PATH    -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $DRV_META   -Recurse -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $DRV_SEARCH -Name 'SearchOrderConfig' -Force -ErrorAction SilentlyContinue
}

function Enable-WUServices {
    foreach ($svc in @('wuauserv','UsoSvc','BITS')) {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if ($s) {
            Set-Service  $svc -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service $svc -ErrorAction SilentlyContinue
            Write-Host "    [SERVICE] $svc -> Automatique"
        }
    }
}

function Disable-WUServices {
    foreach ($svc in @('wuauserv','UsoSvc')) {
        $s = Get-Service $svc -ErrorAction SilentlyContinue
        if ($s) {
            Stop-Service  $svc -Force -ErrorAction SilentlyContinue
            Set-Service   $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "    [SERVICE] $svc -> Desactive"
        }
    }
}

# ── Application du profil ──────────────────────────────────────────────────────
switch ($Profil) {

    '1' {
        Write-Host ""
        Write-Host "  Profil [1] Maximum - restauration des parametres par defaut" -ForegroundColor Green
        Write-Host ""

        Remove-WUPolicies
        Enable-WUServices

        Write-Host "    [OK] Toutes les politiques WU restrictives supprimees"
        Write-Host "    [OK] Windows Update complet reactive"
    }

    '2' {
        Write-Host ""
        Write-Host "  Profil [2] Securite uniquement" -ForegroundColor Yellow
        Write-Host ""

        # Recup version actuelle pour epingler la release (bloque les mises a jour de fonctionnalites)
        $releaseId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
        if (-not $releaseId) {
            $releaseId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ReleaseId
        }

        # Epingler la version courante (bloque feature updates)
        Set-RegValue $WU_PATH 'TargetReleaseVersion'     1            'DWord'
        Set-RegValue $WU_PATH 'TargetReleaseVersionInfo' $releaseId   'String'
        Set-RegValue $WU_PATH 'DisableWUfBSafeguards'    1            'DWord'
        Write-Host "    [POLITIQUES] Version epinglee : $releaseId (pas de mises a jour fonctionnalites)"

        # Desactiver les mises a jour de pilotes via Windows Update
        Set-RegValue $DRV_META   'PreventDeviceMetadataFromNetwork' 1 'DWord'
        Set-RegValue $DRV_SEARCH 'SearchOrderConfig'                0 'DWord'
        Write-Host "    [POLITIQUES] Mises a jour pilotes via WU desactivees"

        # MAJ auto : telecharger et notifier avant installation (mode conservateur)
        Set-RegValue $AU_PATH 'NoAutoUpdate'            0 'DWord'
        Set-RegValue $AU_PATH 'AUOptions'               3 'DWord'   # 3 = telecharger auto, notifier install
        Set-RegValue $AU_PATH 'AutoInstallMinorUpdates' 1 'DWord'
        Write-Host "    [POLITIQUES] Mode : telechargement auto, notification avant installation"

        Enable-WUServices
        Write-Host "    [OK] Profil securite applique"
    }

    '3' {
        Write-Host ""
        Write-Host "  Profil [3] Desactiver Windows Update" -ForegroundColor Red
        Write-Host "  ATTENTION : sans mises a jour de securite, le systeme est expose." -ForegroundColor DarkRed
        Write-Host ""

        # Bloquer l'acces a Windows Update
        Set-RegValue $WU_PATH 'DisableWindowsUpdateAccess' 1 'DWord'
        Set-RegValue $WU_PATH 'DisableWUfBSafeguards'      1 'DWord'
        Write-Host "    [POLITIQUES] Acces Windows Update bloque"

        # Desactiver les telechargements automatiques
        Set-RegValue $AU_PATH 'NoAutoUpdate' 1 'DWord'
        Set-RegValue $AU_PATH 'AUOptions'    1 'DWord'   # 1 = jamais
        Write-Host "    [POLITIQUES] Telechargement auto desactive"

        Disable-WUServices
        Write-Host "    [OK] Windows Update completement desactive"
    }
}

Write-Host ""
