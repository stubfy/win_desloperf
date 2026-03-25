# set_affinity.ps1 - Pin interrupt chains to dedicated CPU cores
#
# WHAT IT DOES
#   Pins hardware interrupts from the GPU (and optionally a USB mouse) to
#   dedicated CPU cores by writing IrqPolicySpecifiedProcessors (DevicePolicy=4)
#   to the registry for each device in the PCI chain:
#     GPU chain  : GPU -> PCI Bridge -> PCI Root Complex
#     Mouse chain: USB Controller (xHCI) -> PCI Bridge -> PCI Root Complex
#
# WHY
#   Windows distributes IRQs across all logical cores by default. GPU DPCs
#   can land on the same core running the render thread, causing latency spikes.
#   Pinning the entire interrupt chain to a dedicated core physically separates
#   GPU IRQ processing from game threads. The same logic applies to mouse input:
#   isolating the USB controller's interrupts reduces input jitter.
#
# MODES
#   Auto  : reads backup/affinity_config.json and applies saved core assignments
#           without prompting (used on re-runs and by run_all).
#   Interactive : detects GPU + USB mice, asks the user to choose cores,
#                 and optionally saves the config for future auto re-runs.
#
# HOW
#   For each device in the chain, writes:
#     HKLM\SYSTEM\CurrentControlSet\Enum\<DeviceInstanceId>\
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

param(
    [switch]$SkipReboot,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'affinity_helpers.ps1')

$BACKUP_DIR = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'backup'
if (-not $ConfigPath) { $ConfigPath = Join-Path $BACKUP_DIR 'affinity_config.json' }
$coreCount = [Environment]::ProcessorCount

# ── Helper: build a human-readable mouse label ────────────────────────────────
function Get-MouseDisplayName {
    param($Mouse)
    # Extract VID/PID from the HID InstanceId (e.g. HID\VID_046D&PID_C548&...)
    $vidPid = ''
    if ($Mouse.InstanceId -match 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') {
        $vidPid = "VID:$($Matches[1].ToUpper()) PID:$($Matches[2].ToUpper())"
    }
    # Walk up one level to get the parent USB device (dongle / composite device).
    # DEVPKEY_Device_BusReportedDeviceDesc = raw USB product string from firmware
    # (e.g. "Pulsar 4K Wireless Receiver") -- more precise than FriendlyName which
    # Windows always sets to the generic "USB Input Device" for composite devices.
    $parentLabel = ''
    try {
        $parentId = (Get-PnpDeviceProperty -InstanceId $Mouse.InstanceId `
            -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop).Data
        $busDesc = (Get-PnpDeviceProperty -InstanceId $parentId `
            -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc' -ErrorAction SilentlyContinue).Data
        if (-not [string]::IsNullOrWhiteSpace($busDesc)) {
            $parentLabel = $busDesc
        } else {
            # Fallback: FriendlyName (better than nothing, though often generic)
            $parentDev = Get-PnpDevice -InstanceId $parentId -ErrorAction SilentlyContinue
            if ($parentDev -and
                -not [string]::IsNullOrWhiteSpace($parentDev.FriendlyName) -and
                $parentDev.FriendlyName -ne $Mouse.FriendlyName) {
                $parentLabel = $parentDev.FriendlyName
            }
        }
    } catch {}

    $display = $Mouse.FriendlyName
    if ($vidPid)      { $display += " ($vidPid)" }
    if ($parentLabel) { $display += " via $parentLabel" }
    return $display
}

# ── A. Pre-cleanup: reset previously pinned mouse chain ──────────────────────
# Runs unconditionally before any apply. Ensures stale affinity from old USB
# ports is removed when the mouse is moved to a different controller.
$rawConfig = Read-AffinityConfig -ConfigPath $ConfigPath
if ($rawConfig) {
    $hadMouseCleanup = $false
    foreach ($g in $rawConfig.groups | Where-Object { $_.type -eq 'mouse' }) {
        $oldChain = Get-PciChainFromDevice -InstanceId $g.instanceId -StartLabel 'USB Controller' -Quiet
        foreach ($dev in $oldChain) {
            $policyPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.Id)\" +
                          "Device Parameters\Interrupt Management\Affinity Policy"
            if (Test-Path $policyPath) {
                Remove-Item -Path $policyPath -Recurse -Force -ErrorAction SilentlyContinue
                if (-not $hadMouseCleanup) {
                    Write-Host "    [RESET] Clearing previous mouse affinity ($($g.label))..." -ForegroundColor DarkGray
                    $hadMouseCleanup = $true
                }
                Write-Host "    [RESET]   $($dev.Label) -> cleared" -ForegroundColor DarkGray
            }
        }
    }
    if ($hadMouseCleanup) { Write-Host "" }
}

