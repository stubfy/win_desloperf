7 - WINDOWS UPDATE
Windows Update profile on demand
================================

USAGE
-----
Run `set_windows_update.bat` as administrator.

The script exposes the same three profiles as `run_all.bat`:
  1. Default
  2. Security
  3. Disabled

Use it when you want to quickly switch Windows Update behavior after the main
setup without re-running the full automated phase.


ROLLBACK
--------
Run `1 - Automated\restore\windows_update.bat` as administrator.

That restore script reapplies profile 1 (`Default`), which is the pack's
WinUtil-aligned Windows Update baseline with Delivery Optimization peer sharing
kept off.


NOTES
-----
- If you launch the PowerShell script directly, `-Profil 1|2|3` is supported
- Profile 2 applies the WinUtil recommended profile: no drivers via WU, feature updates deferred 365 days, quality updates deferred 4 days
- Profile 2 also disables Insider preview builds and automatic optional preview updates for a stable update channel
- Profile 2 hides optional driver updates that Windows Update has already offered
- If hidden drivers remain cached in Settings, Profile 2 backs up and rebuilds the USO UX store, then asks Windows Update to refresh its view
- Delivery Optimization peer sharing is disabled with DODownloadMode=0; Microsoft CDN downloads still work
- Profile 3 disables the WU services and should only be used knowingly
