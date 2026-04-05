8 - USB Power
Disable USB device power management
=====================================

USAGE
-----
Run `set_usb_power.bat` as administrator.

The script disables "Allow the computer to turn off this device to save power"
and "Allow this device to wake the computer" for all connected USB and HID
devices. This prevents Windows from suspending USB peripherals, which can cause
input micro-freezes (mouse stutter, keyboard drops).

RE-RUN AFTER NEW DEVICES
-------------------------
Windows re-enables power management flags on newly plugged USB devices.
Re-run set_usb_power.bat after connecting any new USB peripheral to apply the
settings to it. The script is safe to run multiple times — it only modifies
what needs changing and never overwrites the original backup state.

This is automatically run as part of run_all.bat (Phase B).


ROLLBACK
--------
Restore runs automatically via 1 - Automated\restore_all.ps1.

The restore script reads backup\usb_power_state.json created on the first run
and restores each device to its exact original state. If no backup exists, it
removes the PnpCapabilities override on all connected USB devices.


WHAT IT DOES
------------
For each connected USB and HID device (Status = OK):
- Sets PnpCapabilities = 0x18 in the device's registry node (disables the
  power management checkboxes in Device Manager)
- Disables WakeEnabled under Device Parameters\Power
- Disables EnhancedPowerManagementEnabled, AllowIdleIrpInD3,
  SelectiveSuspendEnabled where already present

Backup file: 1 - Automated\backup\usb_power_state.json
