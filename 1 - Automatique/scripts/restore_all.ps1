#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Opti Pack - Restauration complete
    Annule tous les tweaks appliques par run_all.ps1

.DESCRIPTION
    Remet le systeme dans son etat d'origine.
    Utilise le point de restauration cree au lancement (methode recommandee)
    ou applique les valeurs par defaut de chaque tweak.
#>

$ErrorActionPreference = 'Continue'
$ROOT    = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$RESTORE = Join-Path $ROOT "restore"

function Write-Step {
    param([string]$Msg)
    Write-Host ""
    Write-Host ">>> $Msg" -ForegroundColor Yellow
}

function Invoke-Script {
    param([string]$Path)
    $name = Split-Path $Path -Leaf
    Write-Host "    $name ... " -NoNewline
    try {
        & $Path
        Write-Host "[OK]" -ForegroundColor Green
    } catch {
        Write-Host "[ERREUR] $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host "   OPTI PACK - RESTAURATION                     " -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Cette operation annule tous les tweaks appliques par run_all.ps1" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "Confirmer la restauration ? (O/N)"
if ($confirm -ine 'O') {
    Write-Host "Annule." -ForegroundColor Gray
    exit
}

Write-Step "Restauration registre (valeurs par defaut Windows)"
Invoke-Script "$RESTORE\01_registry.ps1"

Write-Step "Restauration services"
Invoke-Script "$RESTORE\02_services.ps1"

Write-Step "Restauration configuration boot (bcdedit)"
Invoke-Script "$RESTORE\03_bcdedit.ps1"

Write-Step "Restauration DNS (DHCP automatique)"
Invoke-Script "$RESTORE\04_dns.ps1"

Write-Step "Suppression politiques Microsoft Edge"
Invoke-Script "$RESTORE\05_edge.ps1"

Write-Step "Suppression SetTimerResolution du demarrage"
Invoke-Script "$RESTORE\06_timer.ps1"

Write-Step "Restauration plan d'alimentation"
Invoke-Script "$RESTORE\07_power.ps1"

Write-Step "Restauration suspension selective USB"
Invoke-Script "$RESTORE\08_usb.ps1"

Write-Step "Suppression politiques IA / Recall / Copilot"
Invoke-Script "$RESTORE\09_ai_restore.ps1"

Write-Step "Aide reinstallation applications UWP"
Invoke-Script "$RESTORE\10_debloat_restore.ps1"

# Taches planifiees
Write-Host ""
Write-Host "    Note: les taches planifiees de telemetrie desactivees ne sont pas" -ForegroundColor Gray
Write-Host "    restaurees automatiquement. Les reactivir via : Planificateur de taches" -ForegroundColor Gray
Write-Host "    (Microsoft\Windows\Customer Experience Improvement Program, etc.)" -ForegroundColor Gray

# Options conditionnelles Edge / OneDrive
Write-Host ""
$restoreEdge = Read-Host "Reinstaller Microsoft Edge ? (O/N)"
if ($restoreEdge -ieq 'O') {
    Write-Step "OPTION - Reinstallation Microsoft Edge"
    Invoke-Script "$RESTORE\opt_edge_restore.ps1"
}

$restoreOneDrive = Read-Host "Reinstaller OneDrive ? (O/N)"
if ($restoreOneDrive -ieq 'O') {
    Write-Step "OPTION - Reinstallation OneDrive"
    Invoke-Script "$RESTORE\opt_onedrive_restore.ps1"
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "   RESTAURATION TERMINEE                        " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Redemarrer le PC pour finaliser." -ForegroundColor Yellow
Write-Host ""
Write-Host "Si des problemes persistent, utiliser le point de restauration systeme" -ForegroundColor Gray
Write-Host "cree par run_all.ps1 (Panneau de configuration > Recuperation)." -ForegroundColor Gray
Write-Host ""

$restart = Read-Host "Redemarrer maintenant ? (O/N)"
if ($restart -ieq 'O') {
    Restart-Computer -Force
}
