# usb_power_helpers.ps1 - Shared USB power-management helpers

function Get-UsbPowerTargetDeviceClasses {
    @('USB', 'HIDClass', 'USBDevice', 'Keyboard', 'Mouse')
}

function Get-UsbPowerTargetDevices {
    foreach ($class in Get-UsbPowerTargetDeviceClasses) {
        Get-PnpDevice -Class $class -Status OK -ErrorAction SilentlyContinue
    }
}

function Find-UsbPowerWmiInstance {
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Instances
    )

    foreach ($instance in $Instances) {
        if (-not $instance.InstanceName) { continue }

        $baseInstanceName = ([string]$instance.InstanceName) -replace '_\d+$', ''
        if ($baseInstanceName -ieq $InstanceId) {
            $instance
        }
    }
}

function Get-UsbPowerWmiBackupEntries {
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Instances
    )

    @(Find-UsbPowerWmiInstance -InstanceId $InstanceId -Instances $Instances | ForEach-Object {
        [ordered]@{
            InstanceName = $_.InstanceName
            Enable       = [bool]$_.Enable
        }
    })
}

function Set-UsbPowerStateProperty {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()]$Value
    )

    if ($State -is [System.Collections.IDictionary]) {
        if (-not $State.Contains($Name)) {
            $State[$Name] = $Value
        }
        return
    }

    if (-not ($State.PSObject.Properties.Name -contains $Name)) {
        Add-Member -InputObject $State -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Add-UsbPowerWmiBackupState {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PowerDeviceEnableInstances,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PowerDeviceWakeEnableInstances
    )

    Set-UsbPowerStateProperty `
        -State $State `
        -Name 'PowerDeviceEnable' `
        -Value @(Get-UsbPowerWmiBackupEntries -InstanceId $InstanceId -Instances $PowerDeviceEnableInstances)

    Set-UsbPowerStateProperty `
        -State $State `
        -Name 'PowerDeviceWakeEnable' `
        -Value @(Get-UsbPowerWmiBackupEntries -InstanceId $InstanceId -Instances $PowerDeviceWakeEnableInstances)
}

function Disable-UsbPowerWmiInstances {
    param(
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Instances
    )

    $modified = 0
    foreach ($instance in @(Find-UsbPowerWmiInstance -InstanceId $InstanceId -Instances $Instances)) {
        if ($instance.Enable -eq $false) { continue }

        try {
            Set-CimInstance -InputObject $instance -Property @{ Enable = $false } -ErrorAction Stop | Out-Null
            $modified++
        } catch {
            Write-Host "    [WARNING] Could not disable WMI power flag for $($instance.InstanceName): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    return $modified
}

function Restore-UsbPowerWmiBackupEntries {
    param(
        [Parameter()]$Entries,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Instances
    )

    if ($null -eq $Entries) { return 0 }

    $restored = 0
    foreach ($entry in @($Entries)) {
        if (-not $entry.InstanceName) { continue }

        $instance = @($Instances | Where-Object { $_.InstanceName -ieq $entry.InstanceName } | Select-Object -First 1)
        if ($instance.Count -eq 0) { continue }

        try {
            Set-CimInstance -InputObject $instance[0] -Property @{ Enable = [bool]$entry.Enable } -ErrorAction Stop | Out-Null
            $restored++
        } catch {
            Write-Host "    [WARNING] Could not restore WMI power flag for $($entry.InstanceName): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    return $restored
}
