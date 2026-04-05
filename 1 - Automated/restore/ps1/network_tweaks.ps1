# restore\network_tweaks.ps1 - Restore network tweaks

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

$networkFailures = [System.Collections.Generic.List[string]]::new()

function Invoke-NetshRestore {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$FailureLabel
    )

    & netsh @Arguments 2>&1 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) {
        $label = if ($FailureLabel) { $FailureLabel } else { "netsh $($Arguments -join ' ')" }
        $networkFailures.Add("$label (exit code $LASTEXITCODE)")
        Write-Host "    [WARN] $label failed with exit code $LASTEXITCODE" -ForegroundColor Yellow
        return $false
    }

    return $true
}

# ── Teredo ────────────────────────────────────────────────────────────────────
if (Invoke-NetshRestore -Arguments @('interface', 'teredo', 'set', 'state', 'default') -FailureLabel 'Teredo restore') {
    Write-Host "    Teredo restored (default state)"
}

# ── TCP global stack ──────────────────────────────────────────────────────────
$tcpRestoreOk = $true
$tcpCommands = @(
    [PSCustomObject]@{ Arguments = @('int', 'tcp', 'set', 'global', 'autotuninglevel=normal'); FailureLabel = 'TCP autotuninglevel restore' },
    [PSCustomObject]@{ Arguments = @('int', 'tcp', 'set', 'heuristics', 'enabled'); FailureLabel = 'TCP heuristics restore' },
    [PSCustomObject]@{ Arguments = @('int', 'tcp', 'set', 'global', 'rss=default'); FailureLabel = 'TCP RSS restore' },
    [PSCustomObject]@{ Arguments = @('int', 'tcp', 'set', 'global', 'ecncapability=default'); FailureLabel = 'TCP ECN restore' },
    [PSCustomObject]@{ Arguments = @('int', 'tcp', 'set', 'global', 'rsc=default'); FailureLabel = 'TCP RSC restore' },
    [PSCustomObject]@{ Arguments = @('int', 'tcp', 'set', 'global', 'nonsackrttresiliency=default'); FailureLabel = 'TCP non-sack RTT restore' },
    [PSCustomObject]@{ Arguments = @('int', 'tcp', 'set', 'global', 'maxsynretransmissions=2'); FailureLabel = 'TCP max SYN retransmissions restore' },
    [PSCustomObject]@{ Arguments = @('int', 'tcp', 'set', 'global', 'initialrto=3000'); FailureLabel = 'TCP initial RTO restore' }
)
foreach ($tcpCommand in $tcpCommands) {
    if (-not (Invoke-NetshRestore -Arguments $tcpCommand.Arguments -FailureLabel $tcpCommand.FailureLabel)) {
        $tcpRestoreOk = $false
    }
}
if ($tcpRestoreOk) {
    Write-Host "    TCP global stack restored"
}

# ── LSO re-enable ─────────────────────────────────────────────────────────────
$activeAdapters = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })
foreach ($adapter in $activeAdapters) {
    Enable-NetAdapterLso -Name $adapter.Name -IncludeHidden -ErrorAction SilentlyContinue
    Write-Host "    LSO restored: $($adapter.Name)"
}

# ── Nagle restore (remove per-interface keys) ─────────────────────────────────
$nagleSelection = Get-NagleTargetAdapters
$ethernetAdapters = @($nagleSelection.Adapters)
if ($nagleSelection.Mode -in @('fallback', 'path-fallback')) {
    Write-Host "    Nagle select  : $($nagleSelection.Note)" -ForegroundColor DarkGray
}
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
if ($ethernetAdapters.Count -eq 0) {
    Write-Host "    Nagle restore : $($nagleSelection.Note)"
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

# ── NIC Power Saving restore ──────────────────────────────────────────────────
$BACKUP_DIR    = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "backup"
$nicBackupFile = Join-Path $BACKUP_DIR 'nic_power_state.json'

if (Test-Path $nicBackupFile) {
    $nicBackup = Get-Content $nicBackupFile -Raw | ConvertFrom-Json
    foreach ($adapterProp in $nicBackup.PSObject.Properties) {
        $adapterName = $adapterProp.Name
        $state       = $adapterProp.Value

        $adapter = Get-NetAdapter -Name $adapterName -ErrorAction SilentlyContinue
        if (-not $adapter) {
            Write-Host "    NIC power restore: adapter '$adapterName' not found, skipping"
            continue
        }

        $restored = 0

        foreach ($apProp in $state.AdvancedProperties.PSObject.Properties) {
            $regKeyword          = $apProp.Name
            $originalDisplayValue = $apProp.Value.DisplayValue
            if ($null -eq $originalDisplayValue) { continue }
            Set-NetAdapterAdvancedProperty -Name $adapterName -RegistryKeyword $regKeyword -DisplayValue $originalDisplayValue -ErrorAction SilentlyContinue
            $restored++
        }

        # Restore PnpCapabilities
        $pnpPath = $state.PnpCapabilitiesPath
        if ($state.PnpCapabilitiesExisted -and $null -ne $state.PnpCapabilities) {
            Set-ItemProperty -Path $pnpPath -Name 'PnpCapabilities' -Value ([int]$state.PnpCapabilities) -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Host "    $adapterName: PnpCapabilities restored = $($state.PnpCapabilities)"
        } elseif (-not $state.PnpCapabilitiesExisted) {
            Remove-ItemProperty -Path $pnpPath -Name 'PnpCapabilities' -ErrorAction SilentlyContinue
            Write-Host "    $adapterName: PnpCapabilities removed (was not set before)"
        }

        # Restore WakeEnabled
        $wakePath = $state.WakeEnabledPath
        if ($state.WakeEnabledExisted -and $null -ne $state.WakeEnabled) {
            Set-ItemProperty -Path $wakePath -Name 'WakeEnabled' -Value ([int]$state.WakeEnabled) -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Host "    $adapterName: WakeEnabled restored = $($state.WakeEnabled)"
        } elseif (-not $state.WakeEnabledExisted) {
            Remove-ItemProperty -Path $wakePath -Name 'WakeEnabled' -ErrorAction SilentlyContinue
        }

        Write-Host "    NIC power restored: $adapterName ($restored advanced properties)"
    }
} else {
    Write-Host "    NIC power restore: no backup found, removing PnpCapabilities override"
    foreach ($adapter in @(Get-NetAdapter -Physical -Status Up -ErrorAction SilentlyContinue)) {
        $devParamsPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($adapter.PnpDeviceID)\Device Parameters"
        Remove-ItemProperty -Path $devParamsPath -Name 'PnpCapabilities' -ErrorAction SilentlyContinue
        Write-Host "    $($adapter.Name): PnpCapabilities removed (fallback)"
    }
}

if ($networkFailures.Count -gt 0) {
    throw "Network restore completed with failures: $($networkFailures -join '; ')"
}
