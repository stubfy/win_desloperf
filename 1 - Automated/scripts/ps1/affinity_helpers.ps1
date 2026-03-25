# affinity_helpers.ps1 - Shared helpers for interrupt affinity scripts
#
# Dot-sourced by: set_affinity.ps1, restore_affinity.ps1, backup.ps1, snapshot.ps1
#
# Provides: GPU detection, USB mouse detection, generic PCI chain walk,
#           bitmask generation, registry write, config read/write, state capture.

# ── PDO name helper ───────────────────────────────────────────────────────────
function Get-PdoName {
    param([string]$InstanceId)
    try {
        $p = Get-PnpDeviceProperty -InstanceId $InstanceId `
            -KeyName 'DEVPKEY_Device_PDOName' -ErrorAction Stop
        return $p.Data
    } catch { return $null }
}

# ── GPU detection ─────────────────────────────────────────────────────────────
function Find-DiscreteGpu {
    $allGpus = Get-PnpDevice -Class Display -Status OK -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match '^PCI\\' }
    if (-not $allGpus) { return $null }

    $igpuPattern = 'Intel.*(UHD|Iris|HD Graphics)|Microsoft Basic Display'
    $dGpus = $allGpus | Where-Object { $_.FriendlyName -notmatch $igpuPattern }
    if (-not $dGpus) { $dGpus = $allGpus }

    $gpu = $dGpus | Where-Object { $_.FriendlyName -match 'NVIDIA' } | Select-Object -First 1
    if (-not $gpu) { $gpu = $dGpus | Where-Object { $_.FriendlyName -match 'AMD|Radeon' } | Select-Object -First 1 }
    if (-not $gpu) { $gpu = $dGpus | Select-Object -First 1 }
    return $gpu
}

# ── USB mouse detection ───────────────────────────────────────────────────────
function Find-UsbMice {
    # Returns all mice whose parent chain passes through a USB\ node.
    # Covers USB dongles (wireless) and wired USB mice alike.
    $mice = Get-PnpDevice -Class Mouse -Status OK -ErrorAction SilentlyContinue
    if (-not $mice) { return @() }

    $usbMice = @()
    foreach ($mouse in $mice) {
        $current = $mouse.InstanceId
        $isUsb   = $false
        for ($depth = 0; $depth -lt 12; $depth++) {
            try {
                $parent = (Get-PnpDeviceProperty -InstanceId $current `
                    -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop).Data
                if ($parent -match '^USB\\')  { $isUsb = $true; break }
                if ($parent -match '^ACPI\\|^ROOT\\|^PCI\\') { break }
                $current = $parent
            } catch { break }
        }
        if ($isUsb) { $usbMice += $mouse }
    }
    return $usbMice
}

