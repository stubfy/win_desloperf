# 06_dns.ps1 - Configure Cloudflare DNS on all active network interfaces
#
# Replaces any ISP-assigned DNS servers with Cloudflare's public resolvers.
# Cloudflare 1.1.1.1 / 1.0.0.1 are chosen for:
#   - Low latency: typically <5 ms from Western Europe / North America
#   - Privacy: query logs purged within 24h, no selling to advertisers
#   - Reliability: anycast BGP routing, no single point of failure
#
# The script enumerates all adapters with Status=Up (connected) at runtime,
# avoiding hardcoded adapter names which fail on non-French Windows builds.
# This replaces the original batch script that relied on French adapter names.
#
# DNS changes take effect immediately for new connections; ongoing connections
# are unaffected until they need to resolve new hostnames.
#
# Rollback: restore\04_dns.ps1 restores DHCP-assigned DNS (SetDnsClientServerAddress
# with -ResetServerAddresses, delegating DNS back to the DHCP server/router).

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
