#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Opti Pack - Lanceur principal
    Windows 11 25H2 - Optimisation Gaming / Debloat / QoL

.DESCRIPTION
    Execute tous les tweaks automatisables dans l'ordre recommande.
    Cree une sauvegarde avant toute modification.
    Pour annuler : .\restore_all.ps1

.NOTES
    Etapes manuelles post-execution : voir readme.txt a la racine du pack
#>

$ErrorActionPreference = 'Continue'
$ROOT         = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$SCRIPTS      = Join-Path $ROOT "scripts"
$PACK_VERSION = 'v0.1'
$LOG_DIR      = Join-Path $env:APPDATA 'win_unslopper\logs'
$LOG_FILE     = Join-Path $LOG_DIR "win_unslopper.log"

if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Msg
    Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
}

function Write-Step {
    param([string]$Msg)
    Write-Host ""
    Write-Host ">>> $Msg" -ForegroundColor Yellow
    Write-Log $Msg 'STEP'
}

function Invoke-Script {
    param([string]$Path)
    $name = Split-Path $Path -Leaf
    Write-Host "    $name ... " -NoNewline
    Write-Log "Debut : $name" 'RUN'
    try {
        $output = & $Path *>&1
        foreach ($line in $output) {
            if ($line -is [System.Management.Automation.ErrorRecord]) {
                Write-Log "  [ERR] $($line.Exception.Message)" 'WARN'
            } else {
                Write-Log "  $line" 'OUT'
            }
        }
        Write-Host "[OK]" -ForegroundColor Green
        Write-Log "Fin : $name -> OK" 'OK'
    } catch {
        Write-Host "[ERREUR] $_" -ForegroundColor Red
        Write-Log "Fin : $name -> ERREUR : $_" 'ERROR'
        Write-Log "  StackTrace: $($_.ScriptStackTrace)" 'ERROR'
    }
}

# ── En-tete ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  win_unslopper v0.1" -ForegroundColor Cyan
Write-Host ""
Write-Host "  by stubfy" -ForegroundColor DarkGray
Write-Host ""

# ── Init log ──────────────────────────────────────────────────────────────────
Write-Log "============================================================"
Write-Log "win_unslopper $PACK_VERSION" 'INFO'
Write-Log "Date    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
Write-Log "OS      : $([System.Environment]::OSVersion.VersionString)" 'INFO'
Write-Log "Machine : $env:COMPUTERNAME" 'INFO'
Write-Log "User    : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" 'INFO'
Write-Log "Log     : $LOG_FILE" 'INFO'
Write-Log "============================================================"
Write-Host "  Log : $LOG_FILE" -ForegroundColor DarkGray
Write-Host ""

# ── OPTIONS OPTIONNELLES (prompt avant toute modification) ────────────────────
Write-Host "OPTIONS AVANT LANCEMENT :" -ForegroundColor Magenta
Write-Host "(Ces operations sont irreversibles sans reinstallation manuelle)" -ForegroundColor DarkGray
Write-Host ""

$uninstallEdge     = $false
$uninstallOneDrive = $false

$ans = Read-Host "  Desinstaller Microsoft Edge completement ? (O/N)"
if ($ans -ieq 'O') {
    $uninstallEdge = $true
    Write-Host "  -> Edge sera desinstalle apres les tweaks principaux." -ForegroundColor Yellow
    Write-Log "Option choisie : desinstallation Edge = OUI" 'INFO'
} else {
    Write-Log "Option choisie : desinstallation Edge = NON" 'INFO'
}

$ans = Read-Host "  Desinstaller OneDrive completement ? (O/N)"
if ($ans -ieq 'O') {
    $uninstallOneDrive = $true
    Write-Host "  -> OneDrive sera desinstalle apres les tweaks principaux." -ForegroundColor Yellow
    Write-Log "Option choisie : desinstallation OneDrive = OUI" 'INFO'
} else {
    Write-Log "Option choisie : desinstallation OneDrive = NON" 'INFO'
}

Write-Host ""

