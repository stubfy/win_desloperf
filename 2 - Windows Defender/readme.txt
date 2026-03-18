2 - WINDOWS DEFENDER
Manual Safe Mode Defender disable
=================================

PROCEDURE
---------
1. From normal Windows, run `run_defender.bat` as administrator
2. Confirm the prompt
3. The launcher enables Safe Mode, then reboots
4. In Safe Mode, run `run_defender.bat` again
5. The Safe Mode path disables the six Defender services, removes Safe Boot, and reboots back to normal Windows
6. Continue with `3 - MSI Utils/`, `4 - NVInspector/`, `5 - Device Manager/`, `6 - Interrupt Affinity/`, then `Tools/`.

If needed later, the quick rerun entry points are also available:
`7 - DNS/`, `8 - Windows Update/`, and `1 - Automated/scripts/13_firewall.bat`.

If you left the Defender step enabled in the initial `1 - Automated/run_all.bat` menu and then confirmed the final Safe Mode reboot, just run `2 - Windows Defender/run_defender.bat` once Safe Mode boots.

Note: on some 25H2 configurations, even in Safe Mode, modifications may still be blocked if Smart App Control is active. In that case, disable Smart App Control first via Windows Security > App & browser control.


ROLLBACK
--------
To re-enable Defender manually, restore the default `Start` values in Safe Mode:

  WinDefend : Start = 3
  Sense     : Start = 3
  WdFilter  : Start = 0
  WdNisDrv  : Start = 3
  WdNisSvc  : Start = 3
  WdBoot    : Start = 0

The global automated rollback (`1 - Automated/restore_all.bat`) restores the system tweaks, but the Defender Safe Mode step remains manual by design.


WHAT IT DOES
------------
Windows Defender runs continuously in the background and scans every file opened or executed in real time. On a dedicated gaming PC, this behavior consumes CPU resources and introduces unexpected disk accesses during gameplay, which can cause stutters.

This folder contains the manual Safe Mode flow plus the PowerShell script that disables the six kernel-level services that make up Defender.

WARNING: Disabling Defender entirely removes real-time antivirus protection. Recommended only for machines dedicated to gaming, with no unfiltered web browsing or reception of external files.


WHY SAFE MODE IS MANDATORY
--------------------------
On Windows 11 25H2, Defender is protected by two mechanisms:
- Tamper Protection: blocks Defender configuration changes from a normal process, even as administrator
- Protected Process Light (PPL): WinDefend and WdFilter run as protected services that cannot be cleanly disabled from normal mode

In Safe Mode, Tamper Protection is inactive and the minifilter drivers (`WdFilter`) do not load. Registry modification then becomes possible.


SERVICES AFFECTED
-----------------
The script disables these six services by setting their `Start` value to `4` (`Disabled`) in the registry:

  WinDefend    Main Defender service (AV engine)               default: 3
  Sense        Microsoft Defender for Endpoint (EDR telemetry) default: 3
  WdFilter     Minifilter driver hooking into file I/O         default: 0
  WdNisDrv     Network inspection driver                       default: 3
  WdNisSvc     Network inspection service                      default: 3
  WdBoot       Early launch anti-malware driver (ELAM)         default: 0


