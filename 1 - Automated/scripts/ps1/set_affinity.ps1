# set_affinity.ps1 - Pin GPU interrupt chain to a dedicated CPU core
#
# WHAT IT DOES
#   Pins hardware interrupts from the GPU to a dedicated CPU core by writing
#   IrqPolicySpecifiedProcessors (DevicePolicy=4) to the registry for each
#   device in the chain: GPU -> PCI Bridge -> PCI Root Complex.
#
# WHY
#   Windows distributes IRQs across all logical cores by default. GPU DPCs
#   can land on the same core running the render thread, causing latency spikes.
#   Pinning the entire interrupt chain to a dedicated core physically separates
#   GPU IRQ processing from game threads.
#
# HOW
#   For each device in the chain, writes:
#     HKLM\SYSTEM\CurrentControlSet\Enum\PCI\<DeviceID>\<InstanceID>\
#       Device Parameters\Interrupt Management\Affinity Policy\
#         DevicePolicy          = DWORD 4   (IrqPolicySpecifiedProcessors)
#         AssignmentSetOverride = REG_BINARY bitmask (little-endian KAFFINITY)
#
# ROLLBACK
#   Run restore_affinity.bat to remove or revert the affinity policy.
#
# NVIDIA NOTE
#   NVIDIA drivers reset interrupt affinity on each driver update.
#   Re-run set_affinity.bat after every NVIDIA driver update.

param([switch]$SkipReboot)

$ErrorActionPreference = 'Continue'

$TARGET_CORE = 2
$BITMASK     = [byte[]]([System.BitConverter]::GetBytes([uint32][math]::Pow(2, $TARGET_CORE)))
$BITMASK_HEX = ($BITMASK | ForEach-Object { '{0:X2}' -f $_ }) -join ' '

Write-Host "    Target  : core $TARGET_CORE  (bitmask $BITMASK_HEX)"

# ── A. GPU detection ──────────────────────────────────────────────────────────
$allGpus = Get-PnpDevice -Class Display -Status OK -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match '^PCI\\' }

if (-not $allGpus) {
    Write-Host "    [ERROR] No PCI display device found. Is the GPU driver installed?" -ForegroundColor Red
    return
}

$igpuPattern = 'Intel.*(UHD|Iris|HD Graphics)|Microsoft Basic Display'
$dGpus = $allGpus | Where-Object { $_.FriendlyName -notmatch $igpuPattern }

if (-not $dGpus) {
    Write-Host "    [WARN] No discrete GPU found. Using first PCI display device." -ForegroundColor Yellow
    $dGpus = $allGpus
}

$gpu = $dGpus | Where-Object { $_.FriendlyName -match 'NVIDIA' } | Select-Object -First 1
if (-not $gpu) { $gpu = $dGpus | Where-Object { $_.FriendlyName -match 'AMD|Radeon' } | Select-Object -First 1 }
if (-not $gpu) { $gpu = $dGpus | Select-Object -First 1 }

Write-Host "    GPU     : $($gpu.FriendlyName)"

# ── B. Walk PCI chain ─────────────────────────────────────────────────────────
function Get-PdoName([string]$InstanceId) {
    try {
        $p = Get-PnpDeviceProperty -InstanceId $InstanceId `
            -KeyName 'DEVPKEY_Device_PDOName' -ErrorAction Stop
        return $p.Data
    } catch { return $null }
}

$chain = [System.Collections.Generic.List[object]]::new()
$chain.Add([PSCustomObject]@{ Label = 'GPU'; Id = $gpu.InstanceId; DevObj = (Get-PdoName $gpu.InstanceId) })

try {
    $pp = Get-PnpDeviceProperty -InstanceId $gpu.InstanceId `
        -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop
    if ($pp.Data -match '^PCI\\') {
        $chain.Add([PSCustomObject]@{ Label = 'PCI Bridge'; Id = $pp.Data; DevObj = (Get-PdoName $pp.Data) })
        $gpp = Get-PnpDeviceProperty -InstanceId $pp.Data `
            -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop
        if ($gpp.Data -match '^PCI\\') {
            $chain.Add([PSCustomObject]@{ Label = 'Root Complex'; Id = $gpp.Data; DevObj = (Get-PdoName $gpp.Data) })
        } else {
            # Normal on AMD: Root Complex is exposed as ACPI\PNP0A08 in the PnP tree, not PCI.
            # GPU + PCI Bridge is sufficient for IRQ pinning on these platforms.
            Write-Host "    [NOTE] Root Complex is ACPI ($($gpp.Data)) -- normal on AMD." -ForegroundColor DarkGray
            Write-Host "           Applying GPU + PCI Bridge only (sufficient for IRQ pinning)." -ForegroundColor DarkGray
        }
    } else {
        Write-Host "    [WARN] Bridge is not PCI ($($pp.Data)). Applying GPU only." -ForegroundColor Yellow
    }
} catch {
    Write-Host "    [WARN] Could not walk PCI chain: $_. Applying GPU only." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "    PCI chain ($($chain.Count) device(s) to pin):"
for ($i = 0; $i -lt $chain.Count; $i++) {
    $devObj = if ($chain[$i].DevObj) { "  DevObj: $($chain[$i].DevObj)" } else { '' }
    Write-Host ("      [{0}] {1,-14} : {2}{3}" -f ($i + 1), $chain[$i].Label, $chain[$i].Id, $devObj)
}
Write-Host ""

# ── C. Write registry ─────────────────────────────────────────────────────────
$ok = 0
for ($i = 0; $i -lt $chain.Count; $i++) {
    $dev        = $chain[$i]
    $policyPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.Id)\" +
                  "Device Parameters\Interrupt Management\Affinity Policy"
    try {
        if (-not (Test-Path $policyPath)) {
            New-Item -Path $policyPath -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -Path $policyPath -Name 'DevicePolicy' `
            -Value 4 -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $policyPath -Name 'AssignmentSetOverride' `
            -Value $BITMASK -Type Binary -Force -ErrorAction Stop
        Write-Host ("    [OK]  [{0}] {1,-14} -> core {2}  DevicePolicy=4  AssignmentSetOverride={3}" -f `
            ($i + 1), $dev.Label, $TARGET_CORE, $BITMASK_HEX) -ForegroundColor Green
        $ok++
    } catch {
        Write-Host ("    [ERROR] [{0}] {1,-14} : {2}" -f ($i + 1), $dev.Label, $_) -ForegroundColor Red
    }
}

# ── D. Summary ────────────────────────────────────────────────────────────────
Write-Host ""
if ($ok -eq $chain.Count) {
    Write-Host "    $ok/$($chain.Count) devices pinned to core $TARGET_CORE." -ForegroundColor Green
} else {
    Write-Host "    $ok/$($chain.Count) devices pinned to core $TARGET_CORE (check errors above)." -ForegroundColor Yellow
}
Write-Host "    Reboot required for the setting to take effect." -ForegroundColor Yellow
Write-Host "    NVIDIA: re-run set_affinity.bat after each driver update." -ForegroundColor DarkGray
Write-Host ""
if (-not $SkipReboot) {
    $r = Read-Host "  Reboot now? (Y/N) [default: Y]"
    if ($r -eq '' -or $r -ieq 'Y') {
        Restart-Computer -Force
    }
}
