# performance.ps1 - System performance: power plan, BCD, USB selective suspend
# Combines: power.ps1, bcdedit.ps1, usb.ps1
#
# Power plan strategy:
#   Bitsum Highest Performance (GUID: 5a39c962-8fb2-4c72-8843-936f1d325503) is
#   imported from the bundled .pow file if not already present. It sets CPU min/max
#   to 100%, disables USB selective suspend, PCI Express ASPM, and hard disk timeout.
#   Using a fixed GUID avoids the duplicate-plan accumulation caused by
#   -duplicatescheme (which generates a new random GUID on every run).
#
#   Fallback: if the import fails, duplicates the built-in Ultimate Performance plan
#   (GUID ending in ...eb61) as a last resort.
#
#   Cleanup: after activating the plan, any duplicate "Ultimate Performance" plans
#   (created by previous runs) are deleted. Built-in plans (Balanced, High Performance,
#   Power Saver, Ultimate Performance hidden source) are never touched.
#
# PPM setting - Processor Performance Increase Policy (Bitsum "Rocket"):
#   Subgroup: Processor power management (54533251-82be-4824-96c1-47b60b740d00)
#   Setting:  Processor performance increase policy (4d2b0152-7d5c-498b-88e2-34345392a2c5)
#   Value 5000 = "Rocket" (immediate maximum frequency on any load increase).
#   This controls how aggressively the PPM (Processor Power Manager) scales up
#   CPU frequency when it detects a demand spike. The default "Ideal" policy ramps
#   up gradually; "Rocket" jumps to maximum frequency immediately, eliminating the
#   latency of the ramp-up period during burst workloads (frame start, physics step).
#   Applied on top of the Bitsum plan (it does not include Rocket by default).
#
# BCD:
#   disabledynamictick: Forces a constant TSC-based tick at the full requested
#     timer resolution, reducing jitter in frame-to-frame timing.
#   bootmenupolicy legacy: Classic text-mode boot menu rendered by the bootloader.
#     WARNING: Graphical Recovery Environment not available via boot menu afterwards.
#     Recovery: Settings > Recovery > Advanced startup, or F8/Shift+F8 during boot.
#
# USB selective suspend:
#   Keeps USB ports powered at all times to avoid input device wake-up latency.
#   Reuses $planGuid obtained in the power section (no redundant powercfg query).
#
# Rollback: restore\performance.ps1

# === SECTION: Bitsum Highest Performance power plan ===

$BITSUM_GUID    = '5a39c962-8fb2-4c72-8843-936f1d325503'
$UP_SOURCE_GUID = 'e9a42b02-d5df-448d-aa00-03f14749eb61'  # hidden built-in Ultimate Performance
# Built-in plans that must never be deleted (fixed Windows GUIDs)
$BUILTIN_GUIDS  = @(
    '381b4222-f694-41f0-9685-ff5bb260df2e'  # Balanced
    '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'  # High Performance
    'a1841308-3541-4fab-bc81-f71556f20b4a'  # Power Saver
    'e9a42b02-d5df-448d-aa00-03f14749eb61'  # Ultimate Performance (hidden source)
    $BITSUM_GUID                             # Bitsum Highest Performance (keep)
)

$planGuid = $null

