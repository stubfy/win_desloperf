# restore\05_edge.ps1 - Remove Microsoft Edge policies applied by opti pack

$paths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev'
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdateDev'
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    [REMOVED]   $path"
    } else {
        Write-Host "    [NOT FOUND] $path" -ForegroundColor Gray
    }
}

$edgeUninstallKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'
)

foreach ($key in $edgeUninstallKeys) {
    if (Test-Path $key) {
        Set-ItemProperty -Path $key -Name NoRemove -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "    [RESTORED]  $key\NoRemove -> 1"
    }
}
