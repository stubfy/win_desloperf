param([string]$SourceRoot = '')

$ErrorActionPreference = 'Continue'

function Get-PreferredDisplayGpu {
    $allGpus = @()
    if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
        $allGpus = Get-PnpDevice -Class Display -Status OK -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match '^PCI\\' }
    }

    if (-not $allGpus) {
        $allGpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPDeviceID -match '^PCI\\' } |
            ForEach-Object {
                [PSCustomObject]@{
                    FriendlyName = $_.Name
                    InstanceId   = $_.PNPDeviceID
                }
            }
    }

    if (-not $allGpus) {
        return $null
    }

    $igpuPattern = 'Intel.*(UHD|Iris|HD Graphics)|Microsoft Basic Display'
    $dGpus = $allGpus | Where-Object { $_.FriendlyName -notmatch $igpuPattern }
    if (-not $dGpus) {
        $dGpus = $allGpus
    }

    $gpu = $dGpus | Where-Object { $_.FriendlyName -match 'NVIDIA' } | Select-Object -First 1
    if (-not $gpu) {
        $gpu = $dGpus | Where-Object { $_.FriendlyName -match 'AMD|Radeon' } | Select-Object -First 1
    }
    if (-not $gpu) {
        $gpu = $dGpus | Select-Object -First 1
    }

    return $gpu
}

$gpu = Get-PreferredDisplayGpu
if (-not $gpu) {
    Write-Host "    [WARN] No PCI display device found. NVIDIA Profile Inspector install skipped." -ForegroundColor Yellow
    return
}

Write-Host "    GPU detected   : $($gpu.FriendlyName)"
if ($gpu.FriendlyName -notmatch 'NVIDIA') {
    Write-Host "    Skipped        : install only applies to NVIDIA GPUs" -ForegroundColor DarkGray
    return
}

if ($SourceRoot -eq '') { $SourceRoot = Split-Path $PSScriptRoot -Parent }
$sourceDir = Get-ChildItem -Path $SourceRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'NVPI-R.exe') } |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $sourceDir) {
    Write-Host "    [WARN] NVPI-R.exe source folder not found in $SourceRoot" -ForegroundColor Yellow
    return
}

$installRoot = Join-Path $env:APPDATA 'win_deslopper'
$installDir  = Join-Path $installRoot 'NVInspector'
$exePath     = Join-Path $installDir 'NVPI-R.exe'
$desktopDir  = [System.Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopDir 'NVIDIA Profile Inspector.lnk'

if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

$running = Get-Process -Name 'NVPI-R' -ErrorAction SilentlyContinue
if ($running) {
    $running | Stop-Process -Force
    Write-Host "    Stopped running NVPI-R instance"
}

Copy-Item -Path (Join-Path $sourceDir.FullName '*') -Destination $installDir -Recurse -Force
Write-Host "    Source        : $($sourceDir.FullName)"
Write-Host "    Installed to  : $installDir"

Get-ChildItem -Path $installDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Unblock-File -Path $_.FullName -ErrorAction Stop
    } catch {
        # Best effort: continue if no zone identifier stream is present.
    }
}

if (-not (Test-Path $exePath)) {
    Write-Host "    [WARN] Install completed but NVPI-R.exe is missing in $installDir" -ForegroundColor Yellow
    return
}

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath       = $exePath
$shortcut.WorkingDirectory = $installDir
$shortcut.Description      = 'NVIDIA Profile Inspector - win_deslopper'
$shortcut.IconLocation     = "$exePath,0"
$shortcut.Save()

Write-Host "    Shortcut      : $shortcutPath"
