9 - INTERRUPT AFFINITY
Pinning GPU interrupts to a dedicated CPU core
===============================================

PROCEDURE
---------
STEP 1 -- Identify the GPU's PCI bridge

1. Open Device Manager (Gestionnaire.lnk shortcut)
2. Menu View > Devices by connection
3. Locate the graphics card in the connection tree
4. Identify the "PCI to PCI Bridge" immediately above the GPU
5. Right-click on this bridge > Properties > Details
6. Select "Physical device object name" from the dropdown
7. Note the value (e.g. \Device\NTPNP_PCI0010)

STEP 2 -- Configure affinity

1. Open intPolicy_x64.exe as administrator
2. In the list, locate :
   - The graphics card (GPU)
   - The associated PCI bridge (PCI to PCI Bridge identified above)
   - The PCI root complex (PCI Express Root Complex)
3. For each of these three items, set the affinity to CPU 2
4. Apply and reboot


ROLLBACK
--------
Open intPolicy_x64.exe > select each modified device >
choose "Default" as affinity policy > apply > reboot.


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
GPU interrupts travel through the chain :
  GPU -> PCI-PCI Bridge -> PCI Root Complex -> APIC -> CPU

The intPolicy_x64.exe tool writes an affinity policy to the registry :

  HKLM\SYSTEM\CurrentControlSet\Enum\PCI\<DeviceID>\<InstanceID>\
    Device Parameters\Interrupt Management\Affinity Policy\
      DevicePolicy          = 4  (IrqPolicySpecifiedProcessors)
      AssignmentSetOverride = <bitmask of target core>

DevicePolicy=4 instructs the driver to route DPCs to the core specified
by the bitmask. For example, core 2 = bitmask 0x00000004 (bit 2).

Core 2 is recommended because it avoids core 0 (used by the OS and system
interrupts) and stays on a separate physical core in the presence of
Hyper-Threading (logical core 1 = HT pair of physical core 0).


RISK
----
A wrong core choice or wrong device selection can increase latency instead
of reducing it. Precisely identify the GPU -> PCI Bridge -> Root Complex
chain before applying this setting.