# ── B. Validate config for auto-apply ─────────────────────────────────────────
$config = $rawConfig
if ($config) {
    $configValid = $true
    foreach ($g in $config.groups) {
        $dev = Get-PnpDevice -InstanceId $g.instanceId -ErrorAction SilentlyContinue
        if (-not $dev) {
            Write-Host "    [WARN] Saved device not found: $($g.label) ($($g.instanceId))" -ForegroundColor Yellow
            $configValid = $false
        }
    }
    if (-not $configValid) {
        Write-Host "    Config has stale devices. Switching to interactive mode." -ForegroundColor Yellow
        $config = $null
    }
}

if ($config) {
    # ── Auto-apply mode ────────────────────────────────────────────────────────
    Write-Host "    Config  : $ConfigPath"
    Write-Host ""

    foreach ($g in $config.groups) {
        $startLabel = if ($g.type -eq 'gpu') { 'GPU' } else { 'USB Controller' }
        Write-Host "  -- $($g.type.ToUpper()) interrupt affinity --" -ForegroundColor Cyan
        Write-Host "    Device  : $($g.label)"
        Write-Host "    Core    : $($g.core)"

        $chain = Get-PciChainFromDevice -InstanceId $g.instanceId -StartLabel $startLabel
        if ($chain.Count -eq 0) {
            Write-Host "    [WARN] Could not walk PCI chain. Skipping." -ForegroundColor Yellow
            Write-Host ""
            continue
        }

        Write-Host "    PCI chain ($($chain.Count) device(s)):"
        for ($i = 0; $i -lt $chain.Count; $i++) {
            Write-Host ("      [{0}] {1,-20} : {2}" -f ($i + 1), $chain[$i].Label, $chain[$i].Id)
        }
        Write-Host ""
        $ok = Write-AffinityPolicy -Chain $chain -Core $g.core
        $color = if ($ok -eq $chain.Count) { 'Green' } else { 'Yellow' }
        Write-Host "    $ok/$($chain.Count) devices pinned to core $($g.core)." -ForegroundColor $color
        Write-Host ""
    }

} else {
    # ── Interactive mode ───────────────────────────────────────────────────────
    Write-Host "    Available CPU cores: 0-$($coreCount - 1) ($coreCount logical processors)"
    Write-Host ""

    $groups  = @()
    $gpuCore = 2  # track for mouse default suggestion
    $gpuChain = $null

    # GPU section ---------------------------------------------------------------
    Write-Host "  -- GPU interrupt affinity --" -ForegroundColor Cyan
    $gpu = Find-DiscreteGpu

    if (-not $gpu) {
        Write-Host "    [ERROR] No PCI display device found. Is the GPU driver installed?" -ForegroundColor Red
    } else {
        Write-Host "    Detected : $($gpu.FriendlyName)"

        $gpuCoreInput = Read-Host "    Pin GPU chain to core [0-$($coreCount - 1)] (default: 2)"
        $gpuCore = if ($gpuCoreInput -match '^\d+$' -and [int]$gpuCoreInput -lt $coreCount) {
            [int]$gpuCoreInput
        } else { 2 }

        $gpuChain = Get-PciChainFromDevice -InstanceId $gpu.InstanceId -StartLabel 'GPU'
        if ($gpuChain.Count -eq 0) {
            Write-Host "    [WARN] Could not walk PCI chain for GPU." -ForegroundColor Yellow
        } else {
            Write-Host ""
            Write-Host "    PCI chain ($($gpuChain.Count) device(s)):"
            for ($i = 0; $i -lt $gpuChain.Count; $i++) {
                $devObj = if ($gpuChain[$i].DevObj) { "  DevObj: $($gpuChain[$i].DevObj)" } else { '' }
                Write-Host ("      [{0}] {1,-14} : {2}{3}" -f ($i + 1), $gpuChain[$i].Label, $gpuChain[$i].Id, $devObj)
            }
            Write-Host ""
            $ok = Write-AffinityPolicy -Chain $gpuChain -Core $gpuCore
            $color = if ($ok -eq $gpuChain.Count) { 'Green' } else { 'Yellow' }
            Write-Host "    $ok/$($gpuChain.Count) devices pinned to core $gpuCore." -ForegroundColor $color

            $groups += @{
                type       = 'gpu'
                core       = $gpuCore
                label      = $gpu.FriendlyName
                instanceId = $gpu.InstanceId
            }
        }
    }

    Write-Host ""

    # Mouse section -------------------------------------------------------------
    Write-Host "  -- Mouse interrupt affinity --" -ForegroundColor Cyan
    $usbMice = Find-UsbMice

    if ($usbMice.Count -eq 0) {
        Write-Host "    No USB mouse detected. Skipping." -ForegroundColor Gray
    } else {
        Write-Host "    Detected USB mice:"
        $mouseDisplayNames = @()
        for ($i = 0; $i -lt $usbMice.Count; $i++) {
            $displayName = Get-MouseDisplayName -Mouse $usbMice[$i]
            $mouseDisplayNames += $displayName
            Write-Host ("      [{0}] {1}" -f ($i + 1), $displayName)
        }
        Write-Host "      [S] Skip"

        $mouseChoice = Read-Host "    Select [1-$($usbMice.Count)/S] (default: 1)"
        if ($mouseChoice -ieq 'S') {
            Write-Host "    Mouse affinity skipped." -ForegroundColor Gray
        } else {
            $mouseIdx = if ($mouseChoice -match '^\d+$' -and [int]$mouseChoice -ge 1 -and [int]$mouseChoice -le $usbMice.Count) {
                [int]$mouseChoice - 1
            } else { 0 }

            $selectedMouse       = $usbMice[$mouseIdx]
            $selectedDisplayName = $mouseDisplayNames[$mouseIdx]
            Write-Host "    Selected : $selectedDisplayName"

            # Suggest a default core different from GPU core
            $defaultMouseCore = if ($gpuCore -ne 4) { 4 } else { 6 }
            $mouseCoreInput = Read-Host "    Pin mouse chain to core [0-$($coreCount - 1)] (default: $defaultMouseCore)"
            $mouseCore = if ($mouseCoreInput -match '^\d+$' -and [int]$mouseCoreInput -lt $coreCount) {
                [int]$mouseCoreInput
            } else { $defaultMouseCore }

            $mouseChain = Get-PciChainFromDevice -InstanceId $selectedMouse.InstanceId -StartLabel 'USB Controller'
            if ($mouseChain.Count -eq 0) {
                Write-Host "    [WARN] Could not walk PCI chain for mouse." -ForegroundColor Yellow
            } else {
                # Warn if GPU and mouse chains overlap (shared PCI bridge or root port)
                if ($gpuChain -and $gpuChain.Count -gt 0) {
                    $gpuIds  = @($gpuChain  | ForEach-Object { $_.Id })
                    $mIds    = @($mouseChain | ForEach-Object { $_.Id })
                    $overlap = $gpuIds | Where-Object { $mIds -contains $_ }
                    if ($overlap) {
                        Write-Host "    [NOTE] Mouse shares PCI device(s) with GPU chain." -ForegroundColor Yellow
                        Write-Host "           Shared device(s) will use the mouse core ($mouseCore)." -ForegroundColor DarkGray
                    }
                }

                Write-Host ""
                Write-Host "    PCI chain ($($mouseChain.Count) device(s)):"
                for ($i = 0; $i -lt $mouseChain.Count; $i++) {
                    $devObj = if ($mouseChain[$i].DevObj) { "  DevObj: $($mouseChain[$i].DevObj)" } else { '' }
                    Write-Host ("      [{0}] {1,-20} : {2}{3}" -f ($i + 1), $mouseChain[$i].Label, $mouseChain[$i].Id, $devObj)
                }
                Write-Host ""
                $ok = Write-AffinityPolicy -Chain $mouseChain -Core $mouseCore
                $color = if ($ok -eq $mouseChain.Count) { 'Green' } else { 'Yellow' }
                Write-Host "    $ok/$($mouseChain.Count) devices pinned to core $mouseCore." -ForegroundColor $color

                $groups += @{
                    type       = 'mouse'
                    core       = $mouseCore
                    label      = $selectedDisplayName
                    instanceId = $selectedMouse.InstanceId
                }
            }
        }
    }

    # Save config ---------------------------------------------------------------
    Write-Host ""
    if ($groups.Count -gt 0) {
        $saveChoice = Read-Host "  Save config for auto re-application? (Y/N) [default: Y]"
        if ($saveChoice -eq '' -or $saveChoice -ieq 'Y') {
            Save-AffinityConfig -ConfigPath $ConfigPath -Groups $groups
            Write-Host "    Config saved -> $ConfigPath" -ForegroundColor Green
        }
    }
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "    Reboot required for the setting to take effect." -ForegroundColor Yellow
Write-Host "    NVIDIA: re-run set_affinity.bat after each driver update." -ForegroundColor DarkGray
Write-Host ""
if (-not $SkipReboot) {
    $r = Read-Host "  Reboot now? (Y/N) [default: Y]"
    if ($r -eq '' -or $r -ieq 'Y') {
        Restart-Computer -Force
    }
}
