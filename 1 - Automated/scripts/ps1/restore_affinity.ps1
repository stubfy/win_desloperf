# restore_affinity.ps1 - Restore interrupt affinity to Windows default
#
# Reads backup\affinity_state.json (captured by backup.ps1 before tweaks ran).
# For each device recorded in the backup:
#   - If backup had Existed=true : restores original DevicePolicy + AssignmentSetOverride.
#   - If backup had Existed=false: deletes the Affinity Policy subkey (Windows default).
#   - If no backup file found    : deletes any Affinity Policy key found (safest fallback).
#
# Covers all device chains recorded in the backup: GPU, USB mouse, and any future groups.

$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'affinity_helpers.ps1')

$BACKUP_DIR = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'backup'
$STATE_FILE = Join-Path $BACKUP_DIR 'affinity_state.json'

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
    Write-Host "    No affinity backup found. Will delete any Affinity Policy keys found." -ForegroundColor Gray
}

# ── Restore ───────────────────────────────────────────────────────────────────
if (-not $savedState) {
    # No backup: discover and clean up GPU + mouse chains (best-effort)
    Write-Host "    Falling back to live device detection." -ForegroundColor Gray
    $chains = @()

    $gpu = Find-DiscreteGpu
    if ($gpu) {
        $chain = Get-PciChainFromDevice -InstanceId $gpu.InstanceId -StartLabel 'GPU' -Quiet
        if ($chain.Count -gt 0) { $chains += , $chain }
    }

    $config = Read-AffinityConfig -ConfigPath (Join-Path $BACKUP_DIR 'affinity_config.json')
    if ($config) {
        foreach ($g in $config.groups | Where-Object { $_.type -eq 'mouse' }) {
            $chain = Get-PciChainFromDevice -InstanceId $g.instanceId -StartLabel 'USB Controller' -Quiet
            if ($chain.Count -gt 0) { $chains += , $chain }
        }
    }

    Write-Host ""
    foreach ($chain in $chains) {
        foreach ($dev in $chain) {
            $policyPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.Id)\" +
                          "Device Parameters\Interrupt Management\Affinity Policy"
            try {
                if (Test-Path $policyPath) {
                    Remove-Item -Path $policyPath -Recurse -Force -ErrorAction Stop
                    Write-Host "    [RESTORED] $($dev.Label) ($($dev.Id)) -> Affinity Policy deleted (Windows default)" -ForegroundColor Green
                } else {
                    Write-Host "    [SKIPPED]  $($dev.Label) ($($dev.Id)) -> Affinity Policy not present" -ForegroundColor Gray
                }
            } catch {
                Write-Host "    [ERROR] $($dev.Label): $_" -ForegroundColor Red
            }
        }
    }
} else {
    # Restore from backup — generic: handles GPU, mouse, and any future device types
    Write-Host ""
    foreach ($prop in $savedState.PSObject.Properties) {
        $devId      = $prop.Name
        $devState   = $prop.Value
        $policyPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$devId\" +
                      "Device Parameters\Interrupt Management\Affinity Policy"

        try {
            if ($devState.Existed -eq $true) {
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
                Write-Host "    [RESTORED] $devId -> original affinity policy" -ForegroundColor Green
            } else {
                # Device had no affinity policy before — delete it
                if (Test-Path $policyPath) {
                    Remove-Item -Path $policyPath -Recurse -Force -ErrorAction Stop
                    Write-Host "    [RESTORED] $devId -> Affinity Policy deleted (Windows default)" -ForegroundColor Green
                } else {
                    Write-Host "    [SKIPPED]  $devId -> Affinity Policy not present" -ForegroundColor Gray
                }
            }
        } catch {
            Write-Host "    [ERROR] $devId : $_" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "    Restore complete. Reboot required." -ForegroundColor Yellow
