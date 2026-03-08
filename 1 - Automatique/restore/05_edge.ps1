# restore\05_edge.ps1 - Supprime les politiques Microsoft Edge appliquees par opti pack

$paths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    [SUPPRIME] $path"
    } else {
        Write-Host "    [ABSENT]   $path" -ForegroundColor Gray
    }
}
