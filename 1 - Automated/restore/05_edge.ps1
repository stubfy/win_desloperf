# restore\05_edge.ps1 - Remove Microsoft Edge policies applied by opti pack

$paths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    [REMOVED]   $path"
    } else {
        Write-Host "    [NOT FOUND] $path" -ForegroundColor Gray
    }
}
