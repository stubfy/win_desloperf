# 18_firewall.ps1 - Disable Windows Firewall profiles
#
# Disables all three Windows Firewall profiles (Domain, Private, Public).
# On a gaming PC behind a home router with NAT, the Windows Firewall provides
# a redundant layer over the router's stateful packet filtering. Disabling it:
#   - Removes the per-packet inspection overhead for all inbound/outbound traffic.
#   - Eliminates firewall-related delays on the first packet of new connections
#     (rule lookup, logging, connection tracking).
#   - Prevents firewall popups when launching new games or server software.
#
# SECURITY NOTE: Disabling the firewall removes the host-based last line of
# defense. If the router is bypassed (direct ISP connection, public Wi-Fi,
# VPN split tunneling) the PC is directly exposed to the network. This option
# defaults to Y in run_all.ps1 but can be declined at setup time.
#
# The pre-disable state of each profile (Enabled/Disabled) is saved to
# backup\firewall_state.json by 01_backup.ps1 for precise rollback.
#
# Rollback: restore\18_firewall.ps1 reads firewall_state.json and restores
# each profile to its original Enabled/Disabled state.

try {
    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled False -ErrorAction Stop
    Write-Host "    [OK] Windows Firewall disabled for Domain, Private and Public profiles"
} catch {
    Write-Host "    [ERROR] Unable to disable Windows Firewall profiles: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
