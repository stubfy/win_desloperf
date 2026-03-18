# restore\services.ps1 - Restore services to their original state

$BACKUP_DIR = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "backup"
$stateFile  = Join-Path $BACKUP_DIR "services_state.json"
$serviceCatalog = & (Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'scripts\ps1\services.ps1') -ExportCatalogOnly

function Set-ServiceDwordValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )

    try {
        $props = Get-ItemProperty -Path $Path -ErrorAction Stop
        if ($props.PSObject.Properties.Name -contains $Name) {
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force -ErrorAction Stop
        } else {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        }
        return $true
    } catch {
        return $false
    }
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

function Set-ServiceStartupTypeExact {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$StartupType
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) {
        return [PSCustomObject]@{
            Exists    = $false
            Applied   = $false
            Current   = $null
            Requested = $StartupType
        }
    }

    $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $scStartValue = $null

    switch ($StartupType) {
        'Disabled' {
            $scStartValue = 'disabled'
            try { Stop-Service $Name -Force -ErrorAction SilentlyContinue } catch {}
            try { Set-Service $Name -StartupType Disabled -ErrorAction SilentlyContinue } catch {}
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 4 | Out-Null
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0 | Out-Null
        }
        'Manual' {
            $scStartValue = 'demand'
            try { Set-Service $Name -StartupType Manual -ErrorAction SilentlyContinue } catch {}
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 3 | Out-Null
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0 | Out-Null
        }
        'Automatic' {
            $scStartValue = 'auto'
            try { Set-Service $Name -StartupType Automatic -ErrorAction SilentlyContinue } catch {}
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 2 | Out-Null
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0 | Out-Null
        }
        'AutomaticDelayedStart' {
            $scStartValue = 'delayed-auto'
            try { Set-Service $Name -StartupType Automatic -ErrorAction SilentlyContinue } catch {}
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 2 | Out-Null
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 1 | Out-Null
        }
        default {
            throw "Unsupported startup type: $StartupType"
        }
    }

    if ($scStartValue) {
        try { & sc.exe config $Name start= $scStartValue 2>$null | Out-Null } catch {}
    }

    $current = Get-ExactServiceStartupType -Name $Name
    if ($Name -eq 'IKEEXT' -and $current -ne $StartupType -and $scStartValue) {
        try { & sc.exe config $Name start= $scStartValue 2>$null | Out-Null } catch {}
        Start-Sleep -Milliseconds 250
        $current = Get-ExactServiceStartupType -Name $Name
    }

    return [PSCustomObject]@{
        Exists    = $true
        Applied   = ($current -eq $StartupType)
        Current   = $current
        Requested = $StartupType
    }
}

function Write-ServiceStartupResult {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Result.Exists) {
        Write-Host "    [NOT FOUND] $Name" -ForegroundColor Gray
        return
    }

    if ($Result.Applied) {
        Write-Host "    [RESTORED]  $Name -> $($Result.Requested)"
        return
    }

    $current = if ($Result.Current) { $Result.Current } else { 'Unknown' }
    Write-Host "    [WARN]      $Name -> current=$current wanted=$($Result.Requested)" -ForegroundColor Yellow
}

# Reference fallback values if no backup is available
$defaults = [ordered]@{}
foreach ($svc in $serviceCatalog.Defaults.Keys) {
    $defaults[$svc] = $serviceCatalog.Defaults[$svc]
}

# Load saved state if available
if (Test-Path $stateFile) {
    $saved = Get-Content $stateFile -Encoding UTF8 | ConvertFrom-Json
    foreach ($prop in $saved.PSObject.Properties) {
        $defaults[$prop.Name] = $prop.Value
    }
    Write-Host "    Saved state loaded from: $stateFile"
} else {
    Write-Host "    No backup found, using Windows default values." -ForegroundColor Gray
}

foreach ($svc in $defaults.Keys) {
    $startupType = $defaults[$svc]
    $result = Set-ServiceStartupTypeExact -Name $svc -StartupType $startupType
    if ($result.Exists -and $result.Applied -and $startupType -eq 'Automatic') {
        Start-Service $svc -ErrorAction SilentlyContinue
    }
    Write-ServiceStartupResult -Result $result -Name $svc
}

# DoSvc can be restored to its startup type, but TriggerInfo is not recreated here.
if ($defaults.Contains('DoSvc') -and $defaults['DoSvc'] -in @('Manual', 'Disabled')) {
    $triggerPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc\TriggerInfo'
    if (Test-Path $triggerPath) {
        Remove-Item $triggerPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
