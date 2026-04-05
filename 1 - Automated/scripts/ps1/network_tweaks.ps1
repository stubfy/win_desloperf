# network_tweaks.ps1 - Network stack optimizations
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
#   initialrto=300          : SYN retransmit time explicit default, guards against regressions
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
# Applied per-interface via the adapter GUID, preferring active wired adapters and falling back to any compatible active client adapter when metadata is incomplete.
#
# MaxUserPort: extends ephemeral port range to 65534 (default ~16K).
# Useful during development (many simultaneous connections) and avoids port exhaustion.
#
# Rollback: restore\network_tweaks.ps1

function Get-NagleTargetAdapters {
    $upAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
    $usable = @($upAdapters | Where-Object {
        $guid = $_.InterfaceGuid
        if (-not $guid) { return $false }
        $ifacePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        Test-Path $ifacePath
    })

    $strict = @($usable | Where-Object { $_.PhysicalMediaType -eq '802.3' })
    if ($strict.Count -gt 0) {
        return [PSCustomObject]@{
            Adapters = $strict
            Mode     = 'strict'
            Note     = $null
        }
    }

    $fallback = @($usable | Where-Object {
        $label = ("{0} {1}" -f $_.Name, $_.InterfaceDescription)
        $isExcluded = $label -match 'Loopback|Teredo|Tunnel|VPN|PPP|WAN Miniport|Bluetooth'
        $isLikelyClientAdapter = [bool]$_.HardwareInterface -or $label -match 'Ethernet|Wi-?Fi|Wireless|WLAN|PRO/1000|Gigabit|Realtek|PCIe|virtio|Intel|Broadcom'
        $isLikelyClientAdapter -and -not $isExcluded
    })
    if ($fallback.Count -gt 0) {
        return [PSCustomObject]@{
            Adapters = $fallback
            Mode     = 'fallback'
            Note     = 'no adapter reported PhysicalMediaType=802.3; using compatible active adapter fallback'
        }
    }

    if ($usable.Count -gt 0) {
        return [PSCustomObject]@{
            Adapters = $usable
            Mode     = 'path-fallback'
            Note     = 'no adapter matched wired heuristics; using active adapter(s) with a TCP/IP interface path'
        }
    }

    return [PSCustomObject]@{
        Adapters = @()
        Mode     = 'none'
        Note     = 'no compatible active adapter with a TCP/IP interface path found'
    }
}

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
netsh int tcp set global initialrto=300 2>&1 | ForEach-Object { Write-Host "    $_" }
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

# ── Nagle disable (preferred active client adapters) ──────────────────────────
$nagleSelection = Get-NagleTargetAdapters
$ethernetAdapters = @($nagleSelection.Adapters)
if ($nagleSelection.Mode -in @('fallback', 'path-fallback')) {
    Write-Host "    Nagle select  : $($nagleSelection.Note)" -ForegroundColor DarkGray
}
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
    Write-Host "    Nagle: $($nagleSelection.Note)"
}

# ── MaxUserPort ───────────────────────────────────────────────────────────────
$tcpParamsPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
Set-ItemProperty -Path $tcpParamsPath -Name 'MaxUserPort' -Value 65534 -Type DWord -Force
Write-Host "    MaxUserPort = 65534"

