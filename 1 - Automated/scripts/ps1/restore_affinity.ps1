# restore_affinity.ps1 - Restore GPU interrupt affinity to Windows default
#
# Detects the same GPU -> PCI Bridge -> Root Complex chain as set_affinity.ps1.
# For each device:
#   - If backup\affinity_state.json exists and device had Existed=true:
#     Restores the original DevicePolicy and AssignmentSetOverride values.
#   - If backup\affinity_state.json exists and device had Existed=false:
#     Deletes the Affinity Policy subkey (returns to Windows default).
#   - If no backup found:
#     Deletes the Affinity Policy subkey (safest default).

$ErrorActionPreference = 'Continue'

$PACK_ROOT  = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$BACKUP_DIR = Join-Path $PACK_ROOT "1 - Automated\backup"
$STATE_FILE = Join-Path $BACKUP_DIR "affinity_state.json"

# ── Load saved state ──────────────────────────────────────────────────────────
$savedState = $null
if (Test-Path $STATE_FILE) {
    try {
        $savedState = Get-Content $STATE_FILE -Encoding UTF8 | ConvertFrom-Json
        Write-Host "    Saved state : $STATE_FILE"
    } catch {
        Write-Host "    [WARN] Could not read affinity_state.json: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "    No affinity backup found. Affinity Policy keys will be deleted." -ForegroundColor Gray
}

# ── GPU detection (same logic as set_affinity.ps1) ───────────────────────────
$allGpus = Get-PnpDevice -Class Display -Status OK -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match '^PCI\\' }

if (-not $allGpus) {
    Write-Host "    [ERROR] No PCI display device found." -ForegroundColor Red
    return
}

$igpuPattern = 'Intel.*(UHD|Iris|HD Graphics)|Microsoft Basic Display'
$dGpus = $allGpus | Where-Object { $_.FriendlyName -notmatch $igpuPattern }
if (-not $dGpus) { $dGpus = $allGpus }

$gpu = $dGpus | Where-Object { $_.FriendlyName -match 'NVIDIA' } | Select-Object -First 1
if (-not $gpu) { $gpu = $dGpus | Where-Object { $_.FriendlyName -match 'AMD|Radeon' } | Select-Object -First 1 }
if (-not $gpu) { $gpu = $dGpus | Select-Object -First 1 }

Write-Host "    GPU     : $($gpu.FriendlyName)"

$chain = [System.Collections.Generic.List[object]]::new()
$chain.Add([PSCustomObject]@{ Label = 'GPU'; Id = $gpu.InstanceId })

try {
    $pp = Get-PnpDeviceProperty -InstanceId $gpu.InstanceId `
        -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop
    if ($pp.Data -match '^PCI\\') {
        $chain.Add([PSCustomObject]@{ Label = 'PCI Bridge'; Id = $pp.Data })
        $gpp = Get-PnpDeviceProperty -InstanceId $pp.Data `
            -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop
        if ($gpp.Data -match '^PCI\\') {
            $chain.Add([PSCustomObject]@{ Label = 'Root Complex'; Id = $gpp.Data })
        }
    }
} catch {}

Write-Host ""

# ── Restore each device ───────────────────────────────────────────────────────
foreach ($dev in $chain) {
    $policyPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.Id)\" +
                  "Device Parameters\Interrupt Management\Affinity Policy"

    $devState = $null
    if ($savedState) {
        $devState = $savedState.PSObject.Properties |
            Where-Object { $_.Name -eq $dev.Id } |
            Select-Object -ExpandProperty Value
    }

    try {
        if ($devState -and $devState.Existed -eq $true) {
            # Restore original values
            if (-not (Test-Path $policyPath)) {
                New-Item -Path $policyPath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $policyPath -Name 'DevicePolicy' `
                -Value ([int]$devState.DevicePolicy) -Type DWord -Force -ErrorAction Stop
            if ($null -ne $devState.AssignmentSetOverride) {
                $origBytes = [byte[]]($devState.AssignmentSetOverride | ForEach-Object { [byte]$_ })
                Set-ItemProperty -Path $policyPath -Name 'AssignmentSetOverride' `
                    -Value $origBytes -Type Binary -Force -ErrorAction Stop
            }
            Write-Host "    [RESTORED] $($dev.Label) ($($dev.Id)) -> original affinity policy" -ForegroundColor Green
        } else {
            # Delete Affinity Policy subkey -> Windows assigns interrupts automatically
            if (Test-Path $policyPath) {
                Remove-Item -Path $policyPath -Recurse -Force -ErrorAction Stop
                Write-Host "    [RESTORED] $($dev.Label) ($($dev.Id)) -> Affinity Policy deleted (Windows default)" -ForegroundColor Green
            } else {
                Write-Host "    [SKIPPED]  $($dev.Label) ($($dev.Id)) -> Affinity Policy not present" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "    [ERROR] $($dev.Label): $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "    Restore complete. Reboot required." -ForegroundColor Yellow
