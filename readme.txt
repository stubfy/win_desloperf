OPTI PACK -- Windows 11 25H2
Gaming optimization, debloat and quality of life
=================================================

This pack bundles tweaks and tools to improve gaming performance
(input latency, frametime, system fluidity), remove Microsoft bloatware
and fix Windows default behaviors that are unfavorable to gaming.

Target : Windows 11 25H2, gaming PC (NVIDIA GPU, Intel I226-V NIC).


USAGE ORDER
-----------

STEP 1 -- Run the automated tweaks
  Open "1 - Automatique\" as administrator and run run_all.bat.
  The script applies all scriptable tweaks in a single pass, creates a
  backup of the initial state and prompts for a reboot at the end.
  Estimated duration : 5 to 15 minutes depending on configuration.

STEP 2 -- Reboot (prompted by run_all.bat)

STEP 3 -- Complete the manual steps in folder order :

  2 - Windows Defender     Disable Defender in Safe Mode (required)
  3 - Windows Tweaker      Apply additional GUI tweaks (UWT v5)
  4 - Control Panel        Windows graphical interface settings
  5 - MSI Utils            Enable MSI interrupts on GPU / NIC / NVMe
  6 - Mouse Accel fix      Fix mouse acceleration curve (if scaling != 100%)
  7 - NVInspector          Per-game NVIDIA driver profiles
  8 - Gestionnaire         Disable USB power saving (keyboard, mouse)
  9 - Interrupt Affinity   Pin GPU IRQs to a dedicated CPU core
  10 - Network WIP         Advanced NIC settings (offloads, buffers)
  11 - Autres              Complementary tools (Autoruns, DeviceCleanup, temp)

Each folder contains a readme.txt with detailed instructions.


ROLLBACK
--------
Run "1 - Automatique\restore_all.bat" as administrator.
Restores services, registry, DNS and boot configuration to their
original values. A reboot is required to finalize.

UWP app removals are not automatically reversible
(reinstallation available from the Microsoft Store).


CONTENTS OF 1 - AUTOMATIQUE
-----------------------------
  run_all.bat      Main entry point (automated tweaks)
  restore_all.bat  Full rollback entry point
  scripts\         Individual scripts by category
  restore\         Corresponding restore scripts
  tools\           Third-party tools used by the scripts
                   (OOSU10.exe, SetTimerResolution.exe, MeasureSleep.exe)
  backup\          Created on first run -- backup of the initial state
