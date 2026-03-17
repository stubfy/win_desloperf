8 - WINDOWS UPDATE
Windows Update profile on demand
================================

USAGE
-----
Run `set_windows_update.bat` as administrator.

The script exposes the same three profiles as `run_all.bat`:
  1. Maximum
  2. Security only
  3. Disable

Use it when you want to quickly switch Windows Update behavior after the main
setup without re-running the full automated phase.


ROLLBACK
--------
Run `1 - Automated\restore\11_windows_update.bat` as administrator.

That restore script reapplies profile 1 (`Maximum`), which is the pack's
Windows-default baseline.


NOTES
-----
- If you launch the PowerShell script directly, `-Profil 1|2|3` is supported
- Profile 2 pins the current release and disables driver delivery through WU
- Profile 3 disables the WU services and should only be used knowingly