#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot
$helperPath = Join-Path $repoRoot '1 - Automated\scripts\ps1\usb_power_helpers.ps1'
. $helperPath

function Assert-Equal {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

$instances = @(
    [pscustomobject]@{
        InstanceName = 'USB\VID_31E3&PID_1232&MI_00\7&31bad81&0&0000_0'
        Enable       = $true
    },
    [pscustomobject]@{
        InstanceName = 'USB\VID_31E3&PID_1232&MI_00\7&31bad81&0&0000&EXTRA_0'
        Enable       = $true
    },
    [pscustomobject]@{
        InstanceName = 'HID\VID_31E3&PID_1232&MI_00\8&38201032&0&0000_0'
        Enable       = $false
    }
)

$matches = @(Find-UsbPowerWmiInstance -InstanceId 'USB\VID_31E3&PID_1232&MI_00\7&31BAD81&0&0000' -Instances $instances)

Assert-Equal 1 $matches.Count 'WMI matching should only return the exact PnP instance plus WMI suffix.'
Assert-Equal 'USB\VID_31E3&PID_1232&MI_00\7&31bad81&0&0000_0' $matches[0].InstanceName 'WMI matching should ignore case.'

$classes = @(Get-UsbPowerTargetDeviceClasses)
foreach ($class in @('USB', 'HIDClass', 'USBDevice', 'Keyboard', 'Mouse')) {
    if ($classes -notcontains $class) {
        throw "Target device classes should include '$class'."
    }
}

Write-Host 'USB power helper tests passed.'
