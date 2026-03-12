6 - MOUSE ACCEL FIX
Removing mouse acceleration (MarkC fix)
========================================

WHICH .REG FILE TO APPLY
-------------------------
Open Settings > System > Display and check the scale percentage shown
for your primary monitor.

  100%  -> Already applied by the automated scripts
  125%  -> Open "Windows 10 Fixes" folder > apply the 125% .reg file
  150%  -> Open "Windows 10 Fixes" folder > apply the 150% .reg file
  175%  -> Open "Windows 10 Fixes" folder > apply the 175% .reg file
  200%  -> Open "Windows 10 Fixes" folder > apply the 200% .reg file

Double-click the corresponding .reg file and confirm the merge.
A sign-out / sign-in is required for the change to take effect.


ROLLBACK
--------
Apply the Windows_10+8.x_Default.reg file at the root of this folder
to revert to the Windows default acceleration values.


WHAT IT DOES
------------
Windows applies dynamic acceleration to mouse movement by default : the
faster the mouse is moved, the greater the distance the cursor travels
relative to the actual physical movement. This behavior makes it impossible
to develop reliable muscle memory for gaming, since the same physical
movement can produce different results depending on execution speed.

This fix replaces the acceleration curves with linear values, guaranteeing
a strict 1:1 ratio between physical mouse movement and cursor movement
on screen.


TECHNICAL DETAIL
----------------
Windows calculates cursor displacement by applying two Bezier curves stored
in the registry :

  HKCU\Control Panel\Mouse
    SmoothMouseXCurve  (horizontal curve -- 40 bytes)
    SmoothMouseYCurve  (vertical curve -- 40 bytes)
    MouseSpeed         (0 = acceleration disabled, 1 or 2 = enabled)
    MouseThreshold1    (low-speed acceleration threshold)
    MouseThreshold2    (high-speed acceleration threshold)

The MarkC fix replaces these curves with linear segments calculated
specifically for each Windows display scaling level (DPI). This precision
is necessary because Windows applies an additional scaling factor to cursor
movement based on the ratio between the logical and physical screen resolution.

The automated script (02_registry.ps1 via tweaks_consolidated.reg)
already applies the fix for 100% scaling. This folder is only needed
for other scaling levels.


NOTE ON WINDOWS 11
------------------
Windows 11 22H2+ includes an "Enhanced pointer precision" toggle in
Settings > Bluetooth & devices > Mouse > Additional mouse settings.
This option is equivalent to the fix for 100% scaling, but the MarkC fix
remains more precise for other scaling levels.
