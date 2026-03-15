TOOLS
Miscellaneous complementary tools
===================================

This folder groups utility tools that do not fit into the other categories
but remain useful for monitoring and system maintenance after optimization.


MEASURESLEEP
-------------
Use `MeasureSleep.exe` as administrator to verify the actual system timer resolution after
`SetTimerResolution.exe` is enabled.

Target value:
  - around `5200` when the requested 0.52 ms timer resolution is active

If Windows reports a missing `VCRUNTIME140*.dll` or `MSVCP140.dll`, install
the Microsoft Visual C++ 2015-2022 x64 runtime. `1 - Automated/scripts/10_timer.ps1`
already installs it automatically when required.


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


TEMP FOLDERS
-------------
Shortcuts to Windows temporary file folders :
  Fichiers temp 1 : %TEMP% (current user's temporary folder)
  Fichiers temp 2 : %WINDIR%\Temp (system temporary folder)

Delete the contents of these folders periodically to free disk space.
Ignore "file in use" errors -- those files are held by active processes
and cannot be deleted during the current session.

