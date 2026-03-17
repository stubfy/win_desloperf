9 - FIREWALL
Disable Windows Firewall on demand
==================================

USAGE
-----
Run `disable_firewall.bat` as administrator.

The script disables the Domain, Private, and Public Windows Firewall profiles.
Use it when Windows re-enables the firewall after an update or a reset and you
want to restore the pack's intended state without re-running everything else.


ROLLBACK
--------
Run `1 - Automated\restore\12_firewall.bat` as administrator.

That restore script reads `backup\firewall_state.json` and restores the exact
profile states captured before the pack changed them.


WARNING
-------
Disabling the firewall removes the host-based filtering layer. Only do this if
your setup is intentionally relying on another protection layer or isolation.