# Etapes manuelles - Opti Pack Windows 11 25H2

Ces etapes ne peuvent pas etre automatisees. Les effectuer dans l'ordre indique,
apres avoir execute `run_all.ps1` et redemarre le PC.

---

## 1. Redemarrer le PC

Apres `run_all.ps1`, redemarrer avant d'effectuer les etapes suivantes.

---

## 2. Desactiver Windows Defender [Mode Sans Echec requis]

**Prerequis** : Tamper Protection doit etre desactivee manuellement dans
Securite Windows > Protection contre les virus > Parametres > Protection contre la
falsification > OFF.

**Procedure** :
1. Ouvrir `msconfig` > onglet Demarrage > cocher **Demarrage securise** (Minimal) > OK
2. Redemarrer en mode sans echec
3. Ouvrir PowerShell en admin, executer :
   ```
   .\1 - Windows Defender\2 - DisableDefender.ps1
   ```
4. Ouvrir `msconfig` > decocher Demarrage securise > OK > Redemarrer normalement

**Rollback** : Reactiver chaque service (Start = 3 sauf WdFilter/WdBoot = 0) via regedit ou
Securite Windows.

---

## 3. MSI Utils - Mode interruptions (dossier 6)

**Outils** : `6 - MSI Utils\MSI_util_v3.exe` (admin requis)

**Activer MSI sur** :
- GPU (carte graphique NVIDIA/AMD)
- Carte reseau (NIC)
- NVMe / SSD (controleur de stockage)
- Controleurs USB (si compatible)

**NE PAS activer sur** :
- Controleurs audio (risque BSOD)
- Cartes de capture (ELGATO, AVerMedia)
- Appareils USB legacy

Voir `6 - MSI Utils\readme.txt` pour la liste de compatibilite.

**Rollback** : Desactiver MSI dans le meme outil.

---

## 4. Interrupt Affinity Policy (dossier 10)

**Outil** : `10 - Interrupt Affinity Policy\intPolicy_x64.exe`

**Objectif** : Epingler les interruptions GPU sur un coeur CPU dedie (typiquement le coeur 2)
pour reduire la latence.

**Procedure** :
1. Ouvrir le Gestionnaire de peripheriques (`10 - Interrupt Affinity Policy\Gestionnaire.lnk`)
2. Menu Affichage > Afficher par connexion
3. Localiser la carte graphique et noter son PCI Bridge parent
4. Dans `intPolicy_x64.exe` :
   - Selectionner le GPU, le PCI Bridge et le PCI Root Complex
   - Definir l'affinite sur le coeur CPU 2 (ou un coeur dedie)
5. Redemarrer

**Rollback** : Remettre l'affinite sur "tous les coeurs" dans le meme outil.

---

## 5. Parametres carte reseau (dossier 11)

**Chemin** : Gestionnaire de peripheriques > Cartes reseau > [votre carte] > Proprietes > Avance

**Desactiver** :
- ARP Offload
- NS Offload
- DMA Coalescing
- Energy Efficient Ethernet (EEE)
- Flow Control
- Interrupt Moderation
- Large Send Offload v2 (IPv4 et IPv6)
- Wake on Magic Packet / Wake on Pattern Match

**Augmenter a 2048** :
- Receive Buffers
- Transmit Buffers

**Onglet Gestion de l'alimentation** :
- Decocher "Autoriser l'ordinateur a eteindre ce peripherique pour economiser l'energie"

Voir `11 - Network WIP\readme.txt` pour les captures d'ecran (carte Intel I226-V).

**Rollback** : Restaurer les valeurs par defaut dans le meme menu.

---

## 6. Gestionnaire de peripheriques - Economie d'energie USB (dossier 9)

**Chemin** : Gestionnaire de peripheriques > Controleurs USB / Concentrateurs USB / HID

**Pour chaque peripherique USB (clavier, souris, concentrateurs, controleurs)** :
1. Clic droit > Proprietes > onglet Gestion de l'alimentation
2. Decocher "Autoriser l'ordinateur a eteindre ce peripherique pour economiser l'energie"

**Desactiver les peripheriques inutiles** (si presents) :
- Carte Bluetooth si non utilisee
- Adaptateurs reseau virtuels (VMware, VirtualBox)
- Peripheriques audio non utilises

Voir `9 - Gestionnaire de peripherique\readme.txt` pour la liste complete.

---

## 7. NVIDIA Profile Inspector (dossier 8)

**Outil** : `8 - NVInspector\NVPI-Revamped\NVPI-R.exe`

**Prerequis NIS** : Activer NIS dans le Panneau de configuration NVIDIA ou NVIDIA App d'abord
(requiert un rafraichissement de l'affichage que NVPI ne peut pas faire).

**Reg files fournis** (double-clic pour appliquer) :
- `1. Disable DLSS UI.reg` - Desactive l'indicateur DLSS en overlay
- `3. New NIS [Default].reg` - Algorithme NIS moderne (RTX 20+) - **recommande**
- `4. Old NIS.reg` - Algorithme NIS ancien (GTX 10 et plus anciens)

**Dans NVPI-R** : Configurer les profils par jeu selon les besoins.

Voir `8 - NVInspector\ReadMe.txt` pour les valeurs de sharpening recommandees.

---

## 8. Panneau de configuration (dossier 5)

Ouvrir chaque raccourci du dossier `5 - Control Panel` et appliquer les parametres
indiques dans `5 - Control Panel\readme.txt` :

| Raccourci | Action |
|-----------|--------|
| 0 - Planificateur graphique | Activer la planification GPU acceleree |
| 1 - Notifications | Desactiver toutes les notifications inutiles |
| 2 - Stockage | Activer Storage Sense |
| 3 - Couleurs | Desactiver la transparence |
| 5 - Loupe | Desactiver la loupe au demarrage |
| 6 - Confidentialite | Revoir les permissions (localisation, micro, camera) |
| 7 - Effets Visuels | Ajuster les effets (Performance) |
| 8 - Options d'alimentation | Verifier le plan actif (Ultimate Performance) |
| 9 - Pare-feu | Verifier les regles |
| 11 - Barre des taches | Personnaliser la barre des taches |

---

## 9. Verifier la resolution timer

Apres redemarrage, lancer `12 - SetTimerResolution\MeasureSleep.exe` pour confirmer
que la resolution effective est <= 0.5ms.

Si superieure, ajuster l'argument dans le raccourci de demarrage :
- Emplacement : `shell:startup\SetTimerResolution.lnk`
- Essayer : `--resolution 5000`, `--resolution 5100`, `--resolution 5200`

---

## Rollback complet

Executer `restore_all.ps1` pour annuler tous les tweaks automatiques.

Pour les tweaks manuels : les inverser dans les memes outils / menus.

En dernier recours : utiliser le point de restauration systeme cree par `run_all.ps1`
(Panneau de configuration > Systeme > Protection du systeme > Restauration du systeme).
