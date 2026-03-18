#Requires -Version 5.0
<#
.SYNOPSIS
    win_desloperf pack updater.
.DESCRIPTION
    Checks the latest GitHub tag, shows the changelog tag-by-tag, and can
    replace the current pack in place without requiring git on the user side.
.NOTES
    No administrator rights required.
    Run from the pack root by double-clicking update_pack.bat.
#>

param(
    [switch]$CheckOnly,
    [int]$TimeoutSec = 20,
    [string]$RootPath = ''
)

$ErrorActionPreference = 'Stop'
$ROOT = if (-not [string]::IsNullOrWhiteSpace($RootPath)) { (Get-Item $RootPath).FullName } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$REPO = 'stubfy/win_desloperf'
$VERSION_FILE = Join-Path $ROOT 'pack-version.txt'
$LEGACY_VERSION_FILE = Join-Path $ROOT '1 - Automated\scripts\ps1\run_all.ps1'

try {
    $tls12 = [Net.SecurityProtocolType]::Tls12
    if (([Net.ServicePointManager]::SecurityProtocol -band $tls12) -eq 0) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor $tls12
    }
}
catch {
    # Best effort only.
}

function Write-Note {
    param([string]$Text)
    Write-Host "  $Text"
}

function Write-Info {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor DarkGray
}

function Write-Ok {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Red
}

function Get-WebRequestParams {
    $params = @{
        Headers = @{
            'User-Agent' = 'win_desloperf-updater'
            'Accept'     = 'application/vnd.github+json'
        }
        TimeoutSec = $TimeoutSec
    }

    return $params
}

function Get-WebDownloadParams {
    $params = Get-WebRequestParams

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $params.UseBasicParsing = $true
    }

    return $params
}

function Invoke-GitHubJson {
    param([string]$Url)

    $params = Get-WebRequestParams
    return Invoke-RestMethod -Uri $Url @params
}

function Invoke-GitHubDownload {
    param(
        [string]$Url,
        [string]$OutFile
    )

    $params = Get-WebDownloadParams
    Invoke-WebRequest -Uri $Url -OutFile $OutFile @params | Out-Null
}

function Get-SemVer {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return $null
    }

    $trimmed = $Version.Trim()
    $match = [regex]::Match($trimmed, '^[vV]?(\d+)(?:\.(\d+))?(?:\.(\d+))?$')
    if (-not $match.Success) {
        return $null
    }

    [pscustomobject]@{
        Original = if ($trimmed.StartsWith('v')) { $trimmed } elseif ($trimmed.StartsWith('V')) { 'v' + $trimmed.Substring(1) } else { 'v' + $trimmed }
        Major    = [int]$match.Groups[1].Value
        Minor    = if ($match.Groups[2].Success) { [int]$match.Groups[2].Value } else { 0 }
        Patch    = if ($match.Groups[3].Success) { [int]$match.Groups[3].Value } else { 0 }
    }
}

function Compare-SemVer {
    param(
        [pscustomobject]$Left,
        [pscustomobject]$Right
    )

    if (-not $Left -or -not $Right) {
        return $null
    }

    foreach ($part in @('Major', 'Minor', 'Patch')) {
        if ($Left.$part -lt $Right.$part) { return -1 }
        if ($Left.$part -gt $Right.$part) { return 1 }
    }

    return 0
}

function Get-LocalVersion {
    if (Test-Path $VERSION_FILE) {
        $raw = Get-Content -Path $VERSION_FILE -ErrorAction Stop | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            return $raw.Trim()
        }
    }

    if (Test-Path $LEGACY_VERSION_FILE) {
        $legacyContent = Get-Content -Path $LEGACY_VERSION_FILE -Raw -ErrorAction Stop
        $match = [regex]::Match($legacyContent, '\$PACK_VERSION\s*=\s*''([^'']+)''')
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }

    return $null
}

function Get-RemoteTags {
    $tags = Invoke-GitHubJson -Url "https://api.github.com/repos/$REPO/tags?per_page=100"
    $semverTags = foreach ($tag in $tags) {
        $parsed = Get-SemVer -Version ([string]$tag.name)
        if ($parsed) {
            [pscustomobject]@{
                Name  = $parsed.Original
                Major = $parsed.Major
                Minor = $parsed.Minor
                Patch = $parsed.Patch
            }
        }
    }

    return $semverTags | Sort-Object Major, Minor, Patch -Unique
}

function Get-ReleaseInfo {
    param([string]$Tag)

    try {
        $release = Invoke-GitHubJson -Url "https://api.github.com/repos/$REPO/releases/tags/$Tag"
        [pscustomobject]@{
            Tag         = $Tag
            PublishedAt = if ($release.published_at) { ([datetime]$release.published_at).ToString('yyyy-MM-dd') } else { $null }
            Body        = [string]$release.body
        }
    }
    catch {
        $response = $_.Exception.Response
        if ($response -and [int]$response.StatusCode -eq 404) {
            return $null
        }

        throw
    }
}

