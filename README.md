# win_deslopper

![Version](https://img.shields.io/badge/version-0.8-blue)
![Windows](https://img.shields.io/badge/Windows_11-25H2-0078D4?logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell)
![License](https://img.shields.io/badge/license-MIT-green)

> Windows 11 25H2 optimization pack - debloat, system tweaks, input latency reduction.

**Target** : Gaming PC running Windows 11 25H2

---

## Table of Contents

- [What it does](#what-it-does)
- [Fresh install example](#fresh-install-example)
- [Quick start](#quick-start)
- [Automated phase](#automated-phase)
- [Manual phase](#manual-phase)
- [Rollback](#rollback)
- [Project structure](#project-structure)
- [Warnings](#warnings)
- [About](#about)

---

## What it does

win_deslopper applies a set of system tweaks to improve performance on Windows 11 25H2. The pack covers:

- **Input latency**: timer resolution (~0.5 ms), MSI interrupts, GPU IRQ affinity, mouse acceleration fix
- **System fluidity**: power throttling disabled, MMCSS high priority, USB selective suspend disabled
- **Debloat**: UWP app removal, service startup cleanup, Recall/AI 25H2 disabled
- **Privacy**: 240 OOSU10 tweaks, DiagTrack, Cortana, widgets, Copilot disabled
- **Boot**: dynamic tick disabled, legacy boot menu
- **Network**: Cloudflare DNS, network throttling disabled, NIC offloads
- **Windows Update**: configurable profile: Maximum / Security only / Disabled
- **Personal shell/UI**: a dedicated script groups subjective theme/taskbar/Explorer preferences separately

Everything scriptable is automated in a single pass. The remaining manual folders are guided by their local `readme.txt` files.

---

## Fresh install example

Quick visual example on a fresh Windows 11 25H2 install, using Task Manager at idle. This is meant as an illustration of background cleanup, not a benchmark.

| Before | After |
|--------|-------|
| ![Fresh Windows 11 install before the tweaks](assets/readme/fresh-install-before.png) | ![Fresh Windows 11 install after the tweaks](assets/readme/fresh-install-after.png) |
| Stock fresh install: around 133 processes, with visible background disk activity. | After the tweaks: around 65 processes, with much lighter background activity. |

---

## Quick start

> **Requirements** : Windows 11 25H2, administrator rights.

**1. Run the automated tweaks**

```
1 - Automated/run_all.bat   (double-click, UAC prompt is automatic)
```

You will be prompted for a few options before anything runs:
- **Windows Update profile** (Maximum / Security only / Disabled), default: Security only
- **Uninstall Edge + WebView2 Runtime** (optional, best-effort), default: Yes
- **Uninstall OneDrive** (optional), default: Yes
- **Disable Windows Firewall profiles** (optional), default: Yes

Estimated duration: 5 to 15 minutes. A reboot prompt is shown at the end.
If you choose `[S]` there, the pack triggers the same flow as `2 - Windows Defender/run_defender.bat`: Safe Mode is configured and `Disable Defender and Return to Normal Mode.bat` is created on the Desktop for the Defender step.

**2. Reboot**

**3. Follow the manual steps in order (`2 - Windows Defender/run_defender.bat` if you did not choose `[S]`, then folders 3 to 7, then `Tools/`)**

The manual folders still contain a `readme.txt` with detailed instructions.

---

## Automated phase

`run_all.bat` self-elevates via UAC and calls `scripts/run_all.ps1`, which runs the following scripts in sequence:

| Script | Purpose |
|--------|---------|
| `01_backup.ps1` | Windows restore point + service/registry state export |
| `02_registry.ps1` | Consolidated, deduplicated registry tweaks |
| `03_services.ps1` | Service startup alignment (reference main PC) |
| `04_bcdedit.ps1` | Boot configuration (dynamictick, legacy menu) |
| `05_power.ps1` | Ultimate Performance power plan + Bitsum values |
| `06_dns.ps1` | Cloudflare DNS (1.1.1.1 / 1.0.0.1) |
| `07_edge.ps1` | Microsoft Edge policies |
| `08_debloat.ps1` | UWP app removal (Teams, Microsoft 365, Family, Quick Assist, Sticky Notes...) |
| `09_oosu10.ps1` | O&O ShutUp10++ silent mode (240 tweaks) |
| `10_timer.ps1` | SetTimerResolution at startup (~0.5 ms), installs VC++ x64 runtime if missing |
| `11_usb.ps1` | USB selective suspend disabled |
| `12_ai_disable.ps1` | Recall, AI, Copilot disabled (25H2) |
| `13_telemetry_tasks.ps1` | Telemetry scheduled tasks + PS7 + Brave |
| `14_network_tweaks.ps1` | Teredo disabled |
| `15_windows_update.ps1` | Windows Update profile (Maximum / Security / Disabled) |
| `18_firewall.ps1` | Windows Firewall profiles disabled |
| `16_uwt.ps1` | UWT-equivalent tweaks (privacy, context menu, visual effects) |
| `20_personal_settings.ps1` | Personal shell/theme preferences (dark mode, accents, taskbar clock seconds, Explorer presentation) |
| `17_mouse_accel.ps1` | MarkC mouse acceleration fix (auto-detects DPI scaling) |

The Defender step is manual again and lives in `2 - Windows Defender/`. If you choose `[S]` at the final reboot prompt, `run_all.ps1` simply prepares that manual step for you by configuring Safe Mode and creating the Desktop helper automatically.

### Windows Update profiles

`15_windows_update.ps1` can also be run standalone at any time:

```powershell
.\15_windows_update.ps1 -Profil 1   # Maximum - all updates
.\15_windows_update.ps1 -Profil 2   # Security only - no feature updates, no drivers via WU
.\15_windows_update.ps1 -Profil 3   # Disable - completely disable WU (services + policies)
.\15_windows_update.ps1             # Interactive menu
```

### Registry tweaks applied

- GameDVR / GameBar disabled
- MMCSS: GPU Priority 8, Priority 6, Scheduling Category High
- Power throttling disabled (`PowerThrottlingOff=1`)
- Network throttling disabled (`NetworkThrottlingIndex=0xFFFFFFFF`, `SystemResponsiveness=0`)
- VBS/HVCI disabled (`EnableVirtualizationBasedSecurity=0`)
- Global timer resolution (`GlobalTimerResolutionRequests=1`)
- `SvcHostSplitThresholdInKB=33554432` to reduce `svchost` splitting
- WaitToKillServiceTimeout reduced (2000 ms)
- Prefetch disabled
- File extensions visible
- MarkC mouse acceleration fix (auto-detects DPI scaling)
- Hibernate disabled
- Keyboard: delay 0, max repeat rate
- HDCP disabled (NVIDIA)
- Classic context menu (Windows 11)
- Widgets / News disabled
- Personal shell/theme tweaks are applied separately in `20_personal_settings.ps1` (dark mode, black accent, taskbar seconds, classic Alt+Tab, Explorer presentation)

### Service startup tweaks

`03_services.ps1` now aligns startup types to the reference main PC instead of forcing an almost-all-`Manual` policy.

In practice, a noisy core is forced back to `Disabled` (`SysMain`, `DPS`, `Spooler`, `DiagTrack`, `WSearch`, `RmSvc`, `WerSvc`, `PhoneSvc`, `SharedAccess`, `MapsBroker`, `RemoteRegistry`, smart card services, etc.), most secondary services stay `Manual`, some services remain `Automatic` on purpose (`wuauserv`, `W32Time`, `TermService`, `DeviceAssociationService`, `IKEEXT`, `InstallService`, `StiSvc`, `VaultSvc`), and `UsoSvc` is set to `AutomaticDelayedStart`.

`DoSvc` is aligned to the main PC as `Manual` with `TriggerInfo` removed.

### Logging

All executions are logged to:

```
%APPDATA%\win_deslopper\logs\win_deslopper.log
```

The log includes: pack version, timestamp, OS info, machine name, full output of each script, detailed errors with stack traces.

If the Microsoft Visual C++ x64 runtime required by `SetTimerResolution.exe` and `MeasureSleep.exe` is missing, `10_timer.ps1` downloads the official Microsoft redistributable and installs it silently before enabling the timer tool.

---

## Manual phase

To be done in order after rebooting. The Defender step is back in its own manual folder at the pack root.

| Step | Path | Why manual | Risk level |
|------|------|-----------|------------|
| 1 | **2 - Windows Defender/run_defender.bat** | Requires Safe Mode; PPL and Tamper Protection block full disable in normal mode | High |
| 2 | **3 - MSI Utils** | Manual identification of compatible devices required | Moderate |
| 3 | **4 - NVInspector** | Per-game NVIDIA driver profiles, user-specific | Low |
| 4 | **5 - Device Manager** | USB power saving per device node, not cleanly scriptable | Low |
| 5 | **6 - Interrupt Affinity** | GPU PCI bridge identification required | Moderate |
| 6 | **7 - Network WIP** | NIC settings depend on adapter model | Moderate |
| 7 | **Tools** | Complementary tools (Autoruns, temp folders) | Low |

---

## Rollback

```
1 - Automated/restore_all.bat   (double-click, UAC prompt is automatic)
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
- Windows Firewall profiles (restored to saved state or Windows default)
- Personal shell/theme settings (restored to Windows defaults)
- Optional reinstall prompt for Microsoft Edge + WebView2 Runtime / OneDrive

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
│   │   ├── 01_backup.ps1 ... 20_*   Scripts by category
│   │   ├── opt_*.ps1                 Optional (Edge/WebView2, OneDrive removal)
│   ├── restore/                      Symmetric rollback scripts
│   ├── tools/                        Third-party tools
│   │   ├── OOSU10.exe
│   │   ├── ooshutup10.cfg
│   │   └── SetTimerResolution.exe
│   └── backup/                       Created at first run (gitignored)
│
├── 2 - Windows Defender/
│   ├── run_defender.bat             Manual Safe Mode entry point
│   ├── run_defender.ps1             Safe Mode launcher + Desktop helper creation
│   ├── 1 - DisableDefender.ps1      Safe Mode Defender disable script
│   └── readme.txt
│
├── 3 - MSI Utils/
├── 4 - NVInspector/
├── 5 - Gestionnaire/
├── 6 - Interrupt Affinity/
├── 7 - Network WIP/
└── Tools/
    └── MeasureSleep.exe
```

---

## Warnings

> This pack makes deep system-level changes. Using it on a production or primary machine carries risks. A full backup is created before any modification.

| | Risk |
|-|------|
| **Defender disabled** | No real-time antivirus protection. On 25H2, Tamper Protection may block disabling even in Safe Mode. |
| **Edge / WebView2 uninstall** | Uses the current WinUtil-style dummy-file flow for Edge, then tries to remove the WebView2 Runtime. On Windows 11 or with apps that depend on WebView2, the runtime can come back later. |
| **VBS/HVCI disabled** | Credential Guard and certain memory protections are off. Significant performance gain, notable security trade-off. |
| **MSI Utils** | Do not enable MSI on audio controllers, capture cards (ELGATO) or legacy USB - BSOD risk. |
| **Interrupt Affinity** | Wrong pinning can increase latency instead of reducing it. Identify the correct PCI bridge before any change. |
| **Service startup tweaks** | Services touched by `03_services.ps1` are aligned to the reference main PC. The noisiest services are disabled again, most secondary ones stay manual, and `BITS` / `UsoSvc` / `wuauserv` can still be adjusted later by the chosen Windows Update profile. |
| **WU Disabled profile** | No security patches, only use on isolated gaming machines. |
| **Firewall disabled** | No Windows firewall filtering. Use only if another firewall or isolated setup covers the machine. |
| **SetTimerResolution** | After enabling `SetTimerResolution`, verify with `Tools/MeasureSleep.exe` run as administrator that the timer resolution is `5200`. If it is not `5200`, another program is forcing it to `5000`, and you need to find that process manually. Known culprits include VoiceMeeter Macro Buttons below v1.1.3.1, which forces 0.50 ms via `NtSetTimerResolution`; update it to v1.1.3.1+ (available on the VB-Audio Discord). Recent VoiceMeeter builds themselves should no longer force the timer resolution, so a registry fix is normally not needed. If VoiceMeeter still appears to be involved on your system, a known fallback fix exists: set `TimerResolution=1` (DWORD) at `HKCU\VB-Audio\VoiceMeeter`. OpenRGB is another known conflict because it holds a 0.50 ms timer resolution request for as long as it is running; close it after configuring your LED profiles. |

---

## About

win_deslopper is a personal collection of Windows tweaks accumulated over the years from various sources: community guides, benchmarks, forum threads, YouTube channels, and hands-on testing. The goal is to centralize what actually makes a difference and make it as straightforward as possible to apply.

Some of these are simply options that should be on by default: showing file extensions, disabling GameDVR when you never use it, turning off mouse acceleration, cleaning up the right-click menu. Others go further into performance and privacy territory.

The automated script system and git history were built and managed with the help of AI coding tools, mainly Claude Code and Codex. The tweak selection, what to include or exclude, and the overall direction are entirely manual; the AI handled the scripting infrastructure (orchestration, rollback, logging) and repository management.

**Tested on** : Intel / AMD CPU - NVIDIA GPU. Results on other hardware configurations may vary.

---

## License

MIT
