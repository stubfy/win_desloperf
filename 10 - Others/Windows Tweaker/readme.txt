3 - WINDOWS TWEAKER
Additional tweaks via Ultimate Windows Tweaker v5
==================================================

PROCEDURE
---------
1. Open this folder
2. Launch "Ultimate Windows Tweaker v 5\Ultimate Windows Tweaker 5.0.exe"
   as administrator (right-click > Run as administrator)
3. Menu File > Load Settings > select Settings.ini in this folder
4. Review the tweaks to confirm they match your needs
5. Click "Apply" to apply
6. Reboot if prompted


NOTES
-----
UWT v4.4.1 (Windows 10) is also present in this folder as an archive.
Do not use it on Windows 11 -- use UWT v5 exclusively.

If a tweak produces unexpected behavior, UWT allows undoing it individually
through the same interface by deselecting the tweak and clicking Apply.


WHAT IT DOES
------------
Ultimate Windows Tweaker (UWT) is a GUI tool that applies Windows settings
not covered by the automated scripts in the pack. It acts on HKLM and HKCU
registry keys in the Policies, Explorer, services and security categories.

The Settings.ini file provided in this folder pre-selects the tweaks
validated for a gaming PC running Windows 11 25H2.


TWEAKS COVERED BY UWT (not duplicated in the automated scripts)
----------------------------------------------------------------
The run_all.bat scripts already cover the majority of registry and service
tweaks. UWT adds the following elements that cannot be scripted cleanly :

  - Disable UAC prompts (User Account Control) -- note : reduces security
    on machines used for web browsing
  - Disable Windows Hello biometrics
  - Disable WiFi Sense (Wi-Fi password sharing with contacts)
  - A few Edge and Cortana policy keys not exposed via CLI
  - Explorer settings (system icons, window behavior)

Technically, UWT uses SetValue directly on registry keys without going
through intermediate APIs. The tweaks selected in Settings.ini have been
validated for 25H2. Tweaks that overlap with the automated scripts
(telemetry, background apps, GameDVR, Defender via policy) have been
excluded from Settings.ini to avoid conflicts.
