# win_desloperf

![Version](https://img.shields.io/badge/version-1.2-blue)
![Windows](https://img.shields.io/badge/Windows_11-25H2-0078D4?logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell)
![License](https://img.shields.io/badge/license-MIT-green)

> Windows 11 (25H2) optimization pack. Debloat both apps and AI, system tweaks for input latency reduction and overall slight better performance. Includes optional personal settings for a straightforward, consistent setup across fresh installs.

**Tested on**: Intel / AMD CPU, NVIDIA GPU. Results on other hardware configurations may vary.

---

## Table of Contents

- [What is in the pack](#what-is-in-the-pack)
- [Fresh install example](#fresh-install-example)
- [Benchmarks](#benchmarks)
- [Quick start](#quick-start)
- [Pack updates](#pack-updates)
- [Automated phase](#automated-phase)
  - [Windows Update profiles](#windows-update-profiles)
  - [Registry tweaks](#registry-tweaks-applied)
  - [Timer resolution](#timer-resolution-options)
  - [GPU interrupt affinity](#gpu-interrupt-affinity)
  - [Service startup tweaks](#service-startup-tweaks)
  - [Diff report](#diff-report)
  - [Logging](#logging)
- [Manual phase](#manual-phase)
  - [Quick reruns](#quick-reruns)
  - [MSI Utils](#msi-utils)
- [Rollback](#rollback)
- [Project structure](#project-structure)
- [Warnings](#warnings)
- [About and why](#about-and-why)

---

## What is in the pack

The pack contains tweaks for:

- **Better input latency**: by adjusting the timer resolution (via SetTimerResolution or Process Lasso), MSI interrupts, GPU IRQ affinity, mouse acceleration fix, and dynamic tick disabled in the BCD.
- **Better system fluidity**: power throttling disabled, MMCSS high priority, USB selective suspend disabled, less background activity
- **Debloat**: Microsoft app and AI removal, OEM bloatware (HP/Dell/Lenovo), pre-installed third-party apps (Spotify, Netflix, TikTok, Candy Crush, Roblox...), services (~180 services via built-in catalog)
- **Privacy**: OOSU10. DiagTrack, Cortana, widgets, Click to Do, Brave policies (if Brave is installed), and account nag notifications disabled. Start menu Recommended section hidden.
- **Network**: Cloudflare DNS (optional), network throttling disabled, TCP stack tuned (ECN, RSS, CUBIC, Nagle off), LSO off, QoS reservation removed
- **Windows Update**: configurable profile: Maximum / Security only / Disabled. Security only is often the best.
- **Personal settings**: a dedicated optional script groups subjective theme/taskbar/Explorer/Settings preferences separately

---

## Fresh install example

Here is an example of the Task Manager before and after applying the pack.
The Windows install is fresh, and the "before" screenshot was not taken on the very first boot to avoid first load software activity and produce an accurate comparison.

| Before | After |
|--------|-------|
| ![Fresh Windows 11 install before the tweaks](assets/readme/fresh-install-before.png) | ![Fresh Windows 11 install after the tweaks](assets/readme/fresh-install-after.png) |
| Fresh install, 133 processes. Lots of background activity at startup | After tweaks, 65 processes. Much cleaner startup |

---

## Benchmarks

> **Methodology and disclaimer**
>
> **Test rig**: Ryzen 7 9800X3D OC @ 5425 MHz · RTX 4090 OC @ ~2900 MHz · DDR5 6000 MHz FCLK 2000 MHz CAS 28

### Synthetic — Cinebench R23

23 400 pts → 23 681 pts **(+1.2%)**

> **Note**: The difference may be within margin of error.

| Before | After |
|--------|-------|
| ![Cinebench R23 before tweaks](assets/readme/bench/before/cinebench.png) | ![Cinebench R23 after tweaks](assets/readme/bench/after/cinebench.png) |

### Synthetic — 3DMark CPU Profile

| Test | Before | After | Delta |
|------|--------|-------|-------|
| Max threads | 10 085 | 10 375 | +2.9% |
| 8-thread | 8 519 | 9 198 | +8.0% |

| Before | After |
|--------|-------|
| ![3DMark CPU Profile before tweaks](assets/readme/bench/before/cpu.png) | ![3DMark CPU Profile after tweaks](assets/readme/bench/after/cpu.png) |

### Synthetic — 3DMark Steel Nomad

Score: 9 810 → 10 131 **(+3.3%)** · Graphics: 98.10 → 101.31 FPS **(+3.3%)**

| Before | After |
|--------|-------|
| ![3DMark Steel Nomad before tweaks](assets/readme/bench/before/gpu.png) | ![3DMark Steel Nomad after tweaks](assets/readme/bench/after/gpu.png) |

> Some gains may look small, but they meaningfully improve worst-case scenarios in games, as you can see below:

### In-game — Overwatch 2 (Gibraltar)

> **In-game runs (Overwatch 2, Gibraltar)**: same map, same POV, ~8 min game per run. Numbers shown are AVG / 1% low / 0.1% low. Ignore the current FPS value visible in screenshots (skewed by desktop returns and menus locking at 60 FPS).

| Run | AVG | 1% low | 0.1% low |
|-----|-----|--------|----------|
| VOD Before | 449 | 257 | 200 |
| VOD After | 500 | 291 | 227 |
| Vaxta Before | 383 | 284 | 251 |
| Vaxta After | 433 | 324 | 292 |

**VOD run**

| Before | After |
|--------|-------|
| ![Overwatch VOD run before tweaks](assets/readme/bench/before/vod.png) | ![Overwatch VOD run after tweaks](assets/readme/bench/after/vod.png) |

**Vaxta run**

| Before | After |
|--------|-------|
| ![Overwatch Vaxta 1min run before tweaks](assets/readme/bench/before/vaxta.png) | ![Overwatch Vaxta 1min run after tweaks](assets/readme/bench/after/vaxta.png) |

> **Note**: the after screenshot shows 2730 MHz due to a desktop return artifact captured in the frame. In actual gameplay the clock sits lower (~2625 MHz) because of an ongoing NVIDIA driver bug causing GPU downclocking in certain context. This explains slightly lower FPS compared to the VOD run on identical hardware.

---

## Quick start

**1. Run the automated tweaks**

```
1 - Automated/run_all.bat   (double-click, UAC prompt is automatic)
```

Before anything runs, `run_all.bat` shows a summary of the current optional choices.
- if `1 - Automated/backup/run_all_options.json` exists, the last validated choices are loaded, otherwise the built-in defaults are shown.
- answer **Y** to `Run like this?` to launch immediately with those optional choices
- answer **N** to review the same optional choices one by one through sequential prompts
- validated optional choices are saved back to `1 - Automated/backup/run_all_options.json` for future runs
- the core automated phases still run automatically; these are only the optional choices shown up front


| # | Choice | Default |
|---|--------|---------|
| 1 | Defender Safe Mode step (reboot into Safe Mode after run to disable Defender) | Yes |
| 2 | Windows Update profile (1 = Maximum, 2 = Security only, 3 = Disabled) | 2 |
| 3 | Uninstall Edge | Yes |
| 4 | Remove WebView2 Runtime (may break Start menu search on some machines) | No |
| 5 | Uninstall OneDrive | Yes |
| 6 | Disable Windows Firewall | Yes |
| 7 | Apply Cloudflare DNS (1.1.1.1 / 1.0.0.1) | Yes |
| 8 | Enable SetTimerResolution at startup | Yes |
| 9 | Apply personal settings (dark mode, taskbar, Explorer preferences) | Yes |
| 10 | Install NVInspector to `%APPDATA%\win_desloperf` + Desktop shortcut | Yes (NVIDIA only) |
| 11 | Pin GPU interrupt chain to core 2 | Yes |
| 12 | Apply saved MSI snapshot (`3 - MSI Utils/msi_state.json`) | — (shown only if file exists) |

The final reboot is still confirmed at the end:
- if Defender tweak is enabled, the script asks you to reboot into Safe Mode for the Defender step, default: Yes
- if Defender tweak was disabled in the menu, the script asks you for a normal reboot, default: No

**2. Reboot when prompted at the end**

**3. If you confirmed the Defender Safe Mode reboot, run the Desktop shortcut `Disable Defender and Return to Normal Mode` once Safe Mode boots.**



---

## Pack updates

To update the pack itself, just double-click:

```
update_pack.bat
```

No git, GitHub Desktop, or terminal knowledge is required.

The updater:
- reads your current local pack version
- checks the latest GitHub tag for `stubfy/win_desloperf`
- updates the pack **in place** so the folder path stays the same

---

## Automated phase

You can run the scripts you want instead of the run_all script, if you just want specific tweaks.

Scripts executed by run_all:

| Script | Purpose |
|--------|---------|
| `snapshot.ps1` | State capture: registry values, services, BCD, network, GPU affinity, saved to `backup/snapshot_latest.json` for diff comparison |
| `backup.ps1` | Windows Restore Point + service/registry/firewall/affinity state export |
| `registry.ps1` | Consolidated registry tweaks + visual effects SPI (live session) + MarkC mouse fix (auto-detects DPI scaling) |
| `services.ps1` | Many services set to Manual instead of Automatic |
| `performance.ps1` | Bitsum Highest Performance power plan + PPM Rocket (immediate max CPU frequency), BCD (dynamictick, legacy menu), USB selective suspend disabled |
| `set_dns.ps1` | Optional Cloudflare DNS (1.1.1.1 / 1.0.0.1) |
| `debloat.ps1` | UWP app removal: Microsoft bloatware (Teams, Copilot, Outlook, Sticky Notes...), Xbox overlay, OEM apps (HP/Dell/Lenovo), pre-installed third-party apps (Spotify, Netflix, TikTok, Candy Crush...) |
| `privacy.ps1` | O&O ShutUp10++ + Recall, Click to Do, Copilot, Office AI policies, Paint AI, Notepad AI, Edge AI/sidebar disabled + telemetry scheduled tasks + PS7 telemetry + Brave policies + wscsvc (Security Center) + privacy registry tweaks |
| `ai_debloat.ps1` | Deep AI cleanup: advanced AI AppX removal, Recall optional feature removal, CBS package cleanup, region policy patch, and targeted file/task cleanup |
| `timer.ps1` | Optional SetTimerResolution at startup (~0.5 ms), installs VC++ x64 runtime if missing |
| `network_tweaks.ps1` | Teredo disabled, TCP stack (ECN, RSC off, heuristics off), LSO disabled on active adapters, Nagle disabled per Ethernet interface, QoS bandwidth reservation removed, MaxUserPort extended |
| `set_windows_update.ps1` | Windows Update profile (Maximum / Security / Disabled) |
| `firewall.ps1` | Windows Firewall profiles disabled |
| `personal_settings.ps1` | Optional personal shell/theme preferences (dark mode, accents, taskbar clock seconds, taskbar End task, Explorer presentation, Settings Home hidden) |
| `set_affinity.ps1` | GPU interrupt chain pinned to core 2 (GPU, PCI Bridge, Root Complex) |
| `msi_apply.ps1` | Applies `3 - MSI Utils/msi_state.json` if the file exists |
| `install_nvinspector.ps1` | only on NVIDIA systems, copies NVInspector bundle to `%APPDATA%\win_desloperf\NVInspector` and creates a Desktop shortcut |
| `opt_onedrive_uninstall.ps1` | Optional — full OneDrive removal |
| `opt_edge_uninstall.ps1` | Optional — full Edge removal (WebView2 Runtime preserved) |
| `opt_webview2_uninstall.ps1` | Optional — WebView2 Runtime removal (default OFF — may break Start menu search on some machines; fix: `Tools/fix_webview2.bat`) |
| `show_diff.ps1` | Post-tweak diff: compares current system state against `snapshot_latest.json`, categorizes results as "already OK", "applied", or "failed" |

### Diff report

`show_diff.ps1` runs automatically at the end of the automated phase (Phase C). It compares the current system state against the `backup/snapshot_latest.json` captured by `snapshot.ps1` before any tweak ran, and prints a categorized report:

- **already OK** — value was already at the target before tweaks
- **applied** — tweak changed the value successfully
- **failed** — value is not at the expected target after tweaks

`show_diff.ps1` can also be run standalone at any time after `run_all.bat`. Re-run it after a Windows Update to detect regressions: entries marked `failed` indicate tweaks that were reset by the update and need to be reapplied.

### Windows Update profiles

`set_windows_update.ps1` can also be run standalone at any time:


Profile 2 also sets `NoAutoRebootWithLoggedOnUsers=1` (Windows will not reboot to apply an update while you are logged in) and disables the "Get latest updates as soon as they're available" toggle that bypasses the normal update schedule.

### Registry tweaks applied

- GameDVR / GameBar disabled + ms-gamebar / ms-gamebarservices URL protocol redirect (silences focus-stealing popups after GameBar removal)
- MMCSS: GPU Priority 8, Priority 6, Scheduling Category High
- Power throttling disabled (`PowerThrottlingOff=1`)
- Network throttling disabled (`NetworkThrottlingIndex=0xFFFFFFFF`, `SystemResponsiveness=0`)
- VBS/HVCI disabled (`EnableVirtualizationBasedSecurity=0`)
- Global timer resolution (`GlobalTimerResolutionRequests=1`)
- `SvcHostSplitThresholdInKB=33554432` to reduce `svchost` splitting
- WaitToKillServiceTimeout reduced (2000 ms)
- Prefetch left at OS default (no benefit from disabling on modern storage)
- File extensions visible
- MarkC mouse acceleration fix (auto-detects DPI scaling)
- Hibernate disabled (`HibernateEnabled=0`) + Hybrid Boot / Fast Startup disabled (`HiberbootEnabled=0`) for a clean cold boot every time
- Keyboard: delay 0, max repeat rate
- HDCP disabled (NVIDIA)
- Classic context menu (Windows 11)
- Widgets / News disabled
- Start menu Recommended section hidden

### Timer resolution options

The `run_all.bat` setup asks you to install SetTimerResolution at startup. If you already use Process Lasso to manage the system timer, skip it.
The logic is simple:
- Already using Process Lasso for something else? Skip SetTimerResolution.
- Not using Process Lasso? Setup SetTimerResolution.

There is no point installing both, it's a background process running for nothing.

I recommend installing Process Lasso if you have a hybrid E-core + P-core (Intel) CPU, or a dual CCD with only one X3D cache (AMD). Set the CPU core affinity accordingly to get the best core for your game/application. (Double-check this though, some apps/games prefer many cores regardless of whether they are E-cores or X3D cores. Do your own research.)

If you use Process Lasso:
1. `Options > Tools > System Timer Resolution`
2. Set the value you want (`0.510`, `0.520`)
3. Enable `Set at every boot` + `Apply globally`

Use `0.510` or `0.520` rather than `0.500`. At exactly 0.5 ms you're asking for the hardware minimum. The system can't always hit it precisely and may overshoot to the next achievable interval, causing inconsistent `Sleep(1)` behavior and higher delta. A slightly higher target (0.5100 or 0.5200, test it for your setup) is more stable as you can see in the examples below.

After reboot, verify the results with `Tools/MeasureSleep.exe` (as admin). The requested timer value should match what you set with Lasso/STR, and `Sleep(1)` should stay close to `1 ms`.

| Not global | Global, clean | Global, noisier |
|-----------|---------------|-----------------|
| ![5000, Timer request not applied globally](assets/readme/timer-not-global.png) | ![5100, global timer applied](assets/readme/timer-global-clean.png) | ![5000, global timer applied](assets/readme/timer-global-noisy.png) |

**5000 Not global**: `GlobalTimerResolutionRequests=0`: The default and worst case. The timer request is not global, `Sleep(1)` still resolves at the default ~15.6 ms tick.

**5100 global**: `GlobalTimerResolutionRequests=1`: The timer is global. `Sleep(1)` resolves near `1.01-1.02 ms` with low and stable delta. Best result you can have.

**5000 global**: Timer is still global, but `Sleep(1)` drifts to `1.1-1.5 ms` with larger spikes. It's ok but less stable than 5100.

### GPU interrupt affinity

The `run_all.bat` setup menu asks whether the GPU interrupt chain should be pinned to core 2. It automatically detects the GPU, the PCI chain (GPU -> PCI Bridge -> Root Complex), and writes the affinity policy to the registry for each device.

**Warning: NVIDIA driver updates reset this setting for the GPU.** After every NVIDIA driver update (not NVIDIA App, only the driver itself), re-run step 4:

```
5 - Interrupt Affinity/set_affinity.bat   (double-click, UAC prompt is automatic)
```

The script outputs the full chain with the core assignment for each device:

```
[OK]  [1] GPU            -> core 2  DevicePolicy=4  AssignmentSetOverride=04 00 00 00
[OK]  [2] PCI Bridge     -> core 2  DevicePolicy=4  AssignmentSetOverride=04 00 00 00
[OK]  [3] Root Complex   -> core 2  DevicePolicy=4  AssignmentSetOverride=04 00 00 00
```

On AMD platforms, the PCI Root Complex appears as an ACPI device (`ACPI\PNP0A08`) rather than a PCI device in the Windows PnP tree. The script detects this, notes it, and applies to GPU + PCI Bridge only.

```
[NOTE] Root Complex is ACPI (ACPI\PNP0A08\0) -- normal on AMD.
[OK]  [1] GPU        -> core 2 ...
[OK]  [2] PCI Bridge -> core 2 ...
```

Core 2 is generally the best choice. It avoids core 0 (OS/system interrupts), is not a Hyper-Threading sibling, and is not an E-core on Intel CPUs.

LatencyMon (Drivers tab) before and after. Same session, NVIDIA RTX 4090 on AMD (9800X3D) platform, both runs stopped at exactly 1 minute:

| Before | After |
|--------|-------|
| ![LatencyMon before interrupt affinity](assets/readme/affinity-latencymon-before.png) | ![LatencyMon after interrupt affinity](assets/readme/affinity-latencymon-after.png) |
| `nvlddmkm.sys` 3736 DPCs / 0.124 ms -- `dxgkrnl.sys` 576 DPCs / 0.139 ms | `nvlddmkm.sys` 116 DPCs / 0.035 ms (-97% / -72%) -- `dxgkrnl.sys` 90 DPCs / 0.092 ms (-84% / -34%) |

> Note: the "before" baseline is already from a heavily optimized system. On a stock Windows install, `nvlddmkm.sys` highest execution time can exceed 300 ms. The delta here reflects the affinity change alone, on top of everything else the pack already applied.

To undo: `restore_affinity.bat` in the same folder.

### Service startup tweaks

`services.ps1` aligns service startup types to a built-in catalog optimized for gaming.
Noisy stuff like `SysMain`, `DPS`, `DiagTrack`, `WSearch` gets disabled. Most secondary services stay `Manual`, including `IKEEXT`, `StiSvc` and `TermService`. A small core stays `Automatic` on purpose (`DeviceAssociationService`, `InstallService`, `VaultSvc`, `W32Time`, `wuauserv`). `UsoSvc` is `AutomaticDelayedStart`.
`DoSvc` is `Disabled`, and its `TriggerInfo` key is removed so SCM cannot quietly bring it back.

### Logging

All executions are logged to:

```
%APPDATA%\win_desloperf\logs\win_desloperf.log
%APPDATA%\win_desloperf\logs\win_desloperf_restore.log
```

---

## Manual phase

| Step | Path | Why manual | Risk level |
|------|------|-----------|------------|
| 1 | **2 - Windows Defender** | Requires Safe Mode; PPL and Tamper Protection block full disable in normal mode | High |
| 2 | **3 - MSI Utils** | Manual identification of compatible devices required on first run | Moderate |
| 3 | **4 - Device Manager** | Disable unused devices (HDA Controller, IME, Hyper-V driver, GS Wavetable, etc.) to remove their DPCs and interrupts; which devices are safe to disable depends on your hardware | Low |
| 4 | **5 - Interrupt Affinity** | Automated by `set_affinity.bat`, but you need to re-run after each NVIDIA driver update. | Low |
| 5 | **NIC Device Manager** | Hardware-dependent NIC settings: disable Interrupt Moderation, EEE, Flow Control, Wake-on-*, LSO V2; max Receive/Transmit Buffers; uncheck power management. Keep Checksum Offload enabled and Speed/Duplex on Auto-Negotiation. | Low |
| 6 | **Tools** | Complementary tools (Autoruns, NVInspector, temp folders) | Low |

### Quick reruns

These are not mandatory manual steps after a fresh install, but they stay easy to
re-run later without launching the full `run_all.bat` flow again.

- `6 - DNS/set_dns.bat` re-applies Cloudflare DNS on active adapters
- `7 - Windows Update/set_windows_update.bat` switches the Windows Update profile

### MSI Utils

Which devices get MSI enabled is a judgment call, you have to look at the list and decide. That part stays manual. But once it's configured, `msi_snapshot.bat` saves the registry state of every PCI device to `msi_state.json`. `run_all.bat` can pick it up and apply it automatically, or you can run `msi_apply.bat` manually.

**First time:**

1. `PCIutil.exe` as administrator, close it right away (loads the kernel driver `MSI_util_v3.exe` needs)
2. `MSI_util_v3.exe` as administrator (important), enable MSI on GPU, NIC, NVMe. See `readme.txt` for what to avoid
3. `msi_snapshot.bat` saves the replay snapshot to `3 - MSI Utils/msi_state.json` before rebooting
4. Reboot, check nothing broke. If a custom MSI setup causes instability or a BSOD later, `msi_restore.bat` in Safe Mode replays `1 - Automated/backup/msi_state_default.json`.

**After a reformat:**

If `3 - MSI Utils/msi_state.json` exists, `run_all.bat` exposes **Apply saved MSI snapshot** directly in the initial launch menu. On the first apply, it also creates `1 - Automated/backup/msi_state_default.json` as the rollback state.

If a device changed PCI slot since the snapshot, its InstanceId will differ and it gets skipped with a warning — configure it manually and re-run `msi_snapshot.bat` to update.

`msi_apply.bat` does the same thing standalone as the automatic replay path and creates `1 - Automated/backup/msi_state_default.json` if needed. `msi_restore.bat` is the Safe Mode rollback that reapplies only `msi_state_default.json`.

> Do not enable MSI on audio controllers, capture cards (ELGATO), or legacy USB, BSOD risk. See `readme.txt` for the full list.

---

## Rollback

```
1 - Automated/restore_all.bat   (double-click, UAC prompt is automatic)
```

Restores in order:

- Registry (from backup + visual effects SPI reset + mouse curves reverted to Windows default)
- Services (back to saved state from `backup/services_state.json`)
- System performance (BCD entries removed, power plan back to Balanced, USB selective suspend restored)
- DNS (back to DHCP)
- SetTimerResolution (startup shortcut removed)
- Privacy & AI (privacy registry defaults + AI/Recall/Copilot policy keys removed)
- AI deep debloat backups (saved JSON/Game Bar backups restored where available)
- UWP app reinstallation help (`debloat_restore.ps1` provides Store/winget commands)
- Network tweaks (Teredo, TCP stack, LSO, Nagle, QoS restored to Windows defaults)
- Windows Update (restored to Maximum / Windows default)
- Windows Firewall profiles (restored to saved state or Windows default)
- Personal shell/theme settings (restored to Windows defaults)
- GPU interrupt affinity (Affinity Policy keys removed or restored to pre-tweak state)
- Optional reinstall prompt for Microsoft Edge / OneDrive

---

## Warnings

> This touches a lot of system settings. Back up your machine first. The scripts create a restore point, but have your own backup too.

| | Risk |
|-|------|
| **Defender disabled** | No real-time antivirus protection. On 25H2, Tamper Protection may block disabling even in Safe Mode. The script also disables Smart App Control (`VerifiedAndReputablePolicyState=0`) — this is **irreversible** without reinstalling Windows. |
| **VBS/HVCI disabled** | Credential Guard and memory protections are off. Good perf gain, but you lose some security hardening. |
| **MSI Utils** | Do not enable MSI on audio controllers, capture cards (ELGATO) or legacy USB. BSOD risk. |
| **WU Disabled profile** | No security patches, only use on isolated gaming machines. |
| **Firewall disabled** | No Windows firewall filtering. Use only if another firewall or isolated setup covers the machine. |
| **Timer resolution tools** | Use either `SetTimerResolution` or `Process Lasso`, not both. After reboot, check with `Tools/MeasureSleep.exe`. Known conflicts: VoiceMeeter Macro Buttons < v1.1.3.1 (forces 0.50 ms, update it), OpenRGB (holds 0.50 ms while running, close it after setup your leds). |
| **Higher power draw** | With all these settings, your hardware may use more power and generate more heat. It's not a problem, but keep that in mind if your desktop/laptop runs hotter after applying the pack (maybe it's time to clean your PC or replace your thermal paste!). |

---

## About and why

I've been accumulating tweaks for years (since Windows 10 launched). Some from the community on Reddit, various forums, YouTubers, or tested by myself.
Windows was never perfect but was in much better shape 10 years ago. It didn't need an optimization pack, just a few comfort updates and some minor telemetry removal.

Today, with Windows 11, Microslop's catastrophic decisions regarding telemetry, massive BLOAT, AI integration and questionable choices that ruin performance, QOL bugs, and settings forced back after a simple security update, optimizing your machine is more necessary than ever.

Windows 10 is no longer supported, and Microslop is forcing everyone onto the latest release of their OS (W11 25H2). The sad reality today is that to get the most out of your hardware (and keep some privacy), you have to clean up your Windows (or switch to a Linux distro). Many people don't, and lose a ton of performance without even knowing it.

Optimization scripts already exist (WinUtil is excellent), but I decided to make my own pack for several reasons:
- The accumulation of my own tweaks and personal experience.
- Having precise control over what gets applied to a Windows install (registry keys, killed services, etc.)
- Producing a script that is CONSISTENT, fixed, that doesn't require choosing among tons of obscure options, that doesn't need to be pulled every time via `iex`. A straightforward script.
- And finally, being able to reproduce my personal settings consistently without having to go through the Control Panel after every install.

I want to point out that I used Claude Code/Codex to help me build the automation and restore system for the whole pack. It allowed me to automate things I had been doing manually for years.
Some text (readme) is also AI-generated.

Even though the pack has been extensively tested, I can't guarantee it covers every possible configuration without breaking something. I did my best based on my own hardware and personal feedback.



---

## License

MIT
