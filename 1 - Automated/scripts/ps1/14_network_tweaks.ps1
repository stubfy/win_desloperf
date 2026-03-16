# 14_network_tweaks.ps1 - Network stack optimizations
#
# Teredo: An IPv6 transition technology that tunnels IPv6 traffic over UDP/IPv4.
# It creates a virtual network adapter and maintains a NAT traversal session with
# a Teredo relay server on the internet. Issues for gaming:
#   - Adds a persistent UDP "ping" session to a Microsoft relay server, generating
#     background traffic even when no IPv6 content is being accessed.
#   - The Teredo NAT traversal logic can interfere with some game UDP paths that
#     use the same port range, occasionally causing unexpected routing behavior.
#   - On a dual-stack ISP connection where native IPv6 is available, Teredo is
#     redundant; on IPv4-only connections it tunnels through a relay which adds
#     a hop and increases latency compared to direct IPv4.
# Effect: Disabling Teredo removes the virtual adapter and background relay session.
# The DisabledComponents=0x20 key in tweaks_consolidated.reg handles IPv4 preference
# at the stack level; this command handles the Teredo tunnel adapter specifically.
#
# TCP stack (netsh):
#   autotuninglevel=normal  : dynamic receive window, do not override (default is correct)
#   heuristics disabled     : prevents Windows from silently throttling the TCP window
#   rss=enabled             : distribute NIC receive processing across CPU cores
#   ecncapability=enabled   : congestion signal without packet drop (modern networks)
#   rsc=disabled            : receive coalescing batches packets, adds latency -- off for gaming
#   nonsackrttresiliency=disabled : removes extra RTT conservatism added by Windows
#   maxsynretransmissions=2 : 2 SYN retries -- reasonable default (1 is too aggressive)
#   minrto=300              : explicit default, guards against regressions
#   congestionprovider=cubic : Windows 11 default, same as Linux -- no reason to change
#
# LSO (Large Send Offload): offloads TCP segmentation to the NIC. Saves CPU at high
# throughput but adds variable coalescing latency per batch. Disabled on active adapters.
#
# QoS Psched:
#   NonBestEffortLimit=0    : remove the QoS bandwidth reservation (default 20%)
#   Do not use NLA=1        : bypass the NLA lookup in the QoS Packet Scheduler
#
# Nagle algorithm: batches small outbound TCP packets to reduce overhead. For gaming,
# this adds up to 200 ms delay on small packets (delayed ACK interaction). Disabling
# with TcpAckFrequency=1, TCPNoDelay=1, TcpDelAckTicks=0 sends each segment immediately.
# Applied per-interface via the adapter GUID, on the active Ethernet adapter only.
#
# MaxUserPort: extends ephemeral port range to 65534 (default ~16K).
# Useful during development (many simultaneous connections) and avoids port exhaustion.
#
# Rollback: restore\14_network_tweaks.ps1

# ── Teredo ────────────────────────────────────────────────────────────────────
netsh interface teredo set state disabled 2>&1 | ForEach-Object { Write-Host "    $_" }
Write-Host "    Teredo disabled"

# ── TCP global stack ──────────────────────────────────────────────────────────
netsh int tcp set global autotuninglevel=normal 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set heuristics disabled 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global rss=enabled 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global ecncapability=enabled 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global rsc=disabled 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global nonsackrttresiliency=disabled 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global maxsynretransmissions=2 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global minrto=300 2>&1 | ForEach-Object { Write-Host "    $_" }
netsh int tcp set global congestionprovider=cubic 2>&1 | ForEach-Object { Write-Host "    $_" }
Write-Host "    TCP global stack configured"

# ── LSO disable ───────────────────────────────────────────────────────────────
$activeAdapters = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })
foreach ($adapter in $activeAdapters) {
    Disable-NetAdapterLso -Name $adapter.Name -IncludeHidden -ErrorAction SilentlyContinue
    Write-Host "    LSO disabled: $($adapter.Name)"
}
if ($activeAdapters.Count -eq 0) {
    Write-Host "    LSO: no active adapters found"
}

# ── QoS Psched ────────────────────────────────────────────────────────────────
$pschedPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'
if (-not (Test-Path $pschedPath)) {
    New-Item -Path $pschedPath -Force | Out-Null
}
Set-ItemProperty -Path $pschedPath -Name 'NonBestEffortLimit' -Value 0 -Type DWord -Force
Write-Host "    QoS NonBestEffortLimit = 0"

$nlaPschedPath = Join-Path $pschedPath 'NLA'
if (-not (Test-Path $nlaPschedPath)) {
    New-Item -Path $nlaPschedPath -Force | Out-Null
}
Set-ItemProperty -Path $nlaPschedPath -Name 'Do not use NLA' -Value 1 -Type DWord -Force
Write-Host "    QoS NLA bypass = 1"

# ── Nagle disable (per active Ethernet interface) ─────────────────────────────
$ethernetAdapters = @(Get-NetAdapter | Where-Object {
    $_.Status -eq 'Up' -and $_.PhysicalMediaType -eq '802.3'
})
foreach ($adapter in $ethernetAdapters) {
    $guid      = $adapter.InterfaceGuid
    $ifacePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
    if (Test-Path $ifacePath) {
        Set-ItemProperty -Path $ifacePath -Name 'TcpAckFrequency' -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $ifacePath -Name 'TCPNoDelay'      -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $ifacePath -Name 'TcpDelAckTicks'  -Value 0 -Type DWord -Force
        Write-Host "    Nagle disabled: $($adapter.Name)"
    } else {
        Write-Host "    Nagle: interface path not found for $($adapter.Name)"
    }
}
if ($ethernetAdapters.Count -eq 0) {
    Write-Host "    Nagle: no active Ethernet adapter found"
}

# ── MaxUserPort ───────────────────────────────────────────────────────────────
$tcpParamsPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
Set-ItemProperty -Path $tcpParamsPath -Name 'MaxUserPort' -Value 65534 -Type DWord -Force
Write-Host "    MaxUserPort = 65534"
