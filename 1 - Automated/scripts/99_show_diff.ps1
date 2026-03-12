# 99_show_diff.ps1 - Compare current system state to pre-tweak snapshot
# Shows what actually changed vs what was already correct.
# Can be run standalone anytime to detect Windows Update regressions.

$ROOT      = Split-Path $PSScriptRoot
$SNAP_FILE = Join-Path $ROOT "backup\snapshot_latest.json"

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
            $regAlready++
        } else {
            $regChanged.Add([PSCustomObject]@{
                Path   = $path
                Name   = $name
                Before = if ($null -eq $beforeN) { '(missing)' } else { $beforeN }
                After  = $current
            })
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
@('SysMain','DPS','Spooler','TabletInputService','RmSvc','DiagTrack','dmwappushservice',
  'WSearch','WerSvc','PhoneSvc','SCardSvr','ScDeviceEnum','SEMgrSvc','WpcMonSvc',
  'lfsvc','MapsBroker','RetailDemo','RemoteRegistry','SharedAccess') |
    ForEach-Object { $svcDesiredMap[$_] = 'Disabled' }
# DoSvc: force-disabled via registry + TriggerInfo removal (Set-Service alone is ignored on 25H2)
$svcDesiredMap['DoSvc'] = 'Disabled'
# UsoSvc, BITS, WpnService excluded: their state is overridden by 15_windows_update.ps1
# AssignedAccessManagerSvc excluded: Kiosk service, Disabled is acceptable
@('CDPSvc','InventorySvc','PcaSvc','StorSvc','camsvc',
  'edgeupdate','edgeupdatem','WSAIFabricSvc') |
    ForEach-Object { $svcDesiredMap[$_] = 'Manual' }

$svcChanged = [System.Collections.Generic.List[object]]::new()
$svcAlready = 0
$svcFailed  = [System.Collections.Generic.List[object]]::new()

foreach ($prop in $snap.Services.PSObject.Properties) {
    $svcName = $prop.Name
    $before  = $prop.Value
    $desired = $svcDesiredMap[$svcName]
    if (-not $desired) { continue }

    $s = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $s) { continue }
    $current = $s.StartType.ToString()

    if ($current -eq $desired) {
        if ($before -eq $desired) { $svcAlready++ }
        else { $svcChanged.Add([PSCustomObject]@{ Name=$svcName; Before=$before; After=$current }) }
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

# ── Display ───────────────────────────────────────────────────────────────────
function fPath([string]$p) { $p -replace 'HKLM:\\','HKLM\' -replace 'HKCU:\\','HKCU\' -replace 'HKCR:\\','HKCR\' }

$totalReg = $regChanged.Count + $regAlready + $regFailed.Count
$totalSvc = $svcChanged.Count + $svcAlready + $svcFailed.Count
$totalBcd = $bcdChanged.Count + $bcdAlready

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

Write-Host ""
