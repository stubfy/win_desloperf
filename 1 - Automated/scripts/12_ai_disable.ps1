# 12_ai_disable.ps1 - Disable AI / Recall / Copilot features (Windows 11 25H2)

$policies = @{
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' = @{
        'DisableAIDataAnalysis' = 1   # Disable Recall (AI screen recording)
        'AllowRecallEnablement' = 0   # Prevent Recall from being enabled
    }
    'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' = @{
        'TurnOffWindowsCopilot' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' = @{
        'TurnOffWindowsCopilot' = 1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\ChatIcon' = @{
        'Show' = 3   # 3 = hide Copilot icon from taskbar
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' = @{
        'DODownloadMode' = 0   # Disable P2P update sharing mode
    }
    # Additional Copilot keys (source: Chris Titus WinUtil)
    'HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot' = @{
        'IsCopilotAvailable' = 0
    }
    'HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat' = @{
        'IsUserEligible' = 0
    }
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot' = @{
        'AllowCopilotRuntime' = 0
    }
    # Cross-Device Resume (24H2+) - disables activity resume across devices
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

# Block Copilot shell extension (WinUtil CLSID)
$blockedPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
if (-not (Test-Path $blockedPath)) { New-Item -Path $blockedPath -Force | Out-Null }
Set-ItemProperty -Path $blockedPath -Name "{CB5571B1-A131-4C41-BFEF-57696FCE7CA2}" -Value "Copilot Shell Extension" -Type String -ErrorAction SilentlyContinue
Write-Host "    [SET] Copilot shell extension blocked"
