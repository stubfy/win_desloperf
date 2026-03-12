4 - CONTROL PANEL
Manual settings via the Windows interface
==========================================

SETTINGS TO APPLY
-----------------

0 - GPU Scheduler (ms-settings:display-advancedgraphics)
    Enable "Hardware-accelerated GPU scheduling" (HAGS).
    Reduces input latency on NVIDIA GTX 1000+ and AMD RX 5000+ GPUs
    by letting the GPU manage its own buffer scheduling.
    Technical : enables HwSchMode=2 in HKLM\SYSTEM\CurrentControlSet\
    Control\GraphicsDrivers, handing frame scheduling to the GPU driver
    instead of the Windows scheduler.

1 - Notifications (ms-settings:notifications)
    Disable "Do not disturb", disable "Focus", Additional settings tab :
    uncheck everything.
    Prevents interruptions during gameplay and removes the DPCs
    associated with notification toast rendering.

2 - Storage (ms-settings:storagesense)
    Disable automatic cleanup (Storage Sense).
    Avoids background disk accesses during gaming sessions.

3 - Colors (ms-settings:colors)
    Dark mode, disable transparency, black accent color, disable accent
    on taskbar, enable accent on title bars.
    Transparency (DWM blur) uses GPU resources ; disabling it reduces
    the desktop graphics load.

4 - Installed apps (ms-settings:appsfeatures)
    Remove any pre-installed applications still present
    (those not removed automatically by script 08_debloat.ps1 because
    they vary between Windows editions).

5 - Magnifier (ms-settings:easeofaccess-magnifier)
    Disable the Windows Magnifier if not in use.

6 - Privacy (ms-settings:privacy)
    Verify that everything above "App permissions" is disabled :
    diagnostics, inking & typing, activity history, advertising, etc.

7 - Visual Effects
    Follow the provided screenshot (Effets Visuels Settings.png).
    Control Panel > System > Advanced system settings >
    Advanced > Performance > Settings.
    Choose "Adjust for best performance", then re-check only
    "Show thumbnails" and "Smooth edges of screen fonts" to maintain
    readable text.
    Disabling animations reduces DPCs from the Desktop Window Manager
    (DWM) and unnecessary interface redraws.

8 - Power options
    Select the "Ultimate Performance" plan (added by run_all.bat).
    Disable sleep.
    Technical : this plan disables deep C-states and aggressive P-state
    transitions, keeping the CPU at maximum frequency at all times to
    eliminate processor wake-up latency.

9 - Firewall
    Disable Windows Firewall if another firewall is in place,
    or keep it if it is the only active network protection.

10 - Keyboard accessibility (ms-settings:easeofaccess-keyboard)
    Disable Sticky Keys.
    Enable the Print Screen key to open the snipping tool.

11 - Taskbar (ms-settings:taskbar)
    Adjust taskbar behavior as preferred.
    Enable seconds display in the clock (at the bottom of the page).


WHAT IT DOES
------------
Some Windows settings are only accessible through the graphical interface --
either because they depend on an active user session, or because they go
through WinRT APIs not exposed on the command line, or because they modify
per-component settings (per monitor, per application) that cannot be
generalized to a single registry key.

This folder contains shortcuts to each relevant settings page.
Open each shortcut and apply the setting described above.
