# CLAUDE.md

Ce fichier sert de base de connaissance locale pour les agents IA qui travaillent sur **win_desloperf**.

---

## Vue d'ensemble

**win_desloperf** (v1.2) est un pack d'optimisation Windows 11 25H2 axe sur les performances gaming (input lag, frametime, latence), le debloat, la confidentialite et le confort.

Le depot est compose de scripts PowerShell, fichiers `.reg`, lanceurs `.bat`, executables tiers et guides manuels. Il n'est pas une application classique.

**Conventions critiques :**

- Le contenu user-facing reste en anglais
- `CLAUDE.md` est le seul fichier Markdown de reference pour les agents IA ; `AGENTS.md` n'existe plus
- `_check_updates.ps1` est local (gitignore), pas un composant a publier
- `update_pack.bat` est le point d'entree user-facing ; `update_pack.ps1` est dans `1 - Automated/scripts/ps1/` et appele par le bat via `-RootPath`
- `pack-version.txt` est la source de verite de la version locale
- Toute modification de tweaks, scripts ou rollback doit etre repercutee dans `CLAUDE.md`

---

## Structure du depot

- `1 - Automated/` — coeur du projet (scripts automatises, backup, tools)
- `2 - Windows Defender/` — flow Defender Safe Mode manuel
- `3 - MSI Utils/` — configuration MSI sur les peripheriques PCI
- `4 - Device Manager/` — raccourci vers le Gestionnaire de peripheriques
- `5 - Interrupt Affinity/` — epinglage interrupts GPU + souris
- `6 - DNS/` — reapplication rapide DNS Cloudflare
- `7 - Windows Update/` — switch rapide des profils Windows Update
- `8 - USB Power/` — reapplication rapide USB power management disable (apres branchement de nouveaux peripheriques)
- `Tools/` — utilitaires de verification et maintenance
- `Tools/fix_webview2.bat` — restaure WebView2 Runtime sur les PC ou une ancienne version du pack l'a supprime (fix Start menu search)
- `Tools/NVInspector/` — bundle NVInspector, installation vers `%APPDATA%\win_desloperf\NVInspector`
- `backup/` — genere localement, ignore par git
- `1 - Automated/scripts/firewall.bat` — reapplication rapide du firewall

---

## Flux d'execution

### Phases de run_all.bat / run_all.ps1

1. Auto-elevation UAC
2. Menu interactif (profil WU, Edge, OneDrive, firewall, DNS, timer, personal settings, network tweaks, write-cache SSD/NVMe, NVInspector, affinity)
3. **Phase A** : snapshot (`snapshot.ps1`) + sauvegardes multi-couches (`backup.ps1`)
4. **Phase B** : tweaks automatises en sequence
5. **Phase C** : diff final (`show_diff.ps1`) + optionnels (MSI, NVInspector, Edge, OneDrive)
6. Proposition reboot : `[S]` Safe Mode (Defender), `[Y]` normal, `[N]` aucun

### Quick reruns sans relancer run_all

- `6 - DNS\set_dns.bat`
- `7 - Windows Update\set_windows_update.bat`
- `8 - USB Power\set_usb_power.bat` — a relancer apres branchement de nouveaux peripheriques USB
- `1 - Automated\scripts\firewall.bat`

### Rollback global

`restore_all.bat` → `restore_all.ps1` : restauration sequentielle registry > services > performance > dns > timer > privacy > debloat_restore > network_tweaks > usb_power > windows_update > firewall > personal_settings > restore_affinity. Le restore performance remet aussi le write cache / write-cache buffer flushing des SSD/NVMe a l'etat sauvegarde. Propose en fin de reinstaller Edge + OneDrive.

### Logging

- Fichier : `%APPDATA%\win_desloperf\logs\win_desloperf.log`
- Format : `[HH:mm:ss] [LEVEL] message`
- Niveaux : `INFO`, `STEP`, `RUN`, `OUT`, `OK`, `WARN`, `ERROR`
- Fonctions : `Write-Log()`, `Write-Step()`, `Invoke-Script()`

---

## Notes architecturales critiques

### Dependances cross-scripts (non evidentes a la lecture)

