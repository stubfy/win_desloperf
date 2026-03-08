# restore\04_dns.ps1 - Remet le DNS en DHCP automatique sur toutes les interfaces

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

foreach ($adapter in $adapters) {
    try {
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses -ErrorAction Stop
        Write-Host "    [DHCP] DNS automatique restaure sur : $($adapter.Name)"
    } catch {
        Write-Host "    [ERREUR] $($adapter.Name) : $_" -ForegroundColor Yellow
    }
}