# Check if Bitsum plan already exists
$listOutput = powercfg -list 2>&1 | Out-String
if ($listOutput -match $BITSUM_GUID) {
    $planGuid = $BITSUM_GUID
    Write-Host "    Bitsum Highest Performance plan already present: $planGuid"
} else {
    # Import from bundled .pow file
    $powFile = Join-Path $ROOT 'tools\bitsum_highest_performance.pow'
    if (Test-Path $powFile) {
        powercfg -import $powFile $BITSUM_GUID 2>&1 | Out-Null
        # Verify import succeeded
        $listOutput = powercfg -list 2>&1 | Out-String
        if ($listOutput -match $BITSUM_GUID) {
            $planGuid = $BITSUM_GUID
            Write-Host "    Bitsum Highest Performance plan imported: $planGuid"
        } else {
            Write-Host "    WARNING: Bitsum import failed, falling back to Ultimate Performance duplicate." -ForegroundColor Yellow
        }
    } else {
        Write-Host "    WARNING: bitsum_highest_performance.pow not found at $powFile, falling back." -ForegroundColor Yellow
    }

    # Fallback: duplicate built-in Ultimate Performance plan
    if (-not $planGuid) {
        $dupOutput = powercfg -duplicatescheme $UP_SOURCE_GUID 2>&1 | Out-String
        $planGuid  = [regex]::Match($dupOutput, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value
        if ($planGuid) {
            Write-Host "    Fallback: Ultimate Performance duplicate created: $planGuid"
        } else {
            # Last resort: apply to current active plan
            Write-Host "    WARNING: unable to create any performance plan." -ForegroundColor Yellow
            $activeLine = powercfg -getactivescheme 2>&1 | Out-String
            $planGuid   = [regex]::Match($activeLine, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value
        }
    }
}

if ($planGuid) {
    # Activate the plan
    powercfg -setactive $planGuid 2>&1 | Out-Null
    Write-Host "    Active plan: $planGuid"

    # Processor Performance Increase Policy = 5000 (Rocket: immediate max frequency)
    # Subgroup: Processor power management | Setting: Increase policy
    # Applied on top of the Bitsum plan (Bitsum does not bundle this setting)
    powercfg /setacvalueindex $planGuid `
        54533251-82be-4824-96c1-47b60b740d00 `
        4d2b0152-7d5c-498b-88e2-34345392a2c5 `
        5000 2>&1 | Out-Null
    powercfg /setactive $planGuid 2>&1 | Out-Null
    Write-Host "    CPU frequency scaling policy: Rocket (5000)"

    # Disable sleep on AC and battery (standby-timeout 0 = never sleep)
    powercfg /change standby-timeout-ac 0 2>&1 | Out-Null
    powercfg /change standby-timeout-dc 0 2>&1 | Out-Null
    Write-Host "    Sleep disabled on AC and battery"

    # Disable hibernation: removes hiberfil.sys and prevents hybrid sleep.
    # Also set via registry (HibernateEnabled=0 in tweaks_consolidated.reg).
    powercfg -h off 2>&1 | Out-Null
    Write-Host "    Hibernation disabled (hiberfil.sys removed)"

    # Cleanup: delete all "Ultimate Performance" duplicate plans left by previous runs.
    # Safe guard: never delete built-in plans ($BUILTIN_GUIDS) or the current active plan.
    $cleanupList = powercfg -list 2>&1 | Out-String
    $cleanupMatches = [regex]::Matches($cleanupList, '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s+\(Ultimate Performance\)')
    foreach ($m in $cleanupMatches) {
        $g = $m.Groups[1].Value
        if ($BUILTIN_GUIDS -notcontains $g) {
            powercfg -delete $g 2>&1 | Out-Null
            Write-Host "    Deleted duplicate Ultimate Performance plan: $g"
        }
    }
} else {
    Write-Host "    ERROR: unable to determine active plan GUID." -ForegroundColor Red
}

# === SECTION: Boot configuration (bcdedit) ===

# Force constant TSC tick (reduces timer latency jitter in games)
bcdedit /set disabledynamictick yes 2>&1 | Out-Null
Write-Host "    disabledynamictick = yes"

# Classic boot menu (faster to display; loses graphical recovery entry)
bcdedit /set bootmenupolicy legacy 2>&1 | Out-Null
Write-Host "    bootmenupolicy = legacy"

# === SECTION: USB selective suspend ===
# Reuses $planGuid from the power section above (no redundant powercfg query).
# Keeps USB ports powered at all times to avoid input device wake-up latency.
# Subgroup: 2a737441-1930-4402-8d77-b2bebba308a3 (USB settings)
# Setting:  48e6b7a6-50f5-4782-a5d4-53bb8f07e226 (USB selective suspend)
# Value: 0 = Disabled

if (-not $planGuid) {
    Write-Host "    ERROR: unable to determine active plan GUID for USB suspend." -ForegroundColor Red
} else {
    powercfg /setacvalueindex $planGuid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    powercfg /setdcvalueindex $planGuid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>&1 | Out-Null
    powercfg /setactive $planGuid 2>&1 | Out-Null
    Write-Host "    USB selective suspend disabled on plan: $planGuid"
}

# === SECTION: Memory Compression ===
# Windows 11 compresses memory pages to reduce physical RAM usage. On gaming PCs
# with 16 GB+ RAM this trades CPU cycles for memory savings that are unnecessary,
# adding measurable overhead during frame-sensitive workloads.

$mcBefore = (Get-MMAgent).MemoryCompression
Write-Host "    Memory Compression before: $mcBefore"

if ($mcBefore) {
    Disable-MMAgent -MemoryCompression
    $mcAfter = (Get-MMAgent).MemoryCompression
    Write-Host "    Memory Compression after : $mcAfter"
} else {
    Write-Host "    Memory Compression already disabled, skipping."
}