function Show-Changelog {
    param([object[]]$Tags)

    if (-not $Tags -or $Tags.Count -eq 0) {
        return
    }

    Write-Host ''
    Write-Host '  Changelog' -ForegroundColor Cyan
    Write-Host ''

    foreach ($tag in $Tags) {
        $releaseInfo = Get-ReleaseInfo -Tag $tag.Name
        $dateSuffix = if ($releaseInfo -and $releaseInfo.PublishedAt) { " - $($releaseInfo.PublishedAt)" } else { '' }
        Write-Host "  [$($tag.Name)]$dateSuffix" -ForegroundColor White

        if ($releaseInfo -and -not [string]::IsNullOrWhiteSpace($releaseInfo.Body)) {
            foreach ($line in ($releaseInfo.Body -split "`r?`n")) {
                if ([string]::IsNullOrWhiteSpace($line)) {
                    Write-Host ''
                }
                else {
                    Write-Host "    $line" -ForegroundColor DarkGray
                }
            }
        }
        else {
            Write-Info 'No published release notes for this tag.'
        }

        Write-Host ''
    }
}

function Get-SafeVersionLabel {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return 'unknown'
    }

    return ($Version -replace '[^A-Za-z0-9._-]', '_')
}

function Write-HelperScript {
    param(
        [string]$HelperPath,
        [string]$TempRoot
    )

    $helperContent = @'
param(
    [string]$PackRoot,
    [string]$ExpandedRoot,
    [string]$BackupRoot,
    [int]$ParentPid,
    [string]$TempRoot
)

$ErrorActionPreference = 'Stop'

function Write-Stage {
    param([string]$Text)
    Write-Host "  $Text"
}

function Write-StageOk {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Green
}

function Write-StageWarn {
    param([string]$Text)
    Write-Host "  $Text" -ForegroundColor Yellow
}

function Wait-ForParentExit {
    param([int]$Id)

    if ($Id -le 0) {
        return
    }

    while (Get-Process -Id $Id -ErrorAction SilentlyContinue) {
        Start-Sleep -Milliseconds 400
    }

    Start-Sleep -Milliseconds 400
}

function Copy-DirectoryContents {
    param(
        [string]$SourceDir,
        [string]$DestinationDir
    )

    if (-not (Test-Path $SourceDir)) {
        return
    }

    if (-not (Test-Path $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }

    Get-ChildItem -Path $SourceDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $DestinationDir -Recurse -Force
    }
}

function Copy-PreservedFiles {
    $backupDir = Join-Path $BackupRoot '1 - Automated\backup'
    $targetBackupDir = Join-Path $PackRoot '1 - Automated\backup'
    Copy-DirectoryContents -SourceDir $backupDir -DestinationDir $targetBackupDir

    $msiDir = Join-Path $BackupRoot '3 - MSI Utils'
    $targetMsiDir = Join-Path $PackRoot '3 - MSI Utils'
    if (Test-Path $msiDir) {
        if (-not (Test-Path $targetMsiDir)) {
            New-Item -ItemType Directory -Path $targetMsiDir -Force | Out-Null
        }

        Get-ChildItem -Path $msiDir -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $targetMsiDir -Force
        }
    }
}

$movedOldPack = $false
$movedNewPack = $false

try {
    Write-Host ''
    Write-Host '  win_desloperf - Applying update' -ForegroundColor Cyan
    Write-Host ''

    Wait-ForParentExit -Id $ParentPid

    if (-not (Test-Path $PackRoot)) {
        throw "Pack folder not found: $PackRoot"
    }

    if (-not (Test-Path $ExpandedRoot)) {
        throw "Expanded update folder not found: $ExpandedRoot"
    }

    if (Test-Path $BackupRoot) {
        throw "Backup path already exists: $BackupRoot"
    }

    Write-Stage "Backup       : $BackupRoot"
    Move-Item -LiteralPath $PackRoot -Destination $BackupRoot
    $movedOldPack = $true

    Write-Stage "Install path : $PackRoot"
    Move-Item -LiteralPath $ExpandedRoot -Destination $PackRoot
    $movedNewPack = $true

    Write-Stage 'Preserving local backup and MSI state files...'
    Copy-PreservedFiles

    Write-Host ''
    Write-StageOk 'Update completed successfully.'
    Write-Stage "Pack folder  : $PackRoot"
    Write-Stage "Backup kept  : $BackupRoot"
    Write-Host ''

    try {
        Start-Process -FilePath explorer.exe -ArgumentList $PackRoot | Out-Null
    } catch {
        Write-StageWarn "Could not open Explorer automatically: $($_.Exception.Message)"
    }
}
catch {
    Write-Host ''
    Write-Host "  Update failed: $($_.Exception.Message)" -ForegroundColor Red

    if ($movedOldPack -and (Test-Path $BackupRoot)) {
        if (Test-Path $PackRoot) {
            Remove-Item -LiteralPath $PackRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        Move-Item -LiteralPath $BackupRoot -Destination $PackRoot
        Write-StageWarn 'Original pack restored.'
    }

    exit 1
}
finally {
    if ($TempRoot -and (Test-Path $TempRoot)) {
        $cleanupArgs = "/c ping 127.0.0.1 -n 3 >nul && rd /s /q ""$TempRoot"""
        Start-Process -FilePath cmd.exe -ArgumentList $cleanupArgs -WindowStyle Hidden | Out-Null
    }
}
'@

    Set-Content -Path $HelperPath -Value $helperContent -Encoding UTF8
}

