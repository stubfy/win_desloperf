# 06_dns.ps1 - Configure Cloudflare DNS on all active network interfaces
# Replaces the original bat script (which failed on non-French Windows)

$primaryDNS   = '1.1.1.1'
$secondaryDNS = '1.0.0.1'

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

if ($adapters.Count -eq 0) {
    Write-Host "    No active network interface detected." -ForegroundColor Yellow
    return
}

foreach ($adapter in $adapters) {
    try {
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name `
            -ServerAddresses ($primaryDNS, $secondaryDNS) -ErrorAction Stop
        Write-Host "    [OK] $($adapter.Name) -> $primaryDNS / $secondaryDNS"
    } catch {
        Write-Host "    [ERROR] $($adapter.Name): $_" -ForegroundColor Yellow
    }
}
