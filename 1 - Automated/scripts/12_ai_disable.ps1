# 12_ai_disable.ps1 - Disable AI / Recall / Copilot features (Windows 11 25H2)
#
# Windows 11 25H2 introduces several AI features that run background processes,
# capture screen content, and communicate with Microsoft servers. This script
# disables them via Group Policy equivalent registry keys.
#
# All keys written under HKLM\SOFTWARE\Policies\ or HKCU\SOFTWARE\Policies\
# function as Group Policy overrides and cannot be changed by the user from the
# Settings UI (they take precedence over user-accessible settings).
#
# Rollback: restore\09_ai_restore.ps1 removes all keys written here.

$policies = @{
    # ---- Recall (Windows 11 24H2+ AI feature) ----
    # Recall continuously captures screenshots and uses a local AI model to make
    # screen content searchable ("what was I looking at three days ago?"). It stores
    # images and extracted text in a local database.
    # DisableAIDataAnalysis=1: Disables the Recall AI analysis pipeline.
    # AllowRecallEnablement=0: Prevents the user from re-enabling Recall in Settings.
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' = @{
        'DisableAIDataAnalysis' = 1
        'AllowRecallEnablement' = 0
    }

    # ---- Copilot (current user + machine) ----
    # Copilot is the Windows-integrated AI assistant panel. Both HKCU and HKLM
    # keys are set to ensure the policy applies regardless of which hive Windows
    # checks on different builds.
    'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' = @{
        'TurnOffWindowsCopilot' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' = @{
        'TurnOffWindowsCopilot' = 1
    }

    # ---- Copilot taskbar icon ----
    # Show=3: Value 3 hides the Copilot icon from the taskbar entirely.
    # (0=Not configured, 1=Show, 2=Hide, 3=Disable)
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\ChatIcon' = @{
        'Show' = 3
    }

    # ---- Delivery Optimization P2P mode ----
    # DODownloadMode=0: Disables Delivery Optimization peer-to-peer update sharing.
    # Mode 0 = HTTP only (download from Microsoft CDN only, no LAN/Internet peers).
    # This is set here in addition to the DoSvc TriggerInfo removal in 03_services.ps1.
    # The two are intentionally redundant: the registry policy blocks the P2P logic
    # at the protocol layer, while removing TriggerInfo prevents the process from
    # ever starting in the background to check for work.
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' = @{
        'DODownloadMode' = 0
    }

    # ---- Copilot shell availability (WinUtil method) ----
    # These non-policy keys are checked by the Copilot shell runtime at startup
    # to determine whether to activate. Setting both to 0 provides an additional
    # suppression layer on top of the TurnOffWindowsCopilot policy above.
    'HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot' = @{
        'IsCopilotAvailable' = 0
    }
    'HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat' = @{
        'IsUserEligible' = 0
    }
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot' = @{
        'AllowCopilotRuntime' = 0
    }

    # ---- Cross-Device Resume (CDP) ----
    # EnableCdp=0: Disables the Connected Devices Platform (CDP) which powers
    # the "Cross-Device Resume" feature (24H2+). CDP allows Windows to resume
    # phone/browser activity on the PC and syncs clipboard/notifications across
    # devices. Also related to CDPSvc which is set to Manual in 03_services.ps1.
    # Note: EnableActivityFeed/PublishUserActivities in tweaks_consolidated.reg
    # also disables Timeline which uses the same CDP infrastructure.
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' = @{
        'EnableCdp' = 0
    }
}

foreach ($path in $policies.Keys) {
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    foreach ($name in $policies[$path].Keys) {
        Set-ItemProperty -Path $path -Name $name -Value $policies[$path][$name] -Type DWord -ErrorAction SilentlyContinue
        Write-Host "    [SET] $name = $($policies[$path][$name])  ($path)"
    }
}

# Block the Copilot shell extension (registered shell handler CLSID).
# Adding a CLSID to Shell Extensions\Blocked prevents it from loading into
# Explorer's context menu and shell extension pipeline. The same key in
# uwt_tweaks.reg blocks other unwanted extensions; Copilot is added here
# separately because it is handled by a dedicated AI script, not the UWT script.
$blockedPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
if (-not (Test-Path $blockedPath)) { New-Item -Path $blockedPath -Force | Out-Null }
Set-ItemProperty -Path $blockedPath -Name "{CB5571B1-A131-4C41-BFEF-57696FCE7CA2}" -Value "Copilot Shell Extension" -Type String -ErrorAction SilentlyContinue
Write-Host "    [SET] Copilot shell extension blocked"