Write-Host ''
Write-Host '  win_desloperf - Pack update' -ForegroundColor Cyan
Write-Host ("  " + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor DarkGray
Write-Host ''

$localVersion = Get-LocalVersion
if ($localVersion) {
    Write-Note "Current pack : $localVersion"
}
else {
    Write-Warn 'Current pack version could not be detected.'
}

try {
    $remoteTags = @(Get-RemoteTags)
}
catch {
    Write-Err "Could not read remote tags: $($_.Exception.Message)"
    exit 1
}

if (-not $remoteTags -or $remoteTags.Count -eq 0) {
    Write-Err 'No valid semver tags were found on GitHub.'
    exit 1
}

$latestTag = $remoteTags[-1]
Write-Note "Latest tag   : $($latestTag.Name)"

$localSemVer = Get-SemVer -Version $localVersion
$status = 'UNKNOWN'
$tagsForChangelog = @()

if ($localSemVer) {
    $comparison = Compare-SemVer -Left $localSemVer -Right $latestTag
    switch ($comparison) {
        0 {
            $status = 'CURRENT'
            Write-Ok 'Status       : up to date'
        }
        -1 {
            $status = 'UPDATE'
            Write-Warn 'Status       : update available'
        }
        1 {
            $status = 'AHEAD'
            Write-Warn 'Status       : local pack is newer than the latest GitHub tag'
        }
    }

    $localIndex = -1
    for ($i = 0; $i -lt $remoteTags.Count; $i++) {
        if ((Compare-SemVer -Left $localSemVer -Right $remoteTags[$i]) -eq 0) {
            $localIndex = $i
            break
        }
    }

    if ($localIndex -ge 0) {
        if ($localIndex -lt ($remoteTags.Count - 1)) {
            $tagsForChangelog = $remoteTags[($localIndex + 1)..($remoteTags.Count - 1)]
        }
    }
    elseif ($status -eq 'UPDATE') {
        Write-Warn 'Current pack version is not present in remote tags; changelog by tag is unavailable for this install.'
    }
}
else {
    Write-Warn 'Current pack version is unknown; changelog by tag is unavailable for this install.'
}

if ($status -eq 'CURRENT' -or $status -eq 'AHEAD') {
    Write-Host ''
    exit 0
}

if ($tagsForChangelog.Count -gt 0) {
    try {
        Show-Changelog -Tags $tagsForChangelog
    }
    catch {
        Write-Warn "Could not load changelog: $($_.Exception.Message)"
        Write-Host ''
    }
}

if ($CheckOnly) {
    Write-Host ''
    exit 0
}

$answer = Read-Host "  Update this folder to $($latestTag.Name)? (Y/N) [default: N]"
if ($answer -notin @('Y', 'y')) {
    Write-Info 'Cancelled.'
    Write-Host ''
    exit 0
}

$tempRoot = Join-Path $env:TEMP ("win_desloperf-update-" + [guid]::NewGuid().ToString('N'))
$zipPath = Join-Path $tempRoot 'pack.zip'
$extractPath = Join-Path $tempRoot 'extract'
$helperPath = Join-Path $tempRoot 'apply_update.ps1'

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

try {
    Write-Host ''
    Write-Note "Downloading  : $($latestTag.Name)"
    Invoke-GitHubDownload -Url "https://github.com/$REPO/archive/refs/tags/$($latestTag.Name).zip" -OutFile $zipPath

    Write-Note 'Extracting   : archive contents'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $expandedRoot = Get-ChildItem -Path $extractPath -Directory -ErrorAction Stop | Select-Object -First 1
    if (-not $expandedRoot) {
        throw 'The downloaded archive did not contain a pack folder.'
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupRoot = Join-Path (Split-Path $ROOT -Parent) ("{0}.backup-{1}-{2}" -f (Split-Path $ROOT -Leaf), (Get-SafeVersionLabel -Version $localVersion), $timestamp)

    Write-HelperScript -HelperPath $helperPath -TempRoot $tempRoot

    $helperArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $helperPath,
        '-PackRoot', $ROOT,
        '-ExpandedRoot', $expandedRoot.FullName,
        '-BackupRoot', $backupRoot,
        '-ParentPid', $PID,
        '-TempRoot', $tempRoot
    )

    Start-Process -FilePath 'powershell.exe' -ArgumentList $helperArgs -WorkingDirectory $env:TEMP | Out-Null

    Write-Host ''
    Write-Warn 'A new updater window has been opened to finish the replacement.'
    Write-Info 'This window will close now so the folder can be replaced safely.'
    Write-Host ''
    exit 10
}
catch {
    Write-Err "Update preparation failed: $($_.Exception.Message)"
    Write-Host ''
    exit 1
}
