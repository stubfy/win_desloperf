# timer.ps1 - Install SetTimerResolution to AppData and add to Windows startup
#
# Background:
#   The Windows timer resolution controls how frequently the OS clock interrupt fires.
#   The default is ~15.6 ms (64 Hz). Setting it to 520 µs (~1923 Hz) means the OS
#   wakes up to service timers up to ~1923 times per second instead of 64.
#   Effect: sleep() calls in games, audio drivers and input polling loops are
#   satisfied much more promptly, reducing frame pacing jitter and input latency.
#
# GlobalTimerResolutionRequests=1 (set in tweaks_consolidated.reg via registry.ps1)
#   is required for this to benefit game threads system-wide. Without it, Windows
#   10 2004+ scopes the resolution to the requesting process only.
#
# SetTimerResolution.exe by ValleyOfDoom calls NtSetTimerResolution internally.
#   --resolution 5200 : requests 5200 x 100 ns = 520 µs = 0.52 ms.
#   The unit used by NtSetTimerResolution (and SetTimerResolution.exe) is 100-nanosecond intervals.
#   Use Tools\MeasureSleep.exe to verify the actual achieved resolution post-reboot.
#   Values in the 5000-5500 range are well-tested; lower values may not be honored
#   by all hardware/driver combinations.
#
# VC++ runtime: SetTimerResolution.exe and MeasureSleep.exe require the
#   Visual C++ 2015-2022 x64 redistributable. The script checks for the core
#   runtime DLLs and attempts a silent download/install if missing.
#
# Rollback: restore\timer.ps1 deletes the startup shortcut and terminates the process.

$ROOT     = Split-Path (Split-Path $PSScriptRoot)
$timerSrc = Join-Path $ROOT "tools\SetTimerResolution.exe"
$vcRuntimeDlls = @(
    (Join-Path $env:SystemRoot 'System32\vcruntime140.dll'),
    (Join-Path $env:SystemRoot 'System32\vcruntime140_1.dll'),
    (Join-Path $env:SystemRoot 'System32\msvcp140.dll')
)
$vcRedistUrl  = 'https://aka.ms/vc14/vc_redist.x64.exe'

function Ensure-VcRuntimeForTimerTools {
    if (($vcRuntimeDlls | Where-Object { -not (Test-Path $_) }).Count -eq 0) {
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

    if (($vcRuntimeDlls | Where-Object { -not (Test-Path $_) }).Count -eq 0) {
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

if (-not (Ensure-VcRuntimeForTimerTools)) {
    Write-Host "    SetTimerResolution and MeasureSleep require the Microsoft Visual C++ x64 runtime." -ForegroundColor Yellow
    Write-Host "    Timer startup integration skipped until the runtime is available." -ForegroundColor Yellow
    return
}

# Install to %APPDATA%\win_deslopper\ so the binary persists across pack updates
# without requiring admin rights to the original pack directory at runtime.
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

# Create a startup shortcut in the user's Startup folder so SetTimerResolution
# launches automatically at each sign-in and maintains the requested resolution.
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

# Launch immediately so the resolution is active without requiring a reboot.
# The --no-console flag suppresses the terminal window.
try {
    Start-Process -FilePath $timerExe -ArgumentList "--resolution 5200 --no-console" -WindowStyle Hidden -ErrorAction Stop
    Write-Host "    Launched       : SetTimerResolution is now active"
} catch {
    Write-Host "    Launch skipped : $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "                     Startup shortcut is still installed; it will retry at next sign-in." -ForegroundColor Yellow
}
Write-Host "    Tip            : use Tools\MeasureSleep.exe as administrator to verify the actual resolution"
Write-Host "                     (adjust value if needed: 5000, 5100, 5200...)"
