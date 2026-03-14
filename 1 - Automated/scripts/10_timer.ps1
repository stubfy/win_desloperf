# 10_timer.ps1 - Install SetTimerResolution to AppData and add to Windows startup

$ROOT     = Split-Path $PSScriptRoot
$timerSrc = Join-Path $ROOT "tools\SetTimerResolution.exe"
$vcRuntimeDll = Join-Path $env:SystemRoot 'System32\vcruntime140_1.dll'
$vcRedistUrl  = 'https://aka.ms/vc14/vc_redist.x64.exe'

function Ensure-VcRuntimeForSetTimerResolution {
    if (Test-Path $vcRuntimeDll) {
        return $true
    }

    $installerPath = Join-Path ([System.IO.Path]::GetTempPath()) 'win_deslopper_vc_redist.x64.exe'
    Write-Host "    VC++ runtime   : missing, downloading Microsoft Visual C++ Redistributable..." -ForegroundColor Yellow

    try {
        Invoke-WebRequest -Uri $vcRedistUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Host "    [WARNING] Failed to download VC++ runtime: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }

    try {
        $proc = Start-Process -FilePath $installerPath `
            -ArgumentList '/install /quiet /norestart' `
            -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop

        if ($proc.ExitCode -notin @(0, 1638, 3010)) {
            Write-Host "    [WARNING] VC++ runtime installer returned exit code $($proc.ExitCode)." -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "    [WARNING] Failed to install VC++ runtime: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    } finally {
        if (Test-Path $installerPath) {
            Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path $vcRuntimeDll) {
        Write-Host "    VC++ runtime   : installed"
        return $true
    }

    Write-Host "    [WARNING] VC++ runtime is still missing after installation attempt." -ForegroundColor Yellow
    return $false
}

if (-not (Test-Path $timerSrc)) {
    Write-Host "    SetTimerResolution.exe not found: $timerSrc" -ForegroundColor Yellow
    return
}

try {
    Unblock-File -Path $timerSrc -ErrorAction Stop
} catch {
    # Best effort: some environments do not expose a zone identifier stream.
}

if (-not (Ensure-VcRuntimeForSetTimerResolution)) {
    Write-Host "    SetTimerResolution requires the Microsoft Visual C++ x64 runtime." -ForegroundColor Yellow
    Write-Host "    Timer startup integration skipped until the runtime is available." -ForegroundColor Yellow
    return
}

# Install to %APPDATA%\win_deslopper\
$installDir = Join-Path $env:APPDATA "win_deslopper"
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}
$timerExe = Join-Path $installDir "SetTimerResolution.exe"

# Stop any running instance before overwriting the executable
$running = Get-Process -Name "SetTimerResolution" -ErrorAction SilentlyContinue
if ($running) {
    $running | Stop-Process -Force
    Write-Host "    Stopped running SetTimerResolution instance"
}

Copy-Item -Path $timerSrc -Destination $timerExe -Force
Write-Host "    Installed to   : $timerExe"

try {
    Unblock-File -Path $timerExe -ErrorAction Stop
} catch {
    # Best effort: if the file is already unblocked or streams are unavailable, continue.
}

$startupDir   = [System.Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDir "SetTimerResolution.lnk"

$wsh      = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath       = $timerExe
$shortcut.Arguments        = "--resolution 5200 --no-console"
$shortcut.WorkingDirectory = $installDir
$shortcut.Description      = "SetTimerResolution - Opti Pack"
$shortcut.Save()

Write-Host "    Shortcut created: $shortcutPath"
Write-Host "    Arguments      : --resolution 5200 --no-console"

# Launch immediately so the resolution is active without a reboot
try {
    Start-Process -FilePath $timerExe -ArgumentList "--resolution 5200 --no-console" -WindowStyle Hidden -ErrorAction Stop
    Write-Host "    Launched       : SetTimerResolution is now active"
} catch {
    Write-Host "    Launch skipped : $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "                     Startup shortcut is still installed; it will retry at next sign-in." -ForegroundColor Yellow
}
Write-Host "    Tip            : use MeasureSleep.exe to verify the actual resolution"
Write-Host "                     (adjust value if needed: 5000, 5100, 5200...)"
