# restore\04_dns.ps1 - Reset DNS to automatic DHCP on all interfaces

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

foreach ($adapter in $adapters) {
    try {
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses -ErrorAction Stop
        Write-Host "    [DHCP] Automatic DNS restored on: $($adapter.Name)"
    } catch {
        Write-Host "    [ERROR] $($adapter.Name): $_" -ForegroundColor Yellow
    }
}