# ── NIC Power Saving ──────────────────────────────────────────────────────────
$nicPowerProperties = @(
    @{ RegistryKeyword = 'EEE';                     DisplayName = 'Energy-Efficient Ethernet'; DisableValue = 'Disabled' }
    @{ RegistryKeyword = 'EnergyEfficientEthernet'; DisplayName = $null;                       DisableValue = 'Disabled' }
    @{ RegistryKeyword = 'GreenEthernet';           DisplayName = 'Green Ethernet';            DisableValue = 'Disabled' }
    @{ RegistryKeyword = 'GigabitLite';             DisplayName = 'Gigabit Lite';              DisableValue = 'Disabled' }
    @{ RegistryKeyword = 'WakeOnMagicPacket';       DisplayName = 'Wake on Magic Packet';      DisableValue = 'Disabled' }
    @{ RegistryKeyword = 'WakeOnPattern';           DisplayName = 'Wake on Pattern Match';     DisableValue = 'Disabled' }
    @{ RegistryKeyword = '*PMARPOffload';           DisplayName = $null;                       DisableValue = 'Disabled' }
    @{ RegistryKeyword = '*PMNSOffload';            DisplayName = $null;                       DisableValue = 'Disabled' }
    @{ RegistryKeyword = 'PowerSavingMode';         DisplayName = 'Power Saving Mode';         DisableValue = 'Disabled' }
    @{ RegistryKeyword = 'ReduceSpeedOnPowerDown';  DisplayName = 'Reduce Speed On Power Down'; DisableValue = 'Disabled' }
    @{ RegistryKeyword = 'AutoPowerSaveModeEnabled'; DisplayName = $null;                      DisableValue = 'Disabled' }
    @{ RegistryKeyword = 'EnablePME';               DisplayName = $null;                       DisableValue = 'Disabled' }
    @{ RegistryKeyword = 'AdaptivePowerManagement'; DisplayName = $null;                       DisableValue = 'Disabled' }
)

$nicAdapters = @(Get-NetAdapter -Physical -Status Up -ErrorAction SilentlyContinue)
foreach ($adapter in $nicAdapters) {
    $modified = 0

    foreach ($prop in $nicPowerProperties) {
        $handled = $false

        if ($prop.RegistryKeyword) {
            $existing = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $prop.RegistryKeyword -ErrorAction SilentlyContinue
            if ($existing -and $existing.DisplayValue -ne $prop.DisableValue) {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $prop.RegistryKeyword -DisplayValue $prop.DisableValue -ErrorAction SilentlyContinue
                Write-Host "    $($adapter.Name): $($prop.RegistryKeyword) -> Disabled"
                $modified++
                $handled = $true
            } elseif ($existing) {
                $handled = $true
            }
        }

        if (-not $handled -and $prop.DisplayName) {
            $existing = Get-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $prop.DisplayName -ErrorAction SilentlyContinue
            if ($existing -and $existing.DisplayValue -ne $prop.DisableValue) {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $prop.DisplayName -DisplayValue $prop.DisableValue -ErrorAction SilentlyContinue
                Write-Host "    $($adapter.Name): $($prop.DisplayName) -> Disabled"
                $modified++
            }
        }
    }

    # WolShutdownLinkSpeed: set to highest speed or "Not Speed Reduction" (performance-oriented)
    $wolProp = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword 'WolShutdownLinkSpeed' -ErrorAction SilentlyContinue
    if ($wolProp) {
        $target = $wolProp.ValidDisplayValues | Where-Object { $_ -match 'Not Speed Reduction' } | Select-Object -First 1
        if (-not $target) {
            $target = $wolProp.ValidDisplayValues | Sort-Object -Descending | Select-Object -First 1
        }
        if ($target -and $wolProp.DisplayValue -ne $target) {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword 'WolShutdownLinkSpeed' -DisplayValue $target -ErrorAction SilentlyContinue
            Write-Host "    $($adapter.Name): WolShutdownLinkSpeed -> $target"
            $modified++
        }
    }

    # PnP power management: PnpCapabilities = 0x18 disables "Allow the computer to turn off this device"
    $devParamsPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($adapter.PnpDeviceID)\Device Parameters"
    if (-not (Test-Path $devParamsPath)) {
        New-Item -Path $devParamsPath -Force -ErrorAction SilentlyContinue | Out-Null
    }
    if (Test-Path $devParamsPath) {
        Set-ItemProperty -Path $devParamsPath -Name 'PnpCapabilities' -Value 24 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "    $($adapter.Name): PnpCapabilities = 24 (0x18)"
        $modified++
    }

    # WakeEnabled: disable wake-on-LAN at PnP level if Power subkey exists
    $powerPath = Join-Path $devParamsPath 'Power'
    if (Test-Path $powerPath) {
        Set-ItemProperty -Path $powerPath -Name 'WakeEnabled' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "    $($adapter.Name): WakeEnabled = 0"
        $modified++
    }

    Write-Host "    NIC power saving: $($adapter.Name) ($modified properties modified)"
}
if ($nicAdapters.Count -eq 0) {
    Write-Host "    NIC power saving: no active physical adapters found"
}



