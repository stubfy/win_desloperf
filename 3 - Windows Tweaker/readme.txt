3 - WINDOWS TWEAKER
Tweaks supplementaires via Ultimate Windows Tweaker v5
======================================================

CE QUE CA FAIT
--------------
Ultimate Windows Tweaker (UWT) est un outil graphique qui applique des
reglages Windows non couverts par les scripts automatiques du pack. Il agit
sur des cles de registre HKLM et HKCU dans les categories Policies, Explorer,
services et securite.

Le fichier Settings.ini fourni dans ce dossier pre-selectionne les tweaks
valides pour un PC gaming sous Windows 11 25H2.


TWEAKS COUVERTS PAR UWT (non dupliques dans les scripts automatiques)
----------------------------------------------------------------------
Les scripts run_all.ps1 couvrent deja la majorite des tweaks registry et
services. UWT ajoute les elements suivants non scriptables proprement :

  - Desactiver les invites UAC (User Account Control) — attention : reduit
    la securite sur les machines utilisees pour la navigation
  - Desactiver la biometrie Windows Hello
  - Desactiver WiFi Sense (partage de mots de passe WiFi avec contacts)
  - Quelques cles de policies Edge et Cortana non exposees en CLI
  - Reglages Explorer (icones systeme, comportement des fenetres)

En termes techniques, UWT utilise SetValue directement sur les cles registre
sans passer par des API intermediaires. Les tweaks selectionnes dans
Settings.ini ont ete valides pour 25H2. Les tweaks redondants avec les
scripts automatiques du pack (telemetrie, background apps, GameDVR, Defender
via policy) ont ete exclus du Settings.ini pour eviter les conflits.


PROCEDURE
---------
1. Ouvrir ce dossier
2. Lancer UWT_v5.exe en administrateur (clic droit > Executer en tant
   qu'administrateur)
3. Menu File > Load Settings > selectionner Settings.ini dans ce dossier
4. Verifier que les tweaks correspondent a vos besoins
5. Cliquer "Apply" pour appliquer
6. Redemarrer si demande


NOTES
-----
UWT v4.4.1 (Windows 10) est egalement present dans ce dossier a titre
d'archive. Ne pas l'utiliser sur Windows 11 — utiliser exclusivement UWT v5.

Si un tweak produit un comportement inattendu, UWT permet de l'annuler
individuellement via la meme interface en deselectionnant le tweak et en
cliquant Apply.
