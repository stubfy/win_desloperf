# 06_dns.ps1 - Configure le DNS Cloudflare sur toutes les interfaces reseau actives
# Remplace le script bat original (qui echouait sur les Windows non-francais)

$primaryDNS   = '1.1.1.1'
$secondaryDNS = '1.0.0.1'

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

if ($adapters.Count -eq 0) {
    Write-Host "    Aucune interface reseau active detectee." -ForegroundColor Yellow
    return
}

foreach ($adapter in $adapters) {
    try {
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name `
            -ServerAddresses ($primaryDNS, $secondaryDNS) -ErrorAction Stop
        Write-Host "    [OK] $($adapter.Name) -> $primaryDNS / $secondaryDNS"
    } catch {
        Write-Host "    [ERREUR] $($adapter.Name) : $_" -ForegroundColor Yellow
    }
}