# ── Generic PCI chain walk ────────────────────────────────────────────────────
function Get-PciChainFromDevice {
    <#
    .SYNOPSIS
        Walks the device parent chain upward to build a PCI device chain.

    .DESCRIPTION
        For PCI devices (GPU): adds the device directly as the first chain element,
        then continues walking PCI ancestors (Bridge, Root Complex).

        For non-PCI devices (HID mouse): silently traverses HID\, USB\ nodes
        upward until the first PCI\ ancestor is found (typically the xHCI
        USB host controller), then continues walking PCI ancestors.

    .OUTPUTS
        List[PSCustomObject] of @{ Label; Id; DevObj } for each PCI device in chain.
    #>
    param(
        [string]$InstanceId,
        [string]$StartLabel = 'Device',
        [switch]$Quiet
    )

    $chain      = [System.Collections.Generic.List[object]]::new()
    $firstPciId = $null

    if ($InstanceId -match '^PCI\\') {
        # Device is already PCI (GPU case)
        $firstPciId = $InstanceId
    } else {
        # Walk up to find the first PCI ancestor (USB controller for mouse)
        $current = $InstanceId
        for ($depth = 0; $depth -lt 15; $depth++) {
            try {
                $parent = (Get-PnpDeviceProperty -InstanceId $current `
                    -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop).Data
                if ($parent -match '^PCI\\') {
                    $firstPciId = $parent
                    break
                }
                if ($parent -match '^ACPI\\|^ROOT\\') { break }  # Give up at ACPI root
                $current = $parent
            } catch { break }
        }
    }

    if (-not $firstPciId) { return $chain }

    # Add the first PCI device
    $chain.Add([PSCustomObject]@{
        Label  = $StartLabel
        Id     = $firstPciId
        DevObj = (Get-PdoName $firstPciId)
    })

    # Walk PCI chain upward: Bridge -> Root Complex
    try {
        $pp = Get-PnpDeviceProperty -InstanceId $firstPciId `
            -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop
        if ($pp.Data -match '^PCI\\') {
            $chain.Add([PSCustomObject]@{
                Label  = 'PCI Bridge'
                Id     = $pp.Data
                DevObj = (Get-PdoName $pp.Data)
            })
            $gpp = Get-PnpDeviceProperty -InstanceId $pp.Data `
                -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop
            if ($gpp.Data -match '^PCI\\') {
                $chain.Add([PSCustomObject]@{
                    Label  = 'Root Complex'
                    Id     = $gpp.Data
                    DevObj = (Get-PdoName $gpp.Data)
                })
            } elseif (-not $Quiet) {
                # Normal on AMD: Root Complex exposed as ACPI\PNP0A08, not PCI.
                # GPU + PCI Bridge is sufficient for IRQ pinning.
                Write-Host "    [NOTE] PCI parent is ACPI ($($gpp.Data)) -- normal on AMD. Bridge is sufficient." -ForegroundColor DarkGray
            }
        }
    } catch {}

    return $chain
}

# ── Affinity bitmask ──────────────────────────────────────────────────────────
function New-AffinityBitmask {
    param([int]$Core)
    # Use uint64 for systems with 32+ logical processors
    if ($Core -lt 32) {
        return [byte[]]([System.BitConverter]::GetBytes([uint32][math]::Pow(2, $Core)))
    } else {
        return [byte[]]([System.BitConverter]::GetBytes([uint64][math]::Pow(2, $Core)))
    }
}

# ── Write affinity policy ─────────────────────────────────────────────────────
function Write-AffinityPolicy {
    param(
        [System.Collections.Generic.List[object]]$Chain,
        [int]$Core
    )
    $bitmask    = New-AffinityBitmask -Core $Core
    $bitmaskHex = ($bitmask | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
    $ok         = 0

    for ($i = 0; $i -lt $Chain.Count; $i++) {
        $dev        = $Chain[$i]
        $policyPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.Id)\" +
                      "Device Parameters\Interrupt Management\Affinity Policy"
        try {
            if (-not (Test-Path $policyPath)) {
                New-Item -Path $policyPath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $policyPath -Name 'DevicePolicy' `
                -Value 4 -Type DWord -Force -ErrorAction Stop
            Set-ItemProperty -Path $policyPath -Name 'AssignmentSetOverride' `
                -Value $bitmask -Type Binary -Force -ErrorAction Stop
            Write-Host ("    [OK]  [{0}] {1,-20} -> core {2}  DevicePolicy=4  {3}" -f `
                ($i + 1), $dev.Label, $Core, $bitmaskHex) -ForegroundColor Green
            $ok++
        } catch {
            Write-Host ("    [ERROR] [{0}] {1,-20} : {2}" -f ($i + 1), $dev.Label, $_) -ForegroundColor Red
        }
    }
    return $ok
}

# ── Config read / write ───────────────────────────────────────────────────────
function Read-AffinityConfig {
    param([string]$ConfigPath)
    if (-not (Test-Path $ConfigPath)) { return $null }
    try {
        $config = Get-Content $ConfigPath -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $config.version -or $null -eq $config.groups) { return $null }
        return $config
    } catch { return $null }
}

function Save-AffinityConfig {
    param([string]$ConfigPath, [array]$Groups)
    @{
        version = 1
        groups  = $Groups
    } | ConvertTo-Json -Depth 3 | Set-Content $ConfigPath -Encoding UTF8
}

# ── Affinity state capture (for backup.ps1) ───────────────────────────────────
function Get-AffinityStateForChains {
    <#
    .SYNOPSIS
        Reads the current registry affinity state for all devices in the given chains.
    .OUTPUTS
        Hashtable keyed by device InstanceId with { Existed; DevicePolicy; AssignmentSetOverride }.
    #>
    param([object[]]$Chains)
    $state = @{}
    foreach ($chain in $Chains) {
        foreach ($dev in $chain) {
            if ($state.ContainsKey($dev.Id)) { continue }
            $policyPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.Id)\" +
                          "Device Parameters\Interrupt Management\Affinity Policy"
            if (Test-Path $policyPath) {
                $props = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
                $state[$dev.Id] = @{
                    Existed               = $true
                    DevicePolicy          = $props.DevicePolicy
                    AssignmentSetOverride = @($props.AssignmentSetOverride)
                }
            } else {
                $state[$dev.Id] = @{ Existed = $false }
            }
        }
    }
    return $state
}
