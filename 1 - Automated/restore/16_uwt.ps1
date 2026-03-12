# restore\16_uwt.ps1 - Restore defaults for UWT-equivalent tweaks

$REG = Join-Path $PSScriptRoot "uwt_defaults.reg"

if (-not (Test-Path $REG)) {
    Write-Host "    [ERROR] uwt_defaults.reg not found: $REG"
    exit 1
}

$result = Start-Process regedit.exe -ArgumentList "/s `"$REG`"" -Wait -PassThru
if ($result.ExitCode -eq 0) {
    Write-Host "    [OK] uwt_defaults.reg imported"
} else {
    Write-Host "    [WARN] regedit exit code: $($result.ExitCode)"
}

# wscsvc is restored automatically via restore\02_services.ps1 (JSON backup)
