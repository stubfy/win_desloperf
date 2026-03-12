WIN_DESLOPPER v0.5 -- Windows 11 25H2
Gaming optimization, debloat and quality of life
=================================================

This pack bundles tweaks and tools to improve gaming performance
(input latency, frametime, system fluidity), remove Microsoft bloatware
and fix Windows default behaviors that are unfavorable to gaming.

Target : Windows 11 25H2


USAGE ORDER
-----------

STEP 1 -- Run the automated tweaks
  Open "1 - Automated\" as administrator and run run_all.bat.
  The script applies all scriptable tweaks in a single pass, creates a
  backup of the initial state and prompts for a reboot at the end.
  Estimated duration : 5 to 15 minutes depending on configuration.

STEP 2 -- Reboot (prompted by run_all.bat)

STEP 3 -- Complete the manual steps in folder order :

  2 - Windows Defender     Disable Defender in Safe Mode (required)
  3 - Control Panel        Windows graphical interface settings
  4 - MSI Utils            Enable MSI interrupts on GPU / NIC / NVMe
  5 - Mouse Accel fix      Fix mouse acceleration curve (if scaling != 100%)
  6 - NVInspector          Per-game NVIDIA driver profiles
  7 - Gestionnaire         Disable USB power saving (keyboard, mouse)
  8 - Interrupt Affinity   Pin GPU IRQs to a dedicated CPU core
  9 - Network WIP          Advanced NIC settings (offloads, buffers)
  10 - Others              Complementary tools (Autoruns, DeviceCleanup, temp)

Each folder contains a readme.txt with detailed instructions.


ROLLBACK
--------
Run "1 - Automated\restore_all.bat" as administrator.
Restores services, registry, DNS and boot configuration to their
original values. A reboot is required to finalize.

UWP app removals are not automatically reversible
(reinstallation available from the Microsoft Store).


CONTENTS OF 1 - AUTOMATED
-----------------------------
  run_all.bat      Main entry point (automated tweaks)
  restore_all.bat  Full rollback entry point
  scripts\         Individual scripts by category
  restore\         Corresponding restore scripts
  tools\           Third-party tools used by the scripts
                   (OOSU10.exe, SetTimerResolution.exe, MeasureSleep.exe)
  backup\          Created on first run -- backup of the initial state
