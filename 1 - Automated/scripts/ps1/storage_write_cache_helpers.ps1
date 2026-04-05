function ConvertTo-NormalizedDiskSerial {
    param([string]$SerialNumber)

    if ([string]::IsNullOrWhiteSpace($SerialNumber)) {
        return $null
    }

    return (($SerialNumber.ToUpperInvariant()) -replace '[^A-Z0-9]', '')
}

function Resolve-StorageWriteCacheWin32Disk {
    param(
        [Parameter(Mandatory)]$PhysicalDisk,
        [Parameter(Mandatory)]$Win32Disks
    )

    $scoredMatches = @()
    $physicalSerial = ConvertTo-NormalizedDiskSerial -SerialNumber $PhysicalDisk.SerialNumber
    $physicalModels = @(
        [string]$PhysicalDisk.Model
        [string]$PhysicalDisk.FriendlyName
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

    foreach ($win32Disk in $Win32Disks) {
        $score = 0

        if ($null -ne $PhysicalDisk.DeviceId -and $null -ne $win32Disk.Index) {
            if ([int]$PhysicalDisk.DeviceId -eq [int]$win32Disk.Index) {
                $score += 100
            }
        }

        $win32Serial = ConvertTo-NormalizedDiskSerial -SerialNumber $win32Disk.SerialNumber
        if ($physicalSerial -and $win32Serial -and $physicalSerial -eq $win32Serial) {
            $score += 50
        }

        if ($physicalModels -contains [string]$win32Disk.Model) {
            $score += 10
        }

        if ($score -gt 0) {
            $scoredMatches += [PSCustomObject]@{
                Disk  = $win32Disk
                Score = $score
            }
        }
    }

    if (-not $scoredMatches) {
        return $null
    }

    $bestMatch = $scoredMatches | Sort-Object Score -Descending | Select-Object -First 1
    $topMatches = @($scoredMatches | Where-Object { $_.Score -eq $bestMatch.Score })
    if ($topMatches.Count -ne 1) {
        return $null
    }

    return $bestMatch.Disk
}

function Get-StorageWriteCacheDiskTargets {
    param([switch]$InternalOnly)

    $physicalDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    if ($physicalDisks.Count -eq 0) {
        return @()
    }

    $win32Disks = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
    if ($win32Disks.Count -eq 0) {
        return @()
    }

    $excludedBusTypes = @(
        'USB'
        '1394'
        'SD'
        'MMC'
        'Virtual'
        'File Backed Virtual'
    )

    $targets = @()
    foreach ($physicalDisk in $physicalDisks) {
        $busType = [string]$physicalDisk.BusType
        $mediaType = [string]$physicalDisk.MediaType

        if ($busType -ne 'NVMe' -and $mediaType -ne 'SSD') {
            continue
        }

        if ($InternalOnly -and $excludedBusTypes -contains $busType) {
            continue
        }

        $win32Disk = Resolve-StorageWriteCacheWin32Disk -PhysicalDisk $physicalDisk -Win32Disks $win32Disks
        if (-not $win32Disk -or [string]::IsNullOrWhiteSpace($win32Disk.PNPDeviceID)) {
            continue
        }

        $instanceId = [string]$win32Disk.PNPDeviceID
        $diskParametersPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId\Device Parameters\Disk"
        $friendlyName = if (-not [string]::IsNullOrWhiteSpace($physicalDisk.FriendlyName)) {
            [string]$physicalDisk.FriendlyName
        } elseif (-not [string]::IsNullOrWhiteSpace($win32Disk.Model)) {
            [string]$win32Disk.Model
        } else {
            $instanceId
        }

        $targets += [PSCustomObject]@{
            InstanceId           = $instanceId
            FriendlyName         = $friendlyName
            Model                = [string]$win32Disk.Model
            SerialNumber         = if (-not [string]::IsNullOrWhiteSpace($physicalDisk.SerialNumber)) { [string]$physicalDisk.SerialNumber } else { [string]$win32Disk.SerialNumber }
            BusType              = $busType
            MediaType            = $mediaType
            DiskNumber           = if ($null -ne $win32Disk.Index) { [int]$win32Disk.Index } else { $null }
            PhysicalDiskDeviceId = if ($null -ne $physicalDisk.DeviceId) { [int]$physicalDisk.DeviceId } else { $null }
            DeviceParametersPath = Split-Path -Path $diskParametersPath -Parent
            DiskParametersPath   = $diskParametersPath
        }
    }

    return @($targets | Sort-Object DiskNumber, FriendlyName -Unique)
}

function Get-StorageWriteCacheRegistryState {
    param([Parameter(Mandatory)]$DiskTarget)

    $diskPath = [string]$DiskTarget.DiskParametersPath
    $state = [ordered]@{
        DiskKeyExists                = $false
        UserWriteCacheSetting        = $null
        UserWriteCacheSettingExisted = $false
        CacheIsPowerProtected        = $null
        CacheIsPowerProtectedExisted = $false
    }

    if (-not [string]::IsNullOrWhiteSpace($diskPath) -and (Test-Path $diskPath)) {
        $state.DiskKeyExists = $true

        try {
            $state.UserWriteCacheSetting = (Get-ItemProperty -Path $diskPath -Name 'UserWriteCacheSetting' -ErrorAction Stop).UserWriteCacheSetting
            $state.UserWriteCacheSettingExisted = $true
        } catch {
        }

        try {
            $state.CacheIsPowerProtected = (Get-ItemProperty -Path $diskPath -Name 'CacheIsPowerProtected' -ErrorAction Stop).CacheIsPowerProtected
            $state.CacheIsPowerProtectedExisted = $true
        } catch {
        }
    }

    return [PSCustomObject]$state
}

function Get-StorageWriteCacheDiskLabel {
    param([Parameter(Mandatory)]$DiskTarget)

    $name = if (-not [string]::IsNullOrWhiteSpace($DiskTarget.FriendlyName)) {
        [string]$DiskTarget.FriendlyName
    } else {
        [string]$DiskTarget.InstanceId
    }

    if ($null -ne $DiskTarget.DiskNumber) {
        return "$name (Disk $($DiskTarget.DiskNumber), $($DiskTarget.BusType))"
    }

    return "$name ($($DiskTarget.BusType))"
}
