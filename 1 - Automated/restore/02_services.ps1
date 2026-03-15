# restore\02_services.ps1 - Restore services to their original state

$BACKUP_DIR = Join-Path (Split-Path $PSScriptRoot) "backup"
$stateFile  = Join-Path $BACKUP_DIR "services_state.json"
$serviceCatalog = & (Join-Path (Join-Path (Split-Path $PSScriptRoot) 'scripts') '03_services.ps1') -ExportCatalogOnly

function Set-ServiceDwordValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Set-ServiceStartupTypeExact {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$StartupType
    )

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) { return $false }

    $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"

    switch ($StartupType) {
        'Disabled' {
            Stop-Service $Name -Force -ErrorAction SilentlyContinue
            Set-Service $Name -StartupType Disabled -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 4
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0
        }
        'Manual' {
            Set-Service $Name -StartupType Manual -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 3
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0
        }
        'Automatic' {
            Set-Service $Name -StartupType Automatic -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 2
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 0
        }
        'AutomaticDelayedStart' {
            Set-Service $Name -StartupType Automatic -ErrorAction SilentlyContinue
            Set-ServiceDwordValue -Path $serviceKey -Name 'Start' -Value 2
            Set-ServiceDwordValue -Path $serviceKey -Name 'DelayedAutoStart' -Value 1
        }
        default {
            throw "Unsupported startup type: $StartupType"
        }
    }

    return $true
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
    if (Set-ServiceStartupTypeExact -Name $svc -StartupType $startupType) {
        if ($startupType -eq 'Automatic') {
            Start-Service $svc -ErrorAction SilentlyContinue
        }
        Write-Host "    [RESTORED]  $svc -> $startupType"
    } else {
        Write-Host "    [NOT FOUND] $svc" -ForegroundColor Gray
    }
}

# DoSvc can be restored to its startup type, but TriggerInfo is not recreated here.
if ($defaults.Contains('DoSvc') -and $defaults['DoSvc'] -in @('Manual', 'Disabled')) {
    $triggerPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc\TriggerInfo'
    if (Test-Path $triggerPath) {
        Remove-Item $triggerPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
