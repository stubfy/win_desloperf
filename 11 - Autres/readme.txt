11 - AUTRES
Outils complementaires divers
==============================

Ce dossier regroupe des outils utilitaires qui ne s'integrent pas dans
les autres categories mais restent utiles pour le suivi et la maintenance
du systeme apres optimisation.


AUTORUNS (Sysinternals)
-----------------------
Outil de Microsoft Sysinternals qui liste exhaustivement tous les points
de demarrage automatique du systeme Windows.

Ce que ca couvre :
  - Cles Run / RunOnce dans HKLM et HKCU
  - Services systeme (HKLM\SYSTEM\CurrentControlSet\Services)
  - Pilotes de demarrage
  - Taches planifiees (Task Scheduler)
  - AppInit_DLLs (DLL injectees dans tous les processus)
  - Browser Helper Objects (extensions navigateur)
  - LSA Authentication Packages
  - Winlogon Notify packages
  - Boot Execute entries

Utilisation :
  Ouvrir Autoruns\Autoruns64.exe en administrateur. Decocher une entree
  pour la desactiver (sans la supprimer). La colonne "Publisher" affiche
  le signataire — tout element non signe ou de publisher inconnu merite
  attention. Menu Options > Scan Options > Check VirusTotal.com permet
  de verifier les executables contre la base de donnees VirusTotal.


DEVICECLEANUP
-------------
Supprime les entrees de peripheriques fantomes (ghost devices) du
Gestionnaire de peripheriques et du registre Windows.

Ce que ca couvre :
  Les peripheriques deconectes conservent leurs entrees dans :
    HKLM\SYSTEM\CurrentControlSet\Enum
  avec le flag ConfigFlags contenant le bit 0x1 (CONFIGFLAG_REINSTALL).
  DeviceCleanup appelle CM_Get_DevNode_Status pour chaque nœud du
  DeviceTree, identifie ceux dont l'etat est DN_WILL_BE_REMOVED ou
  absent physiquement, puis appelle SetupDiRemoveDevice pour les
  supprimer proprement.

Utilisation :
  Ouvrir deviceCleanup\DeviceCleanup.exe en administrateur. La liste
  affiche les peripheriques non connectes. Selectionner tout (Ctrl+A)
  et supprimer, ou filtrer par type avant de supprimer.

Note : apres avoir desactive des peripheriques dans le Gestionnaire de
peripheriques (voir dossier 8), lancer DeviceCleanup pour nettoyer les
entrees residuelles.


FICHIERS TEMP
-------------
Raccourcis vers les dossiers de fichiers temporaires Windows :
  Fichiers temp 1 : %TEMP% (dossier temporaire de l'utilisateur courant)
  Fichiers temp 2 : %WINDIR%\Temp (dossier temporaire systeme)

Supprimer le contenu de ces dossiers periodiquement pour liberer de
l'espace disque. Ignorer les erreurs "fichier en cours d'utilisation"
— ces fichiers sont utilises par des processus actifs et ne peuvent
pas etre supprimes pendant la session.


FILTRES NVIDIA SHARPNESS
------------------------
Contient des fichiers .reg alternatifs pour le filtre NIS (chemin de
registre legacy utilise par les anciens pilotes NVIDIA).
Ces fichiers sont supplantas par ceux du dossier 7 - NVInspector
qui ciblent le chemin correct pour les pilotes modernes.
Ne pas les appliquer si les .reg du dossier 7 ont deja ete utilises.
