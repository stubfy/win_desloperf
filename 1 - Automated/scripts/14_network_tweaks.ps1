# 14_network_tweaks.ps1 - Additional network tweaks (source: Chris Titus WinUtil)
#
# Teredo: An IPv6 transition technology that tunnels IPv6 traffic over UDP/IPv4.
# It creates a virtual network adapter and maintains a NAT traversal session with
# a Teredo relay server on the internet. Issues for gaming:
#   - Adds a persistent UDP "ping" session to a Microsoft relay server, generating
#     background traffic even when no IPv6 content is being accessed.
#   - The Teredo NAT traversal logic can interfere with some game UDP paths that
#     use the same port range, occasionally causing unexpected routing behavior.
#   - On a dual-stack ISP connection where native IPv6 is available, Teredo is
#     redundant; on IPv4-only connections it tunnels through a relay which adds
#     a hop and increases latency compared to direct IPv4.
# Effect: Disabling Teredo removes the virtual adapter and background relay session.
# The DisabledComponents=0x20 key in tweaks_consolidated.reg handles IPv4 preference
# at the stack level; this command handles the Teredo tunnel adapter specifically.
#
# Rollback: restore\14_network_tweaks.ps1 restores: netsh interface teredo set state default

# Disable Teredo IPv6-over-IPv4 tunnel
netsh interface teredo set state disabled 2>&1 | ForEach-Object { Write-Host "    $_" }
Write-Host "    Teredo disabled"
