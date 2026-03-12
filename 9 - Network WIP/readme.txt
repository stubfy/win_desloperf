10 - NETWORK WIP
Advanced NIC optimization
===========================

PROCEDURE -- DEVICE MANAGER
----------------------------
1. Open Device Manager
2. Network adapters > right-click on the adapter > Properties
3. "Advanced" tab -- apply the following values :

  ARP Offload                    : Disabled
  DMA Coalescing                 : Disabled
  Enable PME                     : Disabled
  Energy Efficient Ethernet      : Disabled
  Flow Control                   : Disabled
  Interrupt Moderation           : Disabled
  Interrupt Moderation Rate      : Off
  IPv4 Checksum Offload          : Enabled (Rx & Tx)
  Large Send Offload V2 (IPv4)   : Disabled
  Large Send Offload V2 (IPv6)   : Disabled
  Log Link State Event           : Disabled
  NS Offload                     : Disabled
  Packet Priority & VLAN         : Disabled
  Receive Buffers                : 2048
  Selective Suspend              : Disabled
  Selective Suspend Idle Timeout : 5
  Speed & Duplex                 : Select the speed matching your router's
                                   Ethernet port (avoid Auto-Negotiation
                                   if possible)
  TCP Checksum Offload IPv4      : Rx & Tx Enabled
  TCP Checksum Offload IPv6      : Rx & Tx Enabled
  Transmit Buffers               : 2048
  UDP Checksum Offload IPv4      : Rx & Tx Enabled
  UDP Checksum Offload IPv6      : Rx & Tx Enabled
  Wait for Link                  : Off
  Wake from S0ix on Magic Packet : Disabled
  Wake on Link Settings          : Disabled
  Wake on Magic Packet           : Disabled
  Wake on Pattern Match          : Disabled

4. "Power Management" tab :
   Uncheck "Allow the computer to turn off this device to save power"


PROCEDURE -- TCP OPTIMIZER
---------------------------
1. Open TCPOptimizer.exe as administrator
2. Apply the settings from the Export.spg profile in this folder
   (File > Load Settings > select Export.spg)
3. Adjust MTU according to your ISP
   (typically 1500 for standard Ethernet, 1492 for PPPoE)
4. Click "Apply Changes" and reboot

The FirstBackup.spg profile contains the original TCP values recorded
on first use -- apply it to restore default TCP settings.


ROLLBACK
--------
NIC "Advanced" tab : click "Restore Defaults" if available, otherwise
revert each value manually.
TCP : apply FirstBackup.spg in TCP Optimizer.


WHAT IT DOES
------------
Disables NIC features designed for servers and multi-connection environments,
which introduce batching and additional latency on a gaming PC with a single
active connection.

Also includes TCP Optimizer (third-party tool) to tune Windows TCP/IP stack
parameters.


TECHNICAL DETAIL
----------------
NIC offloads move TCP/IP processing to the card firmware to reduce CPU load
on servers. On a gaming PC :

- Large Send Offload (LSO) : batches multiple outgoing TCP packets into
  a single segment before sending. Reduces interrupts but increases
  per-packet latency.

- Interrupt Moderation : batches multiple NIC interrupts into one before
  raising them to the CPU. Very useful at 10 Gbps, harmful in gaming
  (extra delay between packet reception and processing).

- Receive/Transmit Buffers : size of the DMA ring buffer between the NIC
  and system memory. At 2048, packet drops under load are avoided while
  buffer fill latency is kept low.

- Flow Control (PAUSE frames) : throughput regulation mechanism between
  the NIC and the switch. Can introduce artificial pauses.

- Energy Efficient Ethernet (EEE) : puts the transceiver to sleep during
  low-activity periods. Causes latency spikes on wake-up.

The settings above target the Intel I226-V specifically. Exact parameter
names may vary depending on the installed network card.
