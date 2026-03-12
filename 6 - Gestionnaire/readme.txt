8 - DEVICE MANAGER
USB power saving and unused device cleanup
==========================================

PROCEDURE -- USB POWER SAVING
------------------------------
1. Open Device Manager (Gestionnaire.lnk shortcut)
2. For each device listed below :
   - Right-click > Properties > "Power Management" tab
   - Uncheck "Allow the computer to turn off this device to save power"
   - OK

Devices to process :
  Keyboards
    > HID Keyboard / USB Keyboard

  Universal Serial Bus controllers
    > USB Controller (all entries in the list)

  Human Interface Devices (HID)
    > All HID devices listed

  Mice and other pointing devices
    > HID Mouse / USB Mouse


PROCEDURE -- DISABLING UNUSED DEVICES
--------------------------------------
The following devices can be disabled if not in use, to remove their
associated DPCs and interrupts.

  Audio, video and game controllers :
    > Disable anything unused (secondary sound cards,
      disconnected game controllers)

  System devices :
    > High Definition Audio Controller (if USB audio or a dedicated
      PCI sound card is used instead)
    > Intel Management Engine Interface (if remote management not needed)
    > Remote Desktop Device Redirector Bus
    > Microsoft Virtual Drive Enumerator
    > Microsoft Hyper-V Virtualization Infrastructure Driver

  Software devices :
    > Microsoft Root Enum
    > Microsoft GS Wavetable Synth (if MIDI audio not in use)

Caution : only disable devices you are certain you do not need. When in
doubt, leave them alone -- they can always be re-enabled via
View > Show hidden devices.


ROLLBACK
--------
"Power Management" tab : re-check the box.
For disabled devices : right-click > Enable device.


WHAT IT DOES
------------
Windows automatically cuts power to USB devices (keyboard, mouse, hubs)
after a period of inactivity to save energy. This behavior can cause brief
input dropouts or a noticeable wake-up delay on gaming peripherals.

This folder contains a shortcut to Device Manager and instructions for
disabling this power management at the individual device level.


DISTINCTION FROM THE AUTOMATED SCRIPT
--------------------------------------
The 11_usb.ps1 script (run by run_all.bat) disables USB selective suspend
at the power plan level via powercfg. This acts on the global USB bus
policy but not on individual device nodes.

The manual procedure above acts at the DevNode level for each device :
it disables the DEVPROP AllowIdleIrpInD3 property on the specific node,
which prevents the USB hub driver from sending suspend commands to that
particular device. The two actions are complementary.
