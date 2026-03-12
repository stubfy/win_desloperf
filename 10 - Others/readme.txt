11 - OTHERS
Miscellaneous complementary tools
===================================

This folder groups utility tools that do not fit into the other categories
but remain useful for monitoring and system maintenance after optimization.


AUTORUNS (Sysinternals)
------------------------
A Microsoft Sysinternals tool that exhaustively lists all automatic startup
points on a Windows system.

What it covers :
  - Run / RunOnce keys in HKLM and HKCU
  - System services (HKLM\SYSTEM\CurrentControlSet\Services)
  - Boot drivers
  - Scheduled tasks (Task Scheduler)
  - AppInit_DLLs (DLLs injected into all processes)
  - Browser Helper Objects (browser extensions)
  - LSA Authentication Packages
  - Winlogon Notify packages
  - Boot Execute entries

Usage :
  Open Autoruns\Autoruns64.exe as administrator. Unchecking an entry
  disables it without deleting it. The "Publisher" column shows the
  code signer -- any unsigned entry or unknown publisher warrants
  investigation. Menu Options > Scan Options > Check VirusTotal.com
  allows verifying executables against the VirusTotal database.


DEVICECLEANUP
--------------
Removes ghost device entries (disconnected devices) from Device Manager
and the Windows registry.

What it covers :
  Disconnected devices retain their entries in :
    HKLM\SYSTEM\CurrentControlSet\Enum
  with the ConfigFlags flag containing bit 0x1 (CONFIGFLAG_REINSTALL).
  DeviceCleanup calls CM_Get_DevNode_Status for each node in the
  DeviceTree, identifies those whose state is DN_WILL_BE_REMOVED or
  physically absent, then calls SetupDiRemoveDevice to cleanly remove them.

Usage :
  Open deviceCleanup\DeviceCleanup.exe as administrator. The list shows
  all disconnected devices. Select all (Ctrl+A) and delete, or filter by
  type before deleting.

Note : after disabling devices in Device Manager (see folder 8), run
DeviceCleanup to clean up residual entries.


TEMP FOLDERS
-------------
Shortcuts to Windows temporary file folders :
  Fichiers temp 1 : %TEMP% (current user's temporary folder)
  Fichiers temp 2 : %WINDIR%\Temp (system temporary folder)

Delete the contents of these folders periodically to free disk space.
Ignore "file in use" errors -- those files are held by active processes
and cannot be deleted during the current session.


NVIDIA SHARPNESS FILTERS
-------------------------
Contains alternative .reg files for the NIS filter (legacy registry path
used by older NVIDIA drivers).
These files are superseded by those in folder 7 - NVInspector which target
the correct path for modern drivers.
Do not apply these if the .reg files from folder 7 have already been used.