- **registry.ps1 → timer.ps1** : `GlobalTimerResolutionRequests=1` est pose dans `tweaks_consolidated.reg`. Sans cette cle, SetTimerResolution reste per-process et n'affecte pas le systeme globalement.
- **services.ps1 → privacy.ps1** : DoSvc est force Disabled + suppression `TriggerInfo` dans services.ps1, complementaire avec `DODownloadMode=0` dans privacy.ps1. Les deux sont necessaires pour bloquer Delivery Optimization durablement.
- **affinity_helpers.ps1** : dot-source par `set_affinity.ps1`, `restore_affinity.ps1`, `backup.ps1`, `snapshot.ps1`. Ne jamais dupliquer la logique de detection GPU, souris ou PCI chain walk en dehors de ce fichier.
- **storage_write_cache_helpers.ps1** : dot-source par `performance.ps1`, `restore\performance.ps1`, `snapshot.ps1`. Centralise la detection SSD/NVMe interne et le mapping vers `HKLM\SYSTEM\CCS\Enum\<disk>\Device Parameters\Disk`.
- **backup.ps1 → restore\network_tweaks.ps1** : `nic_power_state.json` cree par backup.ps1 (Phase A) est lu par le restore pour restaurer les valeurs exactes d'origine. Sans ce fichier, le restore ne peut que supprimer PnpCapabilities (fallback).
- **backup.ps1 + usb_power.ps1 → restore\usb_power.ps1** : `usb_power_state.json` cree par backup.ps1 (Phase A, premier run uniquement). `usb_power.ps1` merge de nouveaux devices dans ce fichier lors des re-runs (sans ecraser les etats d'origine). Le restore lit ce JSON pour revenir a l'etat exact pre-tweak par device.

### Comportements non-évidents par script

**registry.ps1** : trois sections distinctes — import `tweaks_consolidated.reg`, effets visuels via SPI P/Invoke (effet immediat sans logoff), fix souris MarkC (auto-detection DPI via `LogPixels`).

**performance.ps1** : importe `bitsum_highest_performance.pow` (GUID fixe `5a39c962-...`) si absent, active directement si present (idempotent). PPM Rocket applique par-dessus. Nettoie les doublons "Ultimate Performance" des runs precedents. Fallback : duplique le plan cache "Ultimate Performance" si l'import .pow echoue. Desactive la Memory Compression Windows (`Disable-MMAgent -MemoryCompression`) — overhead CPU inutile sur gaming PC 16 Go+. **Option user-choice** : si `disableWriteCacheFlushing=true` dans `run_all.ps1`, cible les SSD/NVMe internes uniquement et force `UserWriteCacheSetting=1` + `CacheIsPowerProtected=1` sous `HKLM\SYSTEM\CCS\Enum\<disk>\Device Parameters\Disk`, ce qui active le write cache et desactive le write-cache buffer flushing. Backup dedie : `backup\disk_write_cache_state.json` (merge additif, etats d'origine preserves). Rollback exact dans `restore\performance.ps1`, avec fallback `0/0` si le backup manque. Etat capture dans `snapshot.ps1` (section `StorageWriteCache`) et diff affiche dans `show_diff.ps1`. **Trade-off explicite** : leger risque de perte de donnees en cas de coupure de courant brutale, accepte pour un gaming PC mais a ne pas activer sur une machine critique.

**network_tweaks.ps1** : sept sections — Teredo disable (netsh), TCP global stack (netsh), LSO disable par adaptateur actif, QoS Psched registre, Nagle disable par adaptateur filaire (TcpAckFrequency/TCPNoDelay/TcpDelAckTicks), MaxUserPort extension, NIC power saving (desactive EEE, Green Ethernet, WoL variants, PM offloads via `Set-NetAdapterAdvancedProperty` + `PnpCapabilities=0x18` par adaptateur physique actif). Backup : `nic_power_state.json`. Rollback lit le JSON pour restaurer les valeurs exactes ; fallback supprime PnpCapabilities si pas de backup.

**privacy.ps1** : OOSU10 n'a pas de rollback automatique — utiliser le restore point cree par `backup.ps1`. Windows Update peut reactiver les taches telemetrie desactivees lors de MAJ majeures.

