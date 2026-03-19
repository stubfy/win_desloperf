# snapshot.ps1 - Snapshot system state before tweaks
# Saved to backup/snapshot_latest.json, used by show_diff.ps1
#
# Captures a point-in-time baseline of registry values, service startup types and
# BCD boot settings BEFORE any tweaks are applied. show_diff.ps1 reads this
# snapshot after all tweaks have run and computes a diff showing:
#   - Which values were already at the desired state (already OK)
#   - Which values were changed by the pack (applied)
#   - Which values failed to apply (failed)
#
# Registry parsing: the script reads tweaks_consolidated.reg, privacy_tweaks.reg
# and personal_settings.reg
# line-by-line and extracts every DWORD and string value. For each value it
# records the BEFORE (current system value) and DESIRED (value the pack will set),
# including the GameDVR state keys used to keep Game Bar capture disabled.
# Hex continuation lines (lines ending in \) are joined before parsing.
# Keys that delete values (Name=-) and hex binary values are skipped since they
# cannot be reliably compared numerically.
#
# Service snapshot: reads the startup type of every service in the catalog from
# the HKLM\...\Services\<name> registry key directly (not via Get-Service API)
# so that DelayedAutoStart is correctly detected.
#
# BCD snapshot: runs bcdedit /enum {current} and extracts disabledynamictick
# and bootmenupolicy values for the diff.
#
# This script is a development/diagnostic tool. It has no effect on the tweaks
# themselves and can be re-run at any time to refresh the snapshot.

$ROOT       = Split-Path (Split-Path $PSScriptRoot)
$BACKUP_DIR = Join-Path $ROOT "backup"
$REG_FILES  = @(
    (Join-Path $PSScriptRoot "tweaks_consolidated.reg")
    (Join-Path $PSScriptRoot "privacy_tweaks.reg")
    (Join-Path $PSScriptRoot "personal_settings.reg")
)
$REQUIRED_TRACKED_REGISTRY_VALUES = @(
    'HKCU:\System\GameConfigStore|GameDVR_Enabled'
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR|GameDVR_Enabled'
)

# Registry values set by PowerShell scripts (not .reg files) that should be
# tracked for regression detection post-Windows-Update. Each entry defines the
# path, value name, expected desired value, and type (for display in show_diff).
$ADDITIONAL_TRACKED_REG_VALUES = @(
    # privacy.ps1 - Recall / Click to Do
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI';                               Name='DisableAIDataAnalysis'; Desired=1;   Type='DWORD' }
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI';                               Name='AllowRecallEnablement'; Desired=0;   Type='DWORD' }
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI';                               Name='DisableClickToDo';      Desired=1;   Type='DWORD' }
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI';                               Name='DisableSettingsAgent'; Desired=1;   Type='DWORD' }
    @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ClickToDo';        Name='DisableClickToDo';      Desired=1;   Type='DWORD' }
    # privacy.ps1 - Paint AI features
    @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name='DisableCocreator';        Desired=1; Type='DWORD' }
    @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name='DisableGenerativeFill';   Desired=1; Type='DWORD' }
    @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name='DisableImageCreator';     Desired=1; Type='DWORD' }
    @{ Path='HKCU:\Software\Microsoft\MSPaint\Settings';                     Name='DisableCocreator';        Desired=1; Type='DWORD' }
    @{ Path='HKCU:\Software\Microsoft\MSPaint\Settings';                     Name='DisableGenerativeFill';   Desired=1; Type='DWORD' }
    @{ Path='HKCU:\Software\Microsoft\MSPaint\Settings';                     Name='DisableImageCreator';     Desired=1; Type='DWORD' }
    @{ Path='HKCU:\Software\Microsoft\MSPaint\Settings';                     Name='DisableGenerativeErase';  Desired=1; Type='DWORD' }
    @{ Path='HKCU:\Software\Microsoft\MSPaint\Settings';                     Name='DisableRemoveBackground'; Desired=1; Type='DWORD' }
    # privacy.ps1 - Notepad AI features
    @{ Path='HKLM:\SOFTWARE\Policies\WindowsNotepad';      Name='DisableAIFeatures'; Desired=1; Type='DWORD' }
    @{ Path='HKCU:\Software\Microsoft\Notepad\Settings';  Name='DisableAIFeatures'; Desired=1; Type='DWORD' }
    # set_windows_update.ps1 Profile 2/3 - anti-forced-reboot
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name='NoAutoRebootWithLoggedOnUsers'; Desired=1; Type='DWORD' }
)
$SNAP_FILE  = Join-Path $BACKUP_DIR "snapshot_latest.json"

