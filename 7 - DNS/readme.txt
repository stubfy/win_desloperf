7 - DNS
Cloudflare DNS on demand
========================

USAGE
-----
Run `set_dns.bat` as administrator.

The script applies Cloudflare DNS (`1.1.1.1` / `1.0.0.1`) to all active
network adapters detected at runtime. Use it when Windows, a driver update,
or a network reset reverted the adapters back to DHCP/router DNS.


ROLLBACK
--------
Run `1 - Automated\restore\04_dns.bat` as administrator.

That restore script resets DNS to automatic DHCP on all active adapters.


WHAT IT DOES
------------
- Enumerates every adapter with `Status = Up`
- Applies `Set-DnsClientServerAddress` with Cloudflare resolvers
- Avoids hardcoded adapter names, so it works regardless of Windows language