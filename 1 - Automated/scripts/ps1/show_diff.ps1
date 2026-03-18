# show_diff.ps1 - Compare current system state to pre-tweak snapshot
# Shows what actually changed vs what was already correct.
# Can be run standalone anytime to detect Windows Update regressions.
#
# Reads backup\snapshot_latest.json (written by snapshot.ps1 before tweaks ran)
# and compares each tracked value against the current system state.
#
# Output categories:
#   "already OK"  - The value was already at the desired target before the pack ran.
#                   (System was partially or fully configured before this run.)
#   "applied"     - The value was different before and is now at the target. Changed by the pack.
#   "failed"      - The value is still not at the desired target after the pack ran.
#                   Investigate: protected key, unsupported OS version, requires reboot.
#
# DiffExcluded services (BITS, UsoSvc, wuauserv): These services are managed by
# set_windows_update.ps1 with user-chosen profiles. Their desired final state depends
# on the chosen profile and cannot be statically predicted, so they are excluded from
# the diff to avoid misleading "failed" entries.
#
# Standalone use: Run this script after a Windows Update or major upgrade to check
# whether the update has reset any of the pack's tweaks back to defaults. Any "failed"
# entries in that context are regressions introduced by the update.

$ROOT      = Split-Path (Split-Path $PSScriptRoot)
$SNAP_FILE = Join-Path $ROOT "backup\snapshot_latest.json"
$serviceCatalog = & (Join-Path $PSScriptRoot 'services.ps1') -ExportCatalogOnly
$volatileRegistryKeys = @(
    'HKCU:\Control Panel\Keyboard|InitialKeyboardIndicators'
)
$volatileRegistryApplied = [System.Collections.Generic.List[object]]::new()
$volatileServicesApplied = [System.Collections.Generic.List[object]]::new()
$volatileServices = if ($serviceCatalog.PSObject.Properties.Name -contains 'DiffVolatile') {
    @($serviceCatalog.DiffVolatile)
} else {
    @()
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

if (-not (Test-Path $SNAP_FILE)) {
    Write-Host "  No snapshot found at: $SNAP_FILE" -ForegroundColor Yellow
    Write-Host "  Run the pack once first to create a baseline." -ForegroundColor DarkGray
    return
}

$snap = Get-Content $SNAP_FILE -Encoding UTF8 | ConvertFrom-Json

# ── Registry diff ─────────────────────────────────────────────────────────────
$regChanged = [System.Collections.Generic.List[object]]::new()
$regAlready = 0
$regFailed  = [System.Collections.Generic.List[object]]::new()

foreach ($data in $snap.Registry) {
    $path    = $data.Path
    $name    = $data.Name
    $type    = $data.Type
    $before  = $data.Before
    $desired = $data.Desired
    $entryId = "$path|$name"
    $isVolatile = $entryId -in $volatileRegistryKeys

    $current = $null
    try {
        $v       = Get-ItemProperty -Path $path -Name $name -ErrorAction Stop
        $current = if ($type -eq 'DWORD') { [long]$v.$name } else { [string]$v.$name }
    } catch { continue }  # key/value missing, skip

    $desiredN = if ($type -eq 'DWORD') { [long]$desired } else { [string]$desired }
    $beforeN  = if ($null -eq $before) { $null }
                elseif ($type -eq 'DWORD') { [long]$before }
                else { [string]$before }

    if ($current -eq $desiredN) {
        if ($beforeN -eq $desiredN) {
            if (-not $isVolatile) {
                $regAlready++
            }
        } else {
            $changeRecord = [PSCustomObject]@{
                Path   = $path
                Name   = $name
                Before = if ($null -eq $beforeN) { '(missing)' } else { $beforeN }
                After  = $current
            }
            if ($isVolatile) {
                $volatileRegistryApplied.Add($changeRecord)
            } else {
                $regChanged.Add($changeRecord)
            }
        }
    } else {
        $regFailed.Add([PSCustomObject]@{
            Path    = $path
            Name    = $name
            Current = $current
            Desired = $desiredN
        })
    }
}

# ── Services diff ─────────────────────────────────────────────────────────────
$svcDesiredMap = @{}
foreach ($svc in $serviceCatalog.Disabled) {
    $svcDesiredMap[$svc] = 'Disabled'
}
# BITS, UsoSvc and wuauserv excluded: their state is overridden by set_windows_update.ps1
foreach ($svc in $serviceCatalog.Manual) {
    if ($svc -notin $serviceCatalog.DiffExcluded) {
        $svcDesiredMap[$svc] = 'Manual'
    }
}
foreach ($svc in $serviceCatalog.Automatic) {
    if ($svc -notin $serviceCatalog.DiffExcluded) {
        $svcDesiredMap[$svc] = 'Automatic'
    }
}
foreach ($svc in $serviceCatalog.AutomaticDelayedStart) {
    if ($svc -notin $serviceCatalog.DiffExcluded) {
        $svcDesiredMap[$svc] = 'AutomaticDelayedStart'
    }
}

$svcChanged = [System.Collections.Generic.List[object]]::new()
$svcAlready = 0
$svcFailed  = [System.Collections.Generic.List[object]]::new()

foreach ($prop in $snap.Services.PSObject.Properties) {
    $svcName = $prop.Name
    $before  = $prop.Value
    $desired = $svcDesiredMap[$svcName]
    if (-not $desired) { continue }

    $current = Get-ExactServiceStartupType -Name $svcName
    if (-not $current) { continue }

    $isVolatile = $svcName -in $volatileServices
    if ($current -eq $desired) {
        if ($before -eq $desired) {
            if (-not $isVolatile) {
                $svcAlready++
            }
        } else {
            $changeRecord = [PSCustomObject]@{ Name=$svcName; Before=$before; After=$current }
            if ($isVolatile) {
                $volatileServicesApplied.Add($changeRecord)
            } else {
                $svcChanged.Add($changeRecord)
            }
        }
    } else {
        $svcFailed.Add([PSCustomObject]@{ Name=$svcName; Current=$current; Desired=$desired })
    }
}

# ── BCD diff ──────────────────────────────────────────────────────────────────
$bcdDesired = @{ disabledynamictick='Yes'; bootmenupolicy='Legacy' }
$bcdChanged = [System.Collections.Generic.List[object]]::new()
$bcdAlready = 0
$bcdCurrent = @{}

try {
    bcdedit /enum '{current}' 2>$null | ForEach-Object {
        if ($_ -match '^(disabledynamictick|bootmenupolicy)\s+(.+)$') {
            $bcdCurrent[$matches[1]] = $matches[2].Trim()
        }
    }
} catch {}

foreach ($key in $bcdDesired.Keys) {
    $before  = if ($snap.BCD.$key) { $snap.BCD.$key } else { '(not set)' }
    $desired = $bcdDesired[$key]
    $current = if ($bcdCurrent[$key]) { $bcdCurrent[$key] } else { '(not set)' }

    if ($current -ieq $desired) {
        if ($before -ieq $desired) { $bcdAlready++ } else { $bcdChanged.Add([PSCustomObject]@{ Key=$key; Before=$before; After=$current }) }
    }
}

# ── Affinity diff ─────────────────────────────────────────────────────────────
$affinityApplied = 0
$affinityAlready = 0

if ($snap.Affinity) {
    foreach ($prop in $snap.Affinity.PSObject.Properties) {
        $devId       = $prop.Name
        $beforeSnap  = $prop.Value
        $beforePolicy = if ($null -ne $beforeSnap.DevicePolicy) { [int]$beforeSnap.DevicePolicy } else { $null }

        $policyPath  = "HKLM:\SYSTEM\CurrentControlSet\Enum\$devId\" +
                       "Device Parameters\Interrupt Management\Affinity Policy"
        $currentPolicy = $null
        if (Test-Path $policyPath) {
            $props = Get-ItemProperty -Path $policyPath -ErrorAction SilentlyContinue
            if ($null -ne $props.DevicePolicy) { $currentPolicy = [int]$props.DevicePolicy }
        }

        if ($currentPolicy -eq 4) {
            if ($beforePolicy -eq 4) { $affinityAlready++ } else { $affinityApplied++ }
        }
    }
}

# ── Network diff ──────────────────────────────────────────────────────────────
$netChanged = [System.Collections.Generic.List[object]]::new()
$netAlready = 0
$netFailed  = [System.Collections.Generic.List[object]]::new()

if ($snap.Network) {
    # Desired TCP global state
    $tcpDesired = @{
        autotuninglevel      = 'normal'
        rss                  = 'enabled'
        ecncapability        = 'enabled'
        rsc                  = 'disabled'
        nonsackrttresiliency = 'disabled'
        maxsynretransmissions = '2'
    }

    # Read current TCP global state
    $tcpCurrent = @{}
    try {
        netsh int tcp show global 2>$null | ForEach-Object {
            if ($_ -match 'Receive-Side Scaling State\s*:\s*(.+)$')    { $tcpCurrent['rss']                  = $matches[1].Trim().ToLower() }
            if ($_ -match 'Auto-Tuning Level\s*:\s*(.+)$')             { $tcpCurrent['autotuninglevel']       = $matches[1].Trim().ToLower() }
            if ($_ -match 'Congestion Control Provider\s*:\s*(.+)$')   { $tcpCurrent['congestionprovider']    = $matches[1].Trim().ToLower() }
            if ($_ -match 'ECN Capability\s*:\s*(.+)$')                { $tcpCurrent['ecncapability']         = $matches[1].Trim().ToLower() }
            if ($_ -match 'Segment Coalescing State\s*:\s*(.+)$')      { $tcpCurrent['rsc']                   = $matches[1].Trim().ToLower() }
            if ($_ -match 'Non Sack Rtt Resiliency\s*:\s*(.+)$')      { $tcpCurrent['nonsackrttresiliency']  = $matches[1].Trim().ToLower() }
            if ($_ -match 'Max SYN Retransmissions\s*:\s*(.+)$')      { $tcpCurrent['maxsynretransmissions'] = $matches[1].Trim().ToLower() }
        }
    } catch {}

    foreach ($key in $tcpDesired.Keys) {
        $snapVal = $snap.Network.TcpGlobal.$key
        $before  = if ($null -ne $snapVal) { [string]$snapVal } else { '(unknown)' }
        $desired = $tcpDesired[$key]
        $current = if ($tcpCurrent[$key]) { $tcpCurrent[$key] } else { '(unknown)' }
        if ($current -ieq $desired) {
            if ($before -ieq $desired) { $netAlready++ }
            else { $netChanged.Add([PSCustomObject]@{ Key="tcp.$key"; Before=$before; After=$current }) }
        } else {
            $netFailed.Add([PSCustomObject]@{ Key="tcp.$key"; Current=$current; Desired=$desired })
        }
    }

    # Heuristics
    $heuristicsCurrent = $null
    try {
        netsh int tcp show heuristics 2>$null | ForEach-Object {
            if ($_ -match 'Window Scaling Heuristics\s*:\s*(.+)$') {
                $heuristicsCurrent = $matches[1].Trim().ToLower()
            }
        }
    } catch {}
    if ($heuristicsCurrent) {
        $hBefore  = if ($snap.Network.Heuristics) { [string]$snap.Network.Heuristics } else { '(unknown)' }
        $hDesired = 'disabled'
        if ($heuristicsCurrent -ieq $hDesired) {
            if ($hBefore -ieq $hDesired) { $netAlready++ }
            else { $netChanged.Add([PSCustomObject]@{ Key='heuristics'; Before=$hBefore; After=$heuristicsCurrent }) }
        } else {
            $netFailed.Add([PSCustomObject]@{ Key='heuristics'; Current=$heuristicsCurrent; Desired=$hDesired })
        }
    }

    # MaxUserPort
    $maxPortCurrent = $null
    try { $maxPortCurrent = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'MaxUserPort' -ErrorAction Stop).MaxUserPort } catch {}
    if ($null -ne $maxPortCurrent) {
        $mBefore  = $snap.Network.MaxUserPort
        $mDesired = 65534
        if ([int]$maxPortCurrent -eq $mDesired) {
            if ($null -ne $mBefore -and [int]$mBefore -eq $mDesired) { $netAlready++ }
            else { $netChanged.Add([PSCustomObject]@{ Key='MaxUserPort'; Before=if($null -eq $mBefore){'(missing)'}else{$mBefore}; After=$maxPortCurrent }) }
        } else {
            $netFailed.Add([PSCustomObject]@{ Key='MaxUserPort'; Current=$maxPortCurrent; Desired=$mDesired })
        }
    }

    # QoS NonBestEffortLimit
    $pschedPath  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'
    $nonBestCurr = $null
    try { $nonBestCurr = (Get-ItemProperty -Path $pschedPath -Name 'NonBestEffortLimit' -ErrorAction Stop).NonBestEffortLimit } catch {}
    if ($null -ne $nonBestCurr) {
        $nbBefore  = $snap.Network.NonBestEffortLimit
        $nbDesired = 0
        if ([int]$nonBestCurr -eq $nbDesired) {
            if ($null -ne $nbBefore -and [int]$nbBefore -eq $nbDesired) { $netAlready++ }
            else { $netChanged.Add([PSCustomObject]@{ Key='QoS.NonBestEffortLimit'; Before=if($null -eq $nbBefore){'(missing)'}else{$nbBefore}; After=$nonBestCurr }) }
        } else {
            $netFailed.Add([PSCustomObject]@{ Key='QoS.NonBestEffortLimit'; Current=$nonBestCurr; Desired=$nbDesired })
        }
    }

    # QoS NLADoNotUse
    $nlaCurr = $null
    try { $nlaCurr = (Get-ItemProperty -Path (Join-Path $pschedPath 'NLA') -Name 'Do not use NLA' -ErrorAction Stop).'Do not use NLA' } catch {}
    if ($null -ne $nlaCurr) {
        $nlaBefore  = $snap.Network.NLADoNotUse
        $nlaDesired = 1
        if ([int]$nlaCurr -eq $nlaDesired) {
            if ($null -ne $nlaBefore -and [int]$nlaBefore -eq $nlaDesired) { $netAlready++ }
            else { $netChanged.Add([PSCustomObject]@{ Key='QoS.NLADoNotUse'; Before=if($null -eq $nlaBefore){'(missing)'}else{$nlaBefore}; After=$nlaCurr }) }
        } else {
            $netFailed.Add([PSCustomObject]@{ Key='QoS.NLADoNotUse'; Current=$nlaCurr; Desired=$nlaDesired })
        }
    }

    # Nagle per-interface
    if ($snap.Network.NagleInterfaces) {
        foreach ($prop in $snap.Network.NagleInterfaces.PSObject.Properties) {
            $guid      = $prop.Name
            $ifacePath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
            if (-not (Test-Path $ifacePath)) { continue }
            $ifProps   = Get-ItemProperty -Path $ifacePath -ErrorAction SilentlyContinue
            $shortGuid = $guid.Substring(1, 8)
            foreach ($nKey in @('TcpAckFrequency', 'TCPNoDelay', 'TcpDelAckTicks')) {
                $desired   = if ($nKey -eq 'TcpDelAckTicks') { 0 } else { 1 }
                $beforeVal = $prop.Value.$nKey
                $currVal   = $null
                try { $currVal = [int]$ifProps.$nKey } catch {}
                if ($null -ne $currVal) {
                    if ($currVal -eq $desired) {
                        if ($null -ne $beforeVal -and [int]$beforeVal -eq $desired) { $netAlready++ }
                        else { $netChanged.Add([PSCustomObject]@{ Key="Nagle.$nKey ($shortGuid)"; Before=if($null -eq $beforeVal){'(missing)'}else{$beforeVal}; After=$currVal }) }
                    } else {
                        $netFailed.Add([PSCustomObject]@{ Key="Nagle.$nKey ($shortGuid)"; Current=$currVal; Desired=$desired })
                    }
                }
            }
        }
    }
}