if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
}

$serviceCatalog = & (Join-Path $PSScriptRoot 'services.ps1') -ExportCatalogOnly

function ConvertTo-PSPath([string]$p) {
    return $p `
        -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM:\' `
        -replace '^HKEY_CURRENT_USER\\',  'HKCU:\' `
        -replace '^HKEY_CLASSES_ROOT\\',  'HKCR:\' `
        -replace '^HKEY_USERS\\',         'HKU:\'
}

function Get-ExactServiceStartupType {
    param([Parameter(Mandatory)][string]$Name)

    $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    try {
        $props = Get-ItemProperty -Path $serviceKey -ErrorAction Stop
    } catch {
        return $null
    }

    $delayedAutoStart = ($props.PSObject.Properties.Name -contains 'DelayedAutoStart' -and $props.DelayedAutoStart -eq 1)
    switch ([int]$props.Start) {
        2 { if ($delayedAutoStart) { return 'AutomaticDelayedStart' } else { return 'Automatic' } }
        3 { return 'Manual' }
        4 { return 'Disabled' }
        default { return $null }
    }
}

function Resolve-TrackedServiceNames {
    param([Parameter(Mandatory)][string]$Name)

    $resolved = @(Get-Service -Name $Name, "${Name}_*" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name -Unique)

    if ($resolved.Count -gt 0) {
        return @($resolved | Sort-Object -Unique)
    }

    return @($Name)
}

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

