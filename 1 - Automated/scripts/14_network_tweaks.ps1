# 14_network_tweaks.ps1 - Additional network tweaks (source: Chris Titus WinUtil)

# Disable Teredo (IPv6-over-IPv4 tunnel, useless for gaming, may cause latency)
netsh interface teredo set state disabled 2>&1 | ForEach-Object { Write-Host "    $_" }
Write-Host "    Teredo disabled"
