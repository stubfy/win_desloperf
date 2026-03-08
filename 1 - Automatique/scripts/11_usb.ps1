# 11_usb.ps1 - Desactive la suspension selective USB sur le plan d'alimentation actif

$activeLine = powercfg -getactivescheme 2>&1 | Out-String
$scheme     = [regex]::Match($activeLine, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value

if (-not $scheme) {
    Write-Host "    ERREUR: impossible de determiner le GUID du plan actif." -ForegroundColor Red
    return
}

# Subgroup  : USB (2a737441-1930-4402-8d77-b2bebba308a3)
# Setting   : USB selective suspend (48e6b7a6-50f5-4782-a5d4-53bb8f07e226)
# Valeur    : 0 = Desactive, 1 = Active
powercfg /setacvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
powercfg /setdcvalueindex $scheme 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
powercfg /setactive $scheme 2>&1 | Out-Null

Write-Host "    Suspension selective USB desactivee sur le plan : $scheme"