# ── Parse reg tweak sources ───────────────────────────────────────────────────
$regEntries = [ordered]@{}
foreach ($regFile in $REG_FILES) {
    if (-not (Test-Path $regFile)) {
        Write-Host "    ERROR: reg file not found: $regFile" -ForegroundColor Red
        return
    }

    $currentKey = $null
    $pending    = $null
    $lines      = Get-Content $regFile -Encoding UTF8
    Write-Host "    Reg file : $(Split-Path $regFile -Leaf) ($($lines.Count) lines)"

    foreach ($raw in $lines) {
        # Handle multi-line continuation (hex values)
        if ($null -ne $pending) {
            $line = $pending + $raw.TrimStart()
        } else {
            $line = $raw
        }

        if ($line.TrimEnd() -match '\\$') {
            $pending = $line.TrimEnd().TrimEnd('\')
            continue
        }
        $pending = $null
        $line = $line.Trim()

        if (-not $line -or $line.StartsWith(';')) { continue }

        # Key header (skip delete-key entries starting with -)
        if ($line -match '^\[([^\]]+)\]$') {
            $keyStr = $matches[1]
            $currentKey = if ($keyStr.StartsWith('-')) { $null } else { ConvertTo-PSPath $keyStr }
            continue
        }

        if (-not $currentKey) { continue }

        # Skip: delete values, hex binary values
        if ($line -match '^"[^"]*"=-$')  { continue }
        if ($line -match '^"[^"]*"=hex') { continue }
        if ($line -match '^@=-$')        { continue }

        # DWORD: "Name"=dword:XXXXXXXX
        if ($line -match '^"([^"]+)"=dword:([0-9a-fA-F]+)$') {
            $name    = $matches[1]
            $desired = [long][Convert]::ToInt64($matches[2], 16)
            $before  = $null
            try { $before = [long](Get-ItemProperty -Path $currentKey -Name $name -ErrorAction Stop).$name } catch {}
            $regEntries["$currentKey|$name"] = @{ Path=$currentKey; Name=$name; Type='DWORD'; Before=$before; Desired=$desired }
            continue
        }

        # String: "Name"="value"
        if ($line -match '^"([^"]+)"="(.*)"$') {
            $name    = $matches[1]
            $desired = $matches[2] -replace '\\\\', '\' -replace '\\"', '"'
            $before  = $null
            try { $before = [string](Get-ItemProperty -Path $currentKey -Name $name -ErrorAction Stop).$name } catch {}
            $regEntries["$currentKey|$name"] = @{ Path=$currentKey; Name=$name; Type='String'; Before=$before; Desired=$desired }
            continue
        }

        # Default string: @="value"
        if ($line -match '^@="(.*)"$') {
            $desired = $matches[1]
            $before  = $null
            try { $before = [string](Get-ItemProperty -Path $currentKey -Name '(default)' -ErrorAction Stop).'(default)' } catch {}
            $regEntries["$currentKey|(default)"] = @{ Path=$currentKey; Name='(default)'; Type='String'; Before=$before; Desired=$desired }
            continue
        }
    }
}

foreach ($entryKey in $REQUIRED_TRACKED_REGISTRY_VALUES) {
    if (-not $regEntries.Contains($entryKey)) {
        Write-Host "    WARNING : expected tracked registry value missing: $entryKey" -ForegroundColor Yellow
    }
}

# Capture additional values set by PowerShell scripts (not present in .reg files)
foreach ($entry in $ADDITIONAL_TRACKED_REG_VALUES) {
    $key = "$($entry.Path)|$($entry.Name)"
    if (-not $regEntries.Contains($key)) {
        $before = $null
        try { $before = [long](Get-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction Stop).($entry.Name) } catch {}
        $regEntries[$key] = @{ Path=$entry.Path; Name=$entry.Name; Type=$entry.Type; Before=$before; Desired=$entry.Desired }
    }
}

$regArray = @($regEntries.Values | ForEach-Object { [PSCustomObject]$_ })
Write-Host "    Registry : $($regArray.Count) trackable values"

# ── Services snapshot ──────────────────────────────────────────────────────────
$svcSnap = [ordered]@{}
foreach ($svc in $serviceCatalog.Tracked) {
    foreach ($resolvedSvc in (Resolve-TrackedServiceNames -Name $svc)) {
        $startupType = Get-ExactServiceStartupType -Name $resolvedSvc
        if ($startupType) { $svcSnap[$resolvedSvc] = $startupType }
    }
}
Write-Host "    Services : $($svcSnap.Count) services"

# ── BCD snapshot ───────────────────────────────────────────────────────────────
$bcdSnap = @{}
try {
    bcdedit /enum '{current}' 2>$null | ForEach-Object {
        if ($_ -match '^(disabledynamictick|bootmenupolicy)\s+(.+)$') {
            $bcdSnap[$matches[1]] = $matches[2].Trim()
        }
    }
} catch {}

# ── Network snapshot ──────────────────────────────────────────────────────────
$netSnap = @{}

$tcpFields = @{}
try {
    netsh int tcp show global 2>$null | ForEach-Object {
        if ($_ -match 'Receive-Side Scaling State\s*:\s*(.+)$')    { $tcpFields['rss']                  = $matches[1].Trim().ToLower() }
        if ($_ -match 'Auto-Tuning Level\s*:\s*(.+)$')             { $tcpFields['autotuninglevel']       = $matches[1].Trim().ToLower() }
        if ($_ -match 'Congestion Control Provider\s*:\s*(.+)$')   { $tcpFields['congestionprovider']    = $matches[1].Trim().ToLower() }
        if ($_ -match 'ECN Capability\s*:\s*(.+)$')                { $tcpFields['ecncapability']         = $matches[1].Trim().ToLower() }
        if ($_ -match 'Segment Coalescing State\s*:\s*(.+)$')      { $tcpFields['rsc']                   = $matches[1].Trim().ToLower() }
        if ($_ -match 'Non Sack Rtt Resiliency\s*:\s*(.+)$')      { $tcpFields['nonsackrttresiliency']  = $matches[1].Trim().ToLower() }
        if ($_ -match 'Max SYN Retransmissions\s*:\s*(.+)$')      { $tcpFields['maxsynretransmissions'] = $matches[1].Trim().ToLower() }
        if ($_ -match 'Initial RTO\s*:\s*(.+)$')                   { $tcpFields['initialrto']            = $matches[1].Trim().ToLower() }
    }
} catch {}
$netSnap['TcpGlobal'] = $tcpFields

$heuristicsState = $null
try {
    netsh int tcp show heuristics 2>$null | ForEach-Object {
        if ($_ -match 'Window Scaling Heuristics\s*:\s*(.+)$') {
            $heuristicsState = $matches[1].Trim().ToLower()
        }
    }
} catch {}
$netSnap['Heuristics'] = $heuristicsState

$maxUserPort = $null
try { $maxUserPort = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'MaxUserPort' -ErrorAction Stop).MaxUserPort } catch {}
$netSnap['MaxUserPort'] = $maxUserPort

$pschedPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'
$nonBestEffortLimit = $null
try { $nonBestEffortLimit = (Get-ItemProperty -Path $pschedPath -Name 'NonBestEffortLimit' -ErrorAction Stop).NonBestEffortLimit } catch {}
$netSnap['NonBestEffortLimit'] = $nonBestEffortLimit

$nlaDoNotUse = $null
try { $nlaDoNotUse = (Get-ItemProperty -Path (Join-Path $pschedPath 'NLA') -Name 'Do not use NLA' -ErrorAction Stop).'Do not use NLA' } catch {}
$netSnap['NLADoNotUse'] = $nlaDoNotUse

$nagleSnap = @{}
try {
    $nagleSelection = Get-NagleTargetAdapters
    $ethernetAdapters = @($nagleSelection.Adapters)
    foreach ($adapter in $ethernetAdapters) {
        $guid      = $adapter.InterfaceGuid
        $ifacePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        $nagleEntry = @{ TcpAckFrequency = $null; TCPNoDelay = $null; TcpDelAckTicks = $null }
        if (Test-Path $ifacePath) {
            try { $nagleEntry.TcpAckFrequency = (Get-ItemProperty -Path $ifacePath -Name 'TcpAckFrequency' -ErrorAction Stop).TcpAckFrequency } catch {}
            try { $nagleEntry.TCPNoDelay      = (Get-ItemProperty -Path $ifacePath -Name 'TCPNoDelay'      -ErrorAction Stop).TCPNoDelay      } catch {}
            try { $nagleEntry.TcpDelAckTicks  = (Get-ItemProperty -Path $ifacePath -Name 'TcpDelAckTicks'  -ErrorAction Stop).TcpDelAckTicks  } catch {}
        }
        $nagleSnap[$guid] = $nagleEntry
    }
    $netSnap['NagleSelectionMode'] = $nagleSelection.Mode
    $netSnap['NagleSelectionNote'] = $nagleSelection.Note
} catch {}
$netSnap['NagleInterfaces'] = $nagleSnap

$nagleModeLabel = if ($netSnap['NagleSelectionMode']) { $netSnap['NagleSelectionMode'] } else { 'unknown' }
Write-Host "    Network  : TCP global + QoS + Nagle ($($nagleSnap.Count) interface(s), mode: $nagleModeLabel)"

# ── Affinity snapshot ─────────────────────────────────────────────────────────
$affinitySnap = [ordered]@{}
try {
    $gpus = Get-PnpDevice -Class Display -Status OK -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match '^PCI\\' }
    foreach ($gpu in $gpus) {
        $deviceIds = @($gpu.InstanceId)
        try {
            $pp = Get-PnpDeviceProperty -InstanceId $gpu.InstanceId `
                -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop
            if ($pp.Data -match '^PCI\\') {
                $deviceIds += $pp.Data
                $gpp = Get-PnpDeviceProperty -InstanceId $pp.Data `
                    -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop
                if ($gpp.Data -match '^PCI\\') { $deviceIds += $gpp.Data }
            }
        } catch {}
        foreach ($devId in $deviceIds) {
            $policyPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$devId\" +
                          "Device Parameters\Interrupt Management\Affinity Policy"
            if (Test-Path $policyPath) {
                $props = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
                $affinitySnap[$devId] = @{ Existed = $true; DevicePolicy = $props.DevicePolicy }
            } else {
                $affinitySnap[$devId] = @{ Existed = $false; DevicePolicy = $null }
            }
        }
    }
} catch {}

# ── Save ──────────────────────────────────────────────────────────────────────
@{
    Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Registry  = $regArray
    Services  = $svcSnap
    BCD       = $bcdSnap
    Network   = $netSnap
    Affinity  = $affinitySnap
} | ConvertTo-Json -Depth 4 | Set-Content $SNAP_FILE -Encoding UTF8

Write-Host "    Saved    : $SNAP_FILE"