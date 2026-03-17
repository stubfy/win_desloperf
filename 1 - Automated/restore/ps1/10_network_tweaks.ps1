# restore\10_network_tweaks.ps1 - Restore network tweaks

# ── Teredo ────────────────────────────────────────────────────────────────────
netsh interface teredo set state default 2>&1 | ForEach-Object { Write-Host "    $_" }
Write-Host "    Teredo restored (default state)"

# ── TCP global stack ──────────────────────────────────────────────────────────
netsh int tcp set global autotuninglevel=normal 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set heuristics enabled 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global rss=enabled 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global ecncapability=default 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global rsc=enabled 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global nonsackrttresiliency=enabled 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global maxsynretransmissions=2 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global minrto=300 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global congestionprovider=cubic 2>&1 | ForEach-Object { Write-Host "    $_" }
Write-Host "    TCP global stack restored"

# ── LSO re-enable ─────────────────────────────────────────────────────────────
$activeAdapters = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })
foreach ($adapter in $activeAdapters) {
    Enable-NetAdapterLso -Name $adapter.Name -IncludeHidden -ErrorAction SilentlyContinue
    Write-Host "    LSO restored: $($adapter.Name)"
}

# ── Nagle restore (remove per-interface keys) ─────────────────────────────────
$ethernetAdapters = @(Get-NetAdapter | Where-Object {
    $_.Status -eq 'Up' -and $_.PhysicalMediaType -eq '802.3'
})
foreach ($adapter in $ethernetAdapters) {
    $guid      = $adapter.InterfaceGuid
    $ifacePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
    if (Test-Path $ifacePath) {
        Remove-ItemProperty -Path $ifacePath -Name 'TcpAckFrequency' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $ifacePath -Name 'TCPNoDelay'      -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $ifacePath -Name 'TcpDelAckTicks'  -ErrorAction SilentlyContinue
        Write-Host "    Nagle restored: $($adapter.Name)"
    }
}

# ── MaxUserPort restore ───────────────────────────────────────────────────────
$tcpParamsPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
Remove-ItemProperty -Path $tcpParamsPath -Name 'MaxUserPort' -ErrorAction SilentlyContinue
Write-Host "    MaxUserPort removed (restored to Windows default)"

# ── QoS Psched restore ───────────────────────────────────────────────────────
$nlaPschedPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched\NLA'
if (Test-Path $nlaPschedPath) {
    Remove-ItemProperty -Path $nlaPschedPath -Name 'Do not use NLA' -ErrorAction SilentlyContinue
    Write-Host "    QoS NLA key removed"
}
$pschedPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'
Remove-ItemProperty -Path $pschedPath -Name 'NonBestEffortLimit' -ErrorAction SilentlyContinue
Write-Host "    QoS NonBestEffortLimit key removed"
