# 00_snapshot.ps1 - Snapshot system state before tweaks
# Saved to backup/snapshot_latest.json, used by 99_show_diff.ps1

$ROOT       = Split-Path $PSScriptRoot
$BACKUP_DIR = Join-Path $ROOT "backup"
$REG_FILES  = @(
    (Join-Path $PSScriptRoot "tweaks_consolidated.reg")
    (Join-Path $PSScriptRoot "uwt_tweaks.reg")
)
$SNAP_FILE  = Join-Path $BACKUP_DIR "snapshot_latest.json"

if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
}

$serviceCatalog = & (Join-Path $PSScriptRoot '03_services.ps1') -ExportCatalogOnly

function ConvertTo-PSPath([string]$p) {
    return $p `
        -replace '^HKEY_LOCAL_MACHINE\\', 'HKLM:\' `
        -replace '^HKEY_CURRENT_USER\\',  'HKCU:\' `
        -replace '^HKEY_CLASSES_ROOT\\',  'HKCR:\' `
        -replace '^HKEY_USERS\\',         'HKU:\'
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

$regArray = @($regEntries.Values | ForEach-Object { [PSCustomObject]$_ })
Write-Host "    Registry : $($regArray.Count) trackable values"

# ── Services snapshot ──────────────────────────────────────────────────────────
$svcSnap = [ordered]@{}
foreach ($n in $serviceCatalog.Tracked) {
    $s = Get-Service -Name $n -ErrorAction SilentlyContinue
    if ($s) { $svcSnap[$n] = $s.StartType.ToString() }
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

# ── Save ──────────────────────────────────────────────────────────────────────
@{
    Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Registry  = $regArray
    Services  = $svcSnap
    BCD       = $bcdSnap
} | ConvertTo-Json -Depth 4 | Set-Content $SNAP_FILE -Encoding UTF8

Write-Host "    Saved    : $SNAP_FILE"
