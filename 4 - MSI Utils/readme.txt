5 - MSI UTILS
Enabling MSI interrupts on hardware devices
============================================

PROCEDURE
---------
1. Launch PCIutil.exe as administrator, then close it immediately
   This is required before running MSI_util_v3.exe.

   Why : PCIutil.exe installs a kernel-mode driver in the background
   (similar to WinIo / WinRing0) that opens direct read/write access to
   the PCI configuration space. The driver stays loaded in memory even
   after the app is closed. MSI_util_v3.exe depends on this driver to
   enumerate all PCI devices and modify their MSI registers. Without it,
   it can only see devices exposed by the standard Windows API (setupAPI /
   WMI), which does not cover every device on the bus.

2. Open MSI_util_v3.exe as administrator
3. Identify the target devices in the list
4. For each compatible device, click the MSI column
   and select "MSI" (or "MSI-X" if available)
5. Apply and reboot
6. After rebooting, verify devices work correctly (audio, network, USB)

In case of BSOD on reboot : start in Safe Mode and disable MSI mode
on the last device that was modified.


ROLLBACK
--------
Open MSI_util_v3.exe as administrator, set each device back to
"Line Based" (INTx) mode, reboot.


WHAT IT DOES
------------
Enables MSI (Message Signaled Interrupts) mode on the main PC components.
In MSI mode, devices communicate with the processor through direct memory
writes rather than shared electrical signals, which reduces interrupt
processing latency and eliminates IRQ conflicts.

The practical impact : fewer stacked DPCs (Deferred Procedure Calls),
more stable frametime, more consistent input latency.


TECHNICAL DETAIL
----------------
By default, PCI/PCIe devices use INTx mode (line-based interrupts). In this
mode, multiple devices can share the same interrupt line (IRQ sharing),
which forces the processor to poll each device to find which one triggered
the interrupt.

In MSI mode (Message Signaled Interrupts, defined in the PCIe spec), the
device sends a memory write directly to the APIC (Advanced Programmable
Interrupt Controller) target address. This :
- Eliminates IRQ sharing (each device gets a unique vector)
- Reduces DPC latency (less waiting in the interrupt queue)
- Enables MSI-X : up to 2048 vectors per device, one per CPU queue

The tools provided (PCIutil.exe and MSI_util_v3.exe) read the MSI state
of each device and allow enabling or disabling it.


DEVICES TO ENABLE
-----------------
Compatible and recommended :
  - Graphics card (GPU)
  - Ethernet NIC
  - Wi-Fi card
  - NVMe controller (NVMe SSD)
  - Recent AHCI SATA controllers (SATA SSDs and drives)
  - Intel, AMD or ASMedia USB controllers
  - AMD PSP / Intel Management Engine

Use with caution (avoid if unsure) :
  - PCI to PCI Bridge
  - Intel PCIe Controller (x16)
  - Intel PCI Express Root Port / PCI Express Root Port


DO NOT ENABLE -- BSOD RISK
---------------------------
  - ELGATO capture cards
  - High Definition Audio controller (integrated audio driver)
  - Soundblaster, ASUS Xonar, Creative sound cards
  - Legacy USB 1.0 / 1.1 / 2.0 controllers (PCs older than 10 years)

Note : if MSI mode is already active on a USB controller, the driver
supports it natively -- do not change anything in that case.
