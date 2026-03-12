# 16_uwt.ps1 - Registry tweaks equivalent to Ultimate Windows Tweaker 5 (settings_v2.ini)
# Covers: Explorer appearance, performance, UAC, privacy, context menu cleanup

$REG = Join-Path $PSScriptRoot "uwt_tweaks.reg"

if (-not (Test-Path $REG)) {
    Write-Host "    [ERROR] uwt_tweaks.reg not found: $REG"
    exit 1
}

$result = Start-Process regedit.exe -ArgumentList "/s `"$REG`"" -Wait -PassThru
if ($result.ExitCode -eq 0) {
    Write-Host "    [OK] uwt_tweaks.reg imported"
} else {
    Write-Host "    [WARN] regedit exit code: $($result.ExitCode)"
}

# --- Disable Windows Security Center service (not in 03_services.ps1) ---
$svc = Get-Service 'wscsvc' -ErrorAction SilentlyContinue
if ($svc) {
    Stop-Service  'wscsvc' -Force -ErrorAction SilentlyContinue
    Set-Service   'wscsvc' -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "    [DISABLED]   wscsvc (Windows Security Center)"
} else {
    Write-Host "    [NOT FOUND]  wscsvc" -ForegroundColor Gray
}