**usb_power.ps1** : itere `Get-PnpDevice` sur les classes `USB`, `HIDClass`, `USBDevice` (Status OK, InstanceId commencant par `USB\` ou `HID\`). Pour chaque device : `PnpCapabilities=0x18` (desactive "allow turn off"), `WakeEnabled=0`, et les cles USB-specifiques (`EnhancedPowerManagementEnabled`, `AllowIdleIrpInD3`, `SelectiveSuspendEnabled`) uniquement si elles existent deja. Backup merge : les etats d'origine sont preserves meme lors des re-runs. **Point critique : chaque nouveau peripherique USB branche a ses flags reactives par Windows** — re-lancer `set_usb_power.bat` apres chaque nouveau branchement.

**affinity (set_affinity.ps1)** : mode auto si `affinity_config.json` present, mode interactif sinon. **Point critique : les MAJ driver NVIDIA resetent l'affinite GPU et souris** — re-lancer `set_affinity.bat` apres chaque MAJ driver. La config JSON est auto-appliquee sans prompt.

**defender_disable.ps1** : shim de compatibilite uniquement, renvoie vers `2 - Windows Defender\1 - DisableDefender.ps1`.

**show_diff.ps1** : reutilisable standalone apres Windows Update pour detecter les regressions (entries "failed" = tweaks reverted par la MAJ). Inclut aussi `StorageWriteCache` si le snapshot a ete pris avec l'option `disableWriteCacheFlushing` activee.

### NVInspector : logique version-aware

`install_nvinspector.ps1` gere 3 cas via `%APPDATA%\win_desloperf\NVInspector\.pack-version` :
- Absent → install complete + raccourci Bureau
- Meme version → no-op
- Version differente / marqueur absent (legacy) → upgrade silencieux, settings utilisateur preserves

### Defender : pourquoi Safe Mode est requis

Tamper Protection bloque les modifications depuis les processus normaux. PPL empeche la desactivation propre. En Safe Mode, Tamper Protection est inactif. Smart App Control (`VerifiedAndReputablePolicyState=0`) est **irreversible** — remettre a On necessite une reinstallation de Windows.

### MSI Utils : devices a ne pas activer (BSOD)

Cartes de capture ELGATO, High Definition Audio controller, cartes son (Soundblaster/ASUS Xonar/Creative), controleurs USB 1.0/1.1/2.0 legacy.

### Systeme de mise a jour : contrat de maintenance

- Toute montee de version doit mettre a jour `pack-version.txt`
- Le tag GitHub publie doit correspondre a `pack-version.txt`
- Un changelog utile dans l'updater necessite une GitHub Release avec body par tag

---

## Limites du rollback

| Limitation | Composant | Impact |
|-----------|-----------|--------|
| Apps UWP non restaurees automatiquement | debloat.ps1 | Reinstallation manuelle via Store/winget |
| Taches telemetrie non re-activees | privacy.ps1 | Re-enable manuel via Task Scheduler |
| DoSvc TriggerInfo non restaure parfaitement | services.ps1 | Restore point recommande |
| OOSU10 non rollback | privacy.ps1 | Restore point recommande |
| Defender necessite Safe Mode | defender_disable.ps1 | restore_all ne le gere pas |
| Smart App Control off = irreversible | Defender disable | Reinstallation Windows requise |
| Edge depend du build Windows | opt_edge_uninstall.ps1 | Methode WinUtil peut echouer |
| Plan Bitsum conserve apres restore | performance.ps1 | `powercfg -delete 5a39c962-8fb2-4c72-8843-936f1d325503` |
| Policies Brave non rollback | privacy.ps1 | Suppression manuelle registre |
| wscsvc non re-enable automatique | privacy.ps1 | Re-enable manuel si necessaire |
| NIC power restore keye par nom d'adaptateur | network_tweaks.ps1 | Renommer l'adaptateur entre apply et restore = restore manuel |
| USB power restore keye par InstanceId | usb_power.ps1 | Device desinstalle/rebranche avec nouvel InstanceId = restore manuel |
| Disk write cache restore keye par chemin PnP disque | performance.ps1 | Changement majeur de controller / re-enumeration = fallback ou restore manuel |

---

## Risques principaux

| Risque | Composant | Niveau |
|-------|-----------|--------|
| Tamper Protection / Smart App Control bloque | Defender disable | Eleve |
| Mauvais device MSI = BSOD possible | MSI Utils | Modere |
| Mauvais core affinity = latence pire | Interrupt Affinity | Modere |
| Baisse de securite significative | VBS / HVCI off | Modere |
| Recovery graphique perdu | boot menu legacy | Modere |
| Firewall off sur reseau non protege | firewall.ps1 | Modere |
| Desactivation du write-cache buffer flushing = risque de perte de donnees sur coupure brutale | performance.ps1 | Modere |
| MAJ driver NVIDIA reset affinity | Interrupt Affinity | Faible (re-run script) |

---

## Historique rapide

- **v1.0** : version publique stable
- **v0.9+** : consolidation Phase B de 20 a 14 steps ; `performance.ps1` fusionne power/bcdedit/usb, `privacy.ps1` fusionne oosu10/ai_disable/telemetry_tasks, `registry.ps1` absorbe SPI + MarkC ; `uwt.ps1` dissous ; 24 fichiers supprimes
- **v0.9** : extraction DNS/WU/Firewall en steps root, suppression placeholder `07_edge`, realignement `services.ps1` vers WinUtil Manual avec DoSvc Disabled
- **v0.7** : flow Defender Safe Mode automatise, ajout `snapshot.ps1` et `show_diff.ps1`
- **v0.6** : automatisation du fix MarkC souris
- **v0.5** : conversion UWT vers registre, renommages dossiers


