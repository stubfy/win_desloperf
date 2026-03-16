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

Tweaks for better gaming performance on Windows 11 25H2. The pack covers:

- **Input latency**: timer resolution (~0.5 ms, via optional SetTimerResolution or Process Lasso), MSI interrupts, GPU IRQ affinity, mouse acceleration fix
- **System fluidity**: power throttling disabled, MMCSS high priority, USB selective suspend disabled
- **Debloat**: UWP app removal, service startup cleanup, Recall/AI 25H2 disabled
- **Privacy**: 240 OOSU10 tweaks, DiagTrack, Cortana, widgets, Copilot disabled
- **Boot**: dynamic tick disabled, legacy boot menu
- **Network**: Cloudflare DNS, network throttling disabled, NIC offloads
- **Windows Update**: configurable profile: Maximum / Security only / Disabled
- **Personal shell/UI**: a dedicated script groups subjective theme/taskbar/Explorer preferences separately

Whatever can be scripted runs in one pass. The rest is manual, each folder has its own `readme.txt`.

---

## Fresh install example

Task Manager at idle on a fresh Windows 11 25H2 install, before and after.

| Before | After |
|--------|-------|
| ![Fresh Windows 11 install before the tweaks](assets/readme/fresh-install-before.png) | ![Fresh Windows 11 install after the tweaks](assets/readme/fresh-install-after.png) |
| Fresh install, ~133 processes. | After tweaks, ~65 processes. |

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
- **Enable SetTimerResolution at startup** (optional), default: Yes. If you already use Process Lasso, you can skip it.

Estimated duration: 5 to 15 minutes. A reboot prompt is shown at the end.
If you pick `[S]`, Safe Mode gets configured and a `Disable Defender and Return to Normal Mode.bat` shortcut lands on the Desktop, same thing as running `2 - Windows Defender/run_defender.bat` yourself.

**2. Reboot**

**3. Follow the manual steps in order (`2 - Windows Defender/run_defender.bat` if you did not choose `[S]`, then folders 3 to 7, then `Tools/`)**

The manual folders still contain a `readme.txt` with detailed instructions.

---

## Automated phase

`run_all.bat` elevates itself (UAC) then runs `scripts/run_all.ps1`. Scripts executed in order:

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
| `10_timer.ps1` | Optional SetTimerResolution at startup (~0.5 ms), installs VC++ x64 runtime if missing |
| `11_usb.ps1` | USB selective suspend disabled |
| `12_ai_disable.ps1` | Recall, AI, Copilot disabled (25H2) |
| `13_telemetry_tasks.ps1` | Telemetry scheduled tasks + PS7 + Brave |
| `14_network_tweaks.ps1` | Teredo disabled |
| `15_windows_update.ps1` | Windows Update profile (Maximum / Security / Disabled) |
| `18_firewall.ps1` | Windows Firewall profiles disabled |
| `16_uwt.ps1` | UWT-equivalent tweaks (privacy, context menu, visual effects) |
| `20_personal_settings.ps1` | Personal shell/theme preferences (dark mode, accents, taskbar clock seconds, Explorer presentation) |
| `17_mouse_accel.ps1` | MarkC mouse acceleration fix (auto-detects DPI scaling) |

Defender is handled manually from `2 - Windows Defender/`. Picking `[S]` at the reboot prompt just sets up Safe Mode and drops the helper `.bat` on your Desktop so you're ready after reboot.

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

### Timer resolution options

`run_all.ps1` asks whether `SetTimerResolution` should be enabled at startup.

What to use:
- if you do not use `Process Lasso`, enable `SetTimerResolution`
- if you already use `Process Lasso` for other reasons, prefer `Process Lasso > Options > Tools > System Timer Resolution` instead of running `SetTimerResolution` separately
- do not use both for the same purpose, because that only adds a redundant background process

If you use `Process Lasso`:
1. Open `Process Lasso`.
2. Go to `Options > Tools > System Timer Resolution`.
3. Set `New Timer Resolution` to the exact value you want, for example `0.510` or `0.520`.
4. Enable `Set at every boot`.
5. Enable `Apply globally`.