# ── Display ───────────────────────────────────────────────────────────────────
function fPath([string]$p) { $p -replace 'HKLM:\\','HKLM\' -replace 'HKCU:\\','HKCU\' -replace 'HKCR:\\','HKCR\' }

$totalReg = $regChanged.Count + $regAlready + $regFailed.Count
$totalSvc = $svcChanged.Count + $svcAlready + $svcFailed.Count
$totalBcd = $bcdChanged.Count + $bcdAlready
$totalNet = $netChanged.Count + $netAlready + $netFailed.Count
$totalAff = if ($snap.Affinity) { @($snap.Affinity.PSObject.Properties).Count } else { 0 }

Write-Host ""
Write-Host "  RECAP - What actually changed" -ForegroundColor Cyan
Write-Host "  Snapshot: $($snap.Timestamp)" -ForegroundColor DarkGray
Write-Host "  -----------------------------------------------------------------" -ForegroundColor DarkGray

# Summary table
Write-Host ""
Write-Host ("  {0,-12} {1,3} checked   {2,3} already OK   {3,3} applied   {4,3} failed" -f `
    "Registry", $totalReg, $regAlready, $regChanged.Count, $regFailed.Count) -ForegroundColor White
Write-Host ("  {0,-12} {1,3} checked   {2,3} already OK   {3,3} applied   {4,3} failed" -f `
    "Services",  $totalSvc, $svcAlready,  $svcChanged.Count,  $svcFailed.Count) -ForegroundColor White
Write-Host ("  {0,-12} {1,3} checked   {2,3} already OK   {3,3} applied" -f `
    "BCD",  $totalBcd, $bcdAlready,  $bcdChanged.Count) -ForegroundColor White
if ($snap.Network) {
    Write-Host ("  {0,-12} {1,3} checked   {2,3} already OK   {3,3} applied   {4,3} failed" -f `
        "Network", $totalNet, $netAlready, $netChanged.Count, $netFailed.Count) -ForegroundColor White
}
if ($snap.Affinity) {
    Write-Host ("  {0,-12} {1,3} checked   {2,3} already OK   {3,3} applied" -f `
        "Affinity", $totalAff, $affinityAlready, $affinityApplied) -ForegroundColor White
}

# Registry changes
if ($regChanged.Count -gt 0) {
    Write-Host ""
    Write-Host "  Registry - applied ($($regChanged.Count)):" -ForegroundColor Green
    foreach ($r in $regChanged) {
        Write-Host ("    + {0,-40}  {1}  ->  {2}" -f $r.Name, $r.Before, $r.After) -ForegroundColor Green
        Write-Host ("      $(fPath $r.Path)") -ForegroundColor DarkGray
    }
}

# Service changes
if ($svcChanged.Count -gt 0) {
    Write-Host ""
    Write-Host "  Services - applied ($($svcChanged.Count)):" -ForegroundColor Green
    foreach ($s in $svcChanged) {
        Write-Host ("    + {0,-35}  {1}  ->  {2}" -f $s.Name, $s.Before, $s.After) -ForegroundColor Green
    }
}

if ($volatileRegistryApplied.Count -gt 0) {
    Write-Host ""
    Write-Host "  Registry - volatile / re-applied ($($volatileRegistryApplied.Count), not counted):" -ForegroundColor Yellow
    foreach ($r in $volatileRegistryApplied) {
        Write-Host ("    ~ {0,-40}  {1}  ->  {2}" -f $r.Name, $r.Before, $r.After) -ForegroundColor Yellow
        Write-Host ("      $(fPath $r.Path)") -ForegroundColor DarkGray
    }
}

if ($volatileServicesApplied.Count -gt 0) {
    Write-Host ""
    Write-Host "  Services - volatile / re-applied ($($volatileServicesApplied.Count), not counted):" -ForegroundColor Yellow
    foreach ($s in $volatileServicesApplied) {
        Write-Host ("    ~ {0,-35}  {1}  ->  {2}" -f $s.Name, $s.Before, $s.After) -ForegroundColor Yellow
    }
}

# BCD changes
if ($bcdChanged.Count -gt 0) {
    Write-Host ""
    Write-Host "  BCD - applied ($($bcdChanged.Count)):" -ForegroundColor Green
    foreach ($b in $bcdChanged) {
        Write-Host ("    + {0,-35}  {1}  ->  {2}" -f $b.Key, $b.Before, $b.After) -ForegroundColor Green
    }
}

# Failures
if ($regFailed.Count -gt 0) {
    Write-Host ""
    Write-Host "  Registry - FAILED ($($regFailed.Count)):" -ForegroundColor Red
    foreach ($r in $regFailed) {
        Write-Host ("    x {0,-40}  current={1}  wanted={2}" -f $r.Name, $r.Current, $r.Desired) -ForegroundColor Red
        Write-Host ("      $(fPath $r.Path)") -ForegroundColor DarkGray
    }
}

if ($svcFailed.Count -gt 0) {
    Write-Host ""
    Write-Host "  Services - FAILED ($($svcFailed.Count)):" -ForegroundColor Red
    foreach ($s in $svcFailed) {
        Write-Host ("    x {0,-35}  current={1}  wanted={2}" -f $s.Name, $s.Current, $s.Desired) -ForegroundColor Red
    }
}

# Network changes
if ($snap.Network -and $netChanged.Count -gt 0) {
    Write-Host ""
    Write-Host "  Network - applied ($($netChanged.Count)):" -ForegroundColor Green
    foreach ($n in $netChanged) {
        Write-Host ("    + {0,-40}  {1}  ->  {2}" -f $n.Key, $n.Before, $n.After) -ForegroundColor Green
    }
}

if ($snap.Network -and $netFailed.Count -gt 0) {
    Write-Host ""
    Write-Host "  Network - FAILED ($($netFailed.Count)):" -ForegroundColor Red
    foreach ($n in $netFailed) {
        Write-Host ("    x {0,-40}  current={1}  wanted={2}" -f $n.Key, $n.Current, $n.Desired) -ForegroundColor Red
    }
}

Write-Host ""
