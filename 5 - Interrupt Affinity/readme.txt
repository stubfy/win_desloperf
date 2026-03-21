5 - INTERRUPT AFFINITY
Pinning GPU interrupts to a dedicated CPU core
===============================================


AUTOMATED USAGE
---------------
Run set_affinity.bat as administrator.

The script automatically:
  1. Detects the discrete GPU (prefers NVIDIA > AMD > first PCI display device)
  2. Walks the PCI chain: GPU -> PCI Bridge -> PCI Root Complex
  3. Pins interrupts for all three devices to core 2
  4. Logs each device with its full InstanceId and result

Output example (Intel -- 3 devices):
  [OK]  [1] GPU            -> core 2  DevicePolicy=4  AssignmentSetOverride=04 00 00 00
  [OK]  [2] PCI Bridge     -> core 2  DevicePolicy=4  AssignmentSetOverride=04 00 00 00
  [OK]  [3] Root Complex   -> core 2  DevicePolicy=4  AssignmentSetOverride=04 00 00 00

Output example (AMD -- 2 devices, Root Complex is ACPI):
  [NOTE] Root Complex is ACPI (ACPI\PNP0A08\0) -- normal on AMD.
         Applying GPU + PCI Bridge only (sufficient for IRQ pinning).
  [OK]  [1] GPU            -> core 2  DevicePolicy=4  AssignmentSetOverride=04 00 00 00
  [OK]  [2] PCI Bridge     -> core 2  DevicePolicy=4  AssignmentSetOverride=04 00 00 00

On AMD platforms, the PCI Express Root Complex is exposed as an ACPI device
(ACPI\PNP0A08) rather than a PCI device in the Windows PnP tree. This is
normal. Pinning GPU + PCI Bridge is sufficient: the Bridge is the device
that schedules DPCs toward the target core.

A reboot is required for the setting to take effect.

NVIDIA NOTE: NVIDIA drivers reset interrupt affinity on each driver update.
Re-run set_affinity.bat after every NVIDIA driver update.


ROLLBACK
--------
Run restore_affinity.bat as administrator.

The script reads backup\affinity_state.json (saved by backup.ps1 before
any tweaks ran) and restores each device to its original state:
  - If the Affinity Policy key did not exist before: deletes it (Windows default)
  - If the Affinity Policy key existed before: restores the original values

If no backup is found, the Affinity Policy keys are deleted for all devices
in the current GPU chain, which is equivalent to the Windows default.

A reboot is required after restore.


WHAT IT DOES
------------
By default, Windows distributes hardware interrupts (IRQs) across all
logical cores of the processor. GPU-generated interrupts may therefore land
on cores already busy with game threads, creating contention and increasing
latency variance (jitter).

This setting pins GPU interrupts to a specific, dedicated CPU core,
physically separating GPU IRQ processing from the main render thread.


TECHNICAL DETAIL
----------------
GPU interrupts travel through the chain:
  GPU -> PCI-PCI Bridge -> PCI Root Complex -> APIC -> CPU

The set_affinity.ps1 script writes an affinity policy to the registry:

  HKLM\SYSTEM\CurrentControlSet\Enum\PCI\<DeviceID>\<InstanceID>\
    Device Parameters\Interrupt Management\Affinity Policy\
      DevicePolicy          = 4  (IrqPolicySpecifiedProcessors)
      AssignmentSetOverride = <bitmask of target core, little-endian KAFFINITY>

DevicePolicy=4 instructs the driver to route DPCs to the core specified
by the bitmask. Core 2 = KAFFINITY 0x0000000000000004 (byte: 04 00 00 00).

Core 2 is recommended because it avoids core 0 (used by the OS and system
interrupts) and stays on a separate physical core in the presence of
Hyper-Threading (logical core 1 = HT pair of physical core 0).


MANUAL PROCEDURE (fallback - use intPolicy_x64.exe)
----------------------------------------------------
STEP 1 -- Identify the GPU's PCI bridge

1. Open Device Manager (`Device Manager.lnk` shortcut)
2. Menu View > Devices by connection
3. Locate the graphics card in the connection tree
4. Identify the "PCI to PCI Bridge" immediately above the GPU
5. Right-click on this bridge > Properties > Details
6. Select "Physical device object name" from the dropdown
7. Note the value (e.g. \Device\NTPNP_PCI0010)

STEP 2 -- Configure affinity

1. Open intPolicy_x64.exe as administrator
2. In the list, locate:
   - The graphics card (GPU)
   - The associated PCI bridge (PCI to PCI Bridge identified above)
   - The PCI root complex (PCI Express Root Complex)
3. For each of these three items, set the affinity to CPU 2
4. Apply and reboot

Manual rollback: intPolicy_x64.exe > select each modified device >
choose "Default" as affinity policy > apply > reboot.


RISK
----
A wrong core choice or wrong device selection can increase latency instead
of reducing it. The automated script uses the same heuristic as common
community tools (NVIDIA > AMD > first PCI, then PCI chain walk). Verify
the detected chain in the script output before rebooting.