After reboot, run `Tools/MeasureSleep.exe` as administrator.

A good result should look similar to this:

    Resolution: 0.5100ms, Sleep(1) slept 1.0168ms (delta: 0.0168)
    Resolution: 0.5100ms, Sleep(1) slept 1.0210ms (delta: 0.0210)
    Resolution: 0.5100ms, Sleep(1) slept 1.0156ms (delta: 0.0156)

Do not expect the exact same numbers on every line. What matters is:
- either `Process Lasso` or `SetTimerResolution` is forcing the exact timer value you selected
- if you set `0.510`, `MeasureSleep` should report about `0.5100ms`
- if you set `0.520`, `MeasureSleep` should report about `0.5200ms`
- `Sleep(1)` should stay close to `1 ms`
- `delta` should stay low, usually only a few hundredths of a millisecond

About `delta`:
- `delta` is the extra time above the requested `Sleep(1)` duration
- example: `Sleep(1) slept 1.0168ms` means the sleep overshot by `0.0168ms`
- small positive deltas are normal because scheduling is never perfectly exact
- if `delta` is consistently high, timer behavior is less clean

### Service startup tweaks

`03_services.ps1` matches the startup types from the reference main PC.
Noisy stuff like `SysMain`, `DPS`, `DiagTrack`, `WSearch` gets disabled. Most secondary services stay `Manual`. A few stay `Automatic` on purpose (`wuauserv`, `W32Time`, `TermService`, etc.). `UsoSvc` is `AutomaticDelayedStart`.
`DoSvc` is set to `Manual` with its `TriggerInfo` removed.

### Logging

All executions are logged to:

```
%APPDATA%\win_deslopper\logs\win_deslopper.log
```

The log includes: pack version, timestamp, OS info, machine name, full output of each script, detailed errors with stack traces.

`10_timer.ps1` will grab and install the VC++ x64 runtime if it's missing (needed by `SetTimerResolution.exe` and `MeasureSleep.exe`).

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

> This touches a lot of system settings. Back up your machine first. The scripts create a restore point, but have your own backup too.

| | Risk |
|-|------|
| **Defender disabled** | No real-time antivirus protection. On 25H2, Tamper Protection may block disabling even in Safe Mode. |
| **Edge / WebView2 uninstall** | Uses the current WinUtil-style dummy-file flow for Edge, then tries to remove the WebView2 Runtime. On Windows 11 or with apps that depend on WebView2, the runtime can come back later. |
| **VBS/HVCI disabled** | Credential Guard and memory protections are off. Good perf gain, but you lose some security hardening. |
| **MSI Utils** | Do not enable MSI on audio controllers, capture cards (ELGATO) or legacy USB - BSOD risk. |
| **Interrupt Affinity** | Wrong pinning can increase latency instead of reducing it. Identify the correct PCI bridge before any change. |
| **Service startup tweaks** | Startup types come from the reference main PC. Noisiest services are disabled, most stay manual. `BITS` / `UsoSvc` / `wuauserv` can still change depending on the Windows Update profile you pick. |
| **WU Disabled profile** | No security patches, only use on isolated gaming machines. |
| **Firewall disabled** | No Windows firewall filtering. Use only if another firewall or isolated setup covers the machine. |
| **Timer resolution tools** | Use either `SetTimerResolution` or `Process Lasso`, not both. After reboot, check with `Tools/MeasureSleep.exe`. Known conflicts: VoiceMeeter Macro Buttons < v1.1.3.1 (forces 0.50 ms, update it), OpenRGB (holds 0.50 ms while running, close it after setup). |

---

## About

Personal collection of Windows tweaks built up over the years, pulled from community guides, benchmarks, forums, YouTube, and a lot of trial and error. The point is to have one place with the stuff that actually works, ready to run.

Some of it is just common sense (file extensions visible, GameDVR off, no mouse acceleration). The rest goes deeper into performance, privacy, and debloat territory.

The scripts, rollback system, and repo structure were built with AI tools (Claude Code, Codex). Tweak selection and decisions are manual.

**Tested on** : Intel / AMD CPU - NVIDIA GPU. Results on other hardware configurations may vary.

---

## License

MIT
