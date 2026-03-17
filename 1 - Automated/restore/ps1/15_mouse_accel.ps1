# restore\15_mouse_accel.ps1 - Restore default Windows mouse acceleration curves

$REG = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "scripts\ps1\mouse_fix\Windows_10+8.x_Default.reg"

if (-not (Test-Path $REG)) {
    Write-Host "    [ERROR] Default mouse reg not found: $REG" -ForegroundColor Red
    exit 1
}

$result = Start-Process regedit.exe -ArgumentList "/s `"$REG`"" -Wait -PassThru
if ($result.ExitCode -eq 0) {
    Write-Host "    [OK] Mouse acceleration curves restored to Windows default"
} else {
    Write-Host "    [WARN] regedit exit code: $($result.ExitCode)"
}
