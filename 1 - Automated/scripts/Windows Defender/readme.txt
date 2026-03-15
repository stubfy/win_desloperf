WINDOWS DEFENDER
Safe Mode disable helper inside 1 - Automated/scripts
======================================================

QUICK PATH FROM RUN_ALL.BAT
---------------------------
1. Finish `1 - Automated/run_all.bat`
2. At the final reboot prompt, choose `[S]`
3. In Safe Mode, run `Disable Defender and Return to Normal Mode.bat` from the Desktop

The Desktop helper runs `1 - DisableDefender.ps1` from this folder, removes the Safe Boot
flag, and reboots back to normal Windows automatically.

PROCEDURE
---------
1. Open msconfig (Win+R > msconfig > Enter)
2. Boot tab > check "Safe boot" > Minimal mode > OK
3. Reboot -- Windows starts in Safe Mode
4. Open PowerShell as administrator
5. Run : Set-ExecutionPolicy Bypass -Scope Process
6. Run the script : .\1 - DisableDefender.ps1
7. Reopen msconfig > uncheck "Safe boot" > OK
8. Reboot normally

Note : on some 25H2 configurations, even in Safe Mode, modifications may
be blocked if Smart App Control is active. In that case, disable Smart App
Control first via Windows Security > App & browser control.


ROLLBACK
--------
To re-enable Defender, restore the default values :

  WinDefend : Start = 3
  Sense      : Start = 3
  WdFilter   : Start = 0
  WdNisDrv   : Start = 3
  WdNisSvc   : Start = 3
  WdBoot     : Start = 0

Then manually restore these default values with the same Safe Mode
procedure if needed.


WHAT IT DOES
------------
Windows Defender runs continuously in the background and scans every
file opened or executed in real time. On a dedicated gaming PC, this
behavior consumes CPU resources and introduces unexpected disk accesses
during gameplay, which can cause stutters.

This folder contains a PowerShell script to disable the six kernel-level
services that make up Defender.

WARNING : Disabling Defender entirely removes real-time antivirus protection.
Recommended only for machines exclusively dedicated to gaming, with no
unfiltered web browsing or reception of external files.


WHY SAFE MODE IS MANDATORY
---------------------------
On Windows 11 25H2, Defender is protected by two mechanisms :
- Tamper Protection : blocks any modification to the Defender configuration
  from a normal process, even as administrator.
- Protected Process Light (PPL) : WinDefend and WdFilter services run as
  protected processes, which cannot be terminated by Task Manager or
  PowerShell in normal mode.

In Safe Mode, Tamper Protection is inactive and the minifilter drivers
(WdFilter) do not load. Registry modification then becomes possible.


SERVICES AFFECTED
-----------------
The script disables these six services by setting their "Start" value to 4
(disabled) in the registry :

  WinDefend    Main Defender service (AV engine)               default : 3
  Sense        Microsoft Defender for Endpoint (EDR telemetry) default : 3
  WdFilter     Minifilter driver -- hooks into the I/O stack    default : 0
  WdNisDrv     Network inspection driver                        default : 3
  WdNisSvc     Network inspection service                       default : 3
  WdBoot       Early launch anti-malware driver (ELAM)          default : 0

WdFilter is particularly impactful : as a minifilter, it intercepts all
file system operations (IRP_MJ_CREATE, IRP_MJ_READ, etc.) through the
Filter Manager (fltmgr.sys). Disabling it removes this interception point
from the I/O stack.
