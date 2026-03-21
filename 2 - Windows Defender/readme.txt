2 - WINDOWS DEFENDER
Manual Safe Mode Defender disable
=================================

PROCEDURE
---------
1. From normal Windows, run `run_defender.bat` as administrator
2. Confirm the prompt
3. The launcher enables Safe Mode and creates a Desktop shortcut
4. In Safe Mode, run `Disable Defender and Return to Normal Mode` from the Desktop
5. The Desktop shortcut points to the static launcher, which disables the six Defender services, removes Safe Boot, and reboots back to normal Windows


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

This folder contains the manual Safe Mode flow plus the PowerShell script that disables the six kernel-level services that make up Defender. The script also disables Smart App Control (`VerifiedAndReputablePolicyState=0`).

WARNING: Disabling Defender entirely removes real-time antivirus protection. Recommended only for machines dedicated to gaming, with no unfiltered web browsing or reception of external files.

WARNING: Disabling Smart App Control is IRREVERSIBLE. Once set to Off, it cannot be re-enabled without reinstalling Windows.


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

In addition, the script sets Smart App Control to Off:

  HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy\VerifiedAndReputablePolicyState = 0
  (0 = Off, 1 = Evaluation, 2 = Enforcing)

  This change is IRREVERSIBLE -- re-enabling Smart App Control requires a
  full Windows reinstall. Safe Mode is required because Tamper Protection
  protects the CI\Policy key in normal mode.