# ── PHASE A : Sauvegarde pre-tweaks ──────────────────────────────────────────
Write-Step "PHASE A - Sauvegarde (point de restauration + etat services)"
Invoke-Script "$SCRIPTS\01_backup.ps1"

# ── PHASE B : Tweaks automatiques ─────────────────────────────────────────────
Write-Step "PHASE B.1 - Tweaks registre (consolides, dedupliques)"
Invoke-Script "$SCRIPTS\02_registry.ps1"

Write-Step "PHASE B.2 - Desactivation services inutiles"
Invoke-Script "$SCRIPTS\03_services.ps1"

Write-Step "PHASE B.3 - Configuration boot (bcdedit)"
Invoke-Script "$SCRIPTS\04_bcdedit.ps1"

Write-Step "PHASE B.4 - Plan d'alimentation Ultimate Performance"
Invoke-Script "$SCRIPTS\05_power.ps1"

Write-Step "PHASE B.5 - DNS Cloudflare (1.1.1.1 / 1.0.0.1)"
Invoke-Script "$SCRIPTS\06_dns.ps1"

Write-Step "PHASE B.6 - Politiques Microsoft Edge"
Invoke-Script "$SCRIPTS\07_edge.ps1"

Write-Step "PHASE B.7 - Suppression applications UWP bloatware"
Invoke-Script "$SCRIPTS\08_debloat.ps1"

Write-Step "PHASE B.8 - O`&O ShutUp10++ (mode silencieux)"
Invoke-Script "$SCRIPTS\09_oosu10.ps1"

Write-Step "PHASE B.9 - SetTimerResolution au demarrage"
Invoke-Script "$SCRIPTS\10_timer.ps1"

Write-Step "PHASE B.10 - Suspension selective USB"
Invoke-Script "$SCRIPTS\11_usb.ps1"

Write-Step "PHASE B.11 - Desactivation IA / Recall / Copilot (25H2)"
Invoke-Script "$SCRIPTS\12_ai_disable.ps1"

Write-Step "PHASE B.12 - Taches planifiees telemetrie + PS7 + Brave"
Invoke-Script "$SCRIPTS\13_telemetry_tasks.ps1"

# ── OPTIONS : desinstallations physiques ─────────────────────────────────────
if ($uninstallEdge) {
    Write-Step "OPTION - Desinstallation physique Microsoft Edge"
    Invoke-Script "$SCRIPTS\opt_edge_uninstall.ps1"
}

if ($uninstallOneDrive) {
    Write-Step "OPTION - Desinstallation OneDrive (Win32)"
    Invoke-Script "$SCRIPTS\opt_onedrive_uninstall.ps1"
}

# ── Resume ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "   TWEAKS AUTOMATIQUES TERMINES                 " -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "ETAPES MANUELLES RESTANTES (voir readme.txt a la racine du pack) :" -ForegroundColor Cyan
Write-Host "  1. Redemarrer le PC"
Write-Host "  2. [Mode Sans Echec] Desactiver Windows Defender"
Write-Host "  3. MSI Utils - activer MSI sur GPU / NIC / NVMe"
Write-Host "  4. Interrupt Affinity - epingler interruptions GPU sur un coeur CPU"
Write-Host "  5. Carte reseau - desactiver offloads, augmenter buffers"
Write-Host "  6. Gestionnaire de peripheriques - economie d'energie USB"
Write-Host "  7. NVIDIA Profile Inspector - profils par jeu"
Write-Host "  8. Panneau de configuration - suivre readme du dossier 4"
Write-Host ""
Write-Host "Pour annuler tous les tweaks : .\restore_all.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "Log complet : $LOG_FILE" -ForegroundColor DarkGray
Write-Host ""

Write-Log "============================================================"
Write-Log "Execution terminee : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'INFO'
Write-Log "============================================================"

$restart = Read-Host "Redemarrer maintenant ? (O/N)"
if ($restart -ieq 'O') {
    Write-Log "Redemarrage demande par l'utilisateur." 'INFO'
    Restart-Computer -Force
}
