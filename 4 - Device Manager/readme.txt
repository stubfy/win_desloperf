4 - DEVICE MANAGER
Unused device cleanup
=====================


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
For disabled devices : right-click > Enable device.
