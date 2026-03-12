# win_deslopper

![Version](https://img.shields.io/badge/version-0.7-blue)
![Windows](https://img.shields.io/badge/Windows_11-25H2-0078D4?logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell)
![License](https://img.shields.io/badge/license-MIT-green)

> Windows 11 25H2 optimization pack — debloat, system tweaks, input latency reduction.

**Target** : Gaming PC running Windows 11 25H2

---

## Table of Contents

- [What it does](#what-it-does)
- [Quick start](#quick-start)
- [Automated phase](#automated-phase)
- [Manual phase](#manual-phase)
- [Rollback](#rollback)
- [Project structure](#project-structure)
- [Warnings](#warnings)

---

## What it does

win_deslopper applies a set of system tweaks to improve performance on Windows 11 25H2. The pack covers:

- **Input latency** — timer resolution (~0.5 ms), MSI interrupts, GPU IRQ affinity, mouse acceleration fix
- **System fluidity** — power throttling disabled, MMCSS high priority, USB selective suspend disabled
- **Debloat** — UWP app removal, telemetry service disables, Recall/AI 25H2 disabled
- **Privacy** — 240 OOSU10 tweaks, DiagTrack, Cortana, widgets, Copilot disabled
- **Boot** — dynamic tick disabled, legacy boot menu
- **Network** — Cloudflare DNS, network throttling disabled, NIC offloads
- **Windows Update** — configurable profile: Maximum / Security only / Disabled

Everything scriptable is automated in a single pass. The rest is guided by `readme.txt` files in each folder.

---

## Quick start

> **Requirements** : Windows 11 25H2, administrator rights.

**1. Run the automated tweaks**

```
1 - Automated/run_all.bat   (double-click — UAC prompt is automatic)
```

You will be prompted for a few options before anything runs:
- **Windows Update profile** (Maximum / Security only / Disabled) — default: Security only
- **Uninstall Edge** (optional)
- **Uninstall OneDrive** (optional)

Estimated duration: 5 to 15 minutes. A reboot prompt is shown at the end.

**2. Reboot**

**3. Follow the manual steps in order (folders 2 to 10)**

Each folder contains a `readme.txt` with detailed instructions.

---

## Automated phase

`run_all.bat` self-elevates via UAC and calls `scripts/run_all.ps1`, which runs the following scripts in sequence:

| Script | Purpose |
|--------|---------|
| `01_backup.ps1` | Windows restore point + service/registry state export |
| `02_registry.ps1` | Consolidated, deduplicated registry tweaks |
| `03_services.ps1` | Unnecessary service disables |
| `04_bcdedit.ps1` | Boot configuration (dynamictick, legacy menu) |
| `05_power.ps1` | Ultimate Performance power plan + Bitsum values |
| `06_dns.ps1` | Cloudflare DNS (1.1.1.1 / 1.0.0.1) |
| `07_edge.ps1` | Microsoft Edge policies |
| `08_debloat.ps1` | UWP app removal (Clipchamp, Teams, News, Copilot...) |
| `09_oosu10.ps1` | O&O ShutUp10++ silent mode (240 tweaks) |
| `10_timer.ps1` | SetTimerResolution at startup (~0.5 ms) |
| `11_usb.ps1` | USB selective suspend disabled |
| `12_ai_disable.ps1` | Recall, AI, Copilot disabled (25H2) |
| `13_telemetry_tasks.ps1` | Telemetry scheduled tasks + PS7 + Brave |
| `14_network_tweaks.ps1` | Teredo disabled |
| `15_windows_update.ps1` | Windows Update profile (Maximum / Security / Disabled) |
| `16_uwt.ps1` | UWT-equivalent tweaks (appearance, privacy, context menu) |
| `17_mouse_accel.ps1` | MarkC mouse acceleration fix (auto-detects DPI scaling) |

### Windows Update profiles

`15_windows_update.ps1` can also be run standalone at any time:

```powershell
.\15_windows_update.ps1 -Profil 1   # Maximum — all updates
.\15_windows_update.ps1 -Profil 2   # Security only — no feature updates, no drivers via WU
.\15_windows_update.ps1 -Profil 3   # Disable — completely disable WU (services + policies)
.\15_windows_update.ps1             # Interactive menu
```

### Registry tweaks applied

- GameDVR / GameBar disabled
- MMCSS: GPU Priority 8, Priority 6, Scheduling Category High
- Power throttling disabled (`PowerThrottlingOff=1`)
- Network throttling disabled (`NetworkThrottlingIndex=0xFFFFFFFF`, `SystemResponsiveness=0`)
- VBS/HVCI disabled (`EnableVirtualizationBasedSecurity=0`)
- Global timer resolution (`GlobalTimerResolutionRequests=1`)
- WaitToKillServiceTimeout reduced (2000 ms)
- Prefetch disabled
- File extensions visible
- MarkC mouse acceleration fix (auto-detects DPI scaling)
- Hibernate disabled
- Keyboard: delay 0, max repeat rate
- HDCP disabled (NVIDIA)
- Classic context menu (Windows 11)
- Widgets / News disabled

### Services disabled

`SysMain` · `DPS` · `Spooler` · `TabletInputService` · `RmSvc` · `DiagTrack` · `dmwappushservice` · `WSearch` · `DoSvc` · `WerSvc`

### Logging

All executions are logged to:

```
%APPDATA%\win_deslopper\logs\win_deslopper.log
```

The log includes: pack version, timestamp, OS info, machine name, full output of each script, detailed errors with stack traces.

---

## Manual phase

To be done in order after rebooting. Each folder contains a `readme.txt` with full instructions.

| # | Folder | Why manual | Risk level |
|---|--------|-----------|------------|
| 2 | **Windows Defender** | Requires Safe Mode — services protected by PPL in normal mode | High |
| 3 | **Control Panel** | ms-settings shortcuts — settings not exposed via CLI | Low |
| 4 | **MSI Utils** | Manual identification of compatible devices required | Moderate |
| 5 | **NVInspector** | Per-game NVIDIA driver profiles — user-specific | Low |
| 6 | **Device Manager** | USB power saving per device node — not cleanly scriptable | Low |
| 7 | **Interrupt Affinity** | GPU PCI bridge identification required | Moderate |
| 8 | **Network WIP** | NIC settings depend on adapter model | Moderate |

| 9 | **Tools** | Complementary tools (Autoruns, temp folders) | Low |

---

## Rollback

```
1 - Automated/restore_all.bat   (double-click — UAC prompt is automatic)
```

Restores in order:

- Registry (from backup created by `01_backup.ps1`)
- Services (back to default values)
- Boot configuration (bcdedit)
- DNS (back to DHCP)
- Edge policies (keys deleted)
- SetTimerResolution (startup shortcut removed)
- Power plan (back to Balanced)
- USB selective suspend (restored)
- AI/Recall keys (deleted)
- Windows Update (restored to Maximum / Windows default)

> **Limitation** : Removed UWP apps are not restored automatically. The `10_debloat_restore.ps1` script provides Store reinstall commands.

---

## Project structure

```
win_deslopper/
├── README.md
├── .gitignore
│
├── 1 - Automated/
│   ├── run_all.bat                   Main entry point
│   ├── restore_all.bat               Rollback entry point
│   ├── scripts/
│   │   ├── run_all.ps1               Main PowerShell launcher
│   │   ├── restore_all.ps1           Full rollback launcher
│   │   ├── 01_backup.ps1 ... 17_*   Scripts by category
│   │   └── opt_*.ps1                 Optional (Edge, OneDrive removal)
│   ├── restore/                      Symmetric rollback scripts
│   ├── tools/                        Third-party tools
│   │   ├── OOSU10.exe
│   │   ├── ooshutup10.cfg
│   │   ├── SetTimerResolution.exe
│   │   └── MeasureSleep.exe
│   └── backup/                       Created at first run (gitignored)
│
├── 2 - Windows Defender/
├── 3 - Control Panel/
├── 4 - MSI Utils/
├── 5 - NVInspector/
├── 6 - Gestionnaire/
├── 7 - Interrupt Affinity/
├── 8 - Network WIP/
└── Tools/
```

---

## Warnings

> This pack makes deep system-level changes. Using it on a production or primary machine carries risks. A full backup is created before any modification.

| | Risk |
|-|------|
| **Defender disabled** | No real-time antivirus protection. On 25H2, Tamper Protection may block disabling even in Safe Mode. |
| **VBS/HVCI disabled** | Credential Guard and certain memory protections are off. Significant performance gain, notable security trade-off. |
| **MSI Utils** | Do not enable MSI on audio controllers, capture cards (ELGATO) or legacy USB — BSOD risk. |
| **Interrupt Affinity** | Wrong pinning can increase latency instead of reducing it. Identify the correct PCI bridge before any change. |
| **Disabled services** | Print Spooler disabled = printing broken. DPS disabled = no system diagnostics. |
| **WU Disabled profile** | No security patches — only use on isolated gaming machines. |

---

## About

win_deslopper is a personal collection of Windows tweaks gathered from various sources — community guides, benchmarks, forum threads, and hands-on testing. The goal is to centralize what actually makes a difference and make it as straightforward as possible to apply.

Some of these are simply options that should be on by default: showing file extensions, disabling GameDVR when you never use it, turning off mouse acceleration, cleaning up the right-click menu. Others go further into performance and privacy territory.

The automated script system and git history were built and managed with the help of Claude. The tweak selection, what to include or exclude, and the overall direction are entirely manual — the AI handled the scripting infrastructure (orchestration, rollback, logging) and repository management.

**Tested on** : Intel / AMD CPU — NVIDIA GPU. Results on other hardware configurations may vary.

---

## License

MIT
