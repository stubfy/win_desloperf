OPTI PACK — Windows 11 25H2
Optimisation gaming, debloat et qualite de vie
===============================================

Ce pack regroupe des tweaks et outils pour ameliorer les performances gaming
(latence d'entree, frametime, fluidite systeme), supprimer le bloatware Microsoft
et corriger des comportements Windows par defaut defavorables au gaming.

Cible : Windows 11 25H2, configuration PC gaming (GPU NVIDIA, NIC Intel I226-V).


ORDRE D'UTILISATION
-------------------

ETAPE 1 — Lancer les tweaks automatiques
  Ouvrir "1 - Automatique\" en administrateur et executer run_all.ps1.
  Le script applique tous les tweaks scriptables en une passe, cree une
  sauvegarde de l'etat initial et propose un redemarrage a la fin.
  Duree estimee : 5 a 15 minutes selon la configuration.

ETAPE 2 — Redemarrer le PC (demande par run_all.ps1)

ETAPE 3 — Effectuer les etapes manuelles dans l'ordre des dossiers :

  2 - Windows Defender     Desactiver Defender en Mode Sans Echec (requis)
  3 - Windows Tweaker      Appliquer tweaks GUI supplementaires (UWT v5)
  4 - Control Panel        Reglages interface graphique Windows
  5 - MSI Utils            Activer les interruptions MSI sur GPU / NIC / NVMe
  6 - Mouse Accel fix      Corriger la courbe d'acceleration souris (si scaling != 100%)
  7 - NVInspector          Profils pilote NVIDIA par jeu
  8 - Gestionnaire         Desactiver economie d'energie USB (clavier, souris)
  9 - Interrupt Affinity   Epingler les IRQ GPU sur un coeur CPU dedie
  10 - Network WIP         Reglages avances carte reseau (offloads, buffers)
  11 - Autres              Outils complementaires (Autoruns, DeviceCleanup, temp)

Chaque dossier contient un readme.txt avec les instructions detaillees.


ANNULER LES TWEAKS AUTOMATIQUES
--------------------------------
Executer "1 - Automatique\restore_all.ps1" en administrateur.
Remet les services, le registre, le DNS et la configuration boot a leurs
valeurs d'origine. Un redemarrage est necessaire pour finaliser.

Les desinstallations d'applications UWP ne sont pas automatiquement reversibles
(reinstallation possible depuis le Microsoft Store).


CONTENU DE 1 - AUTOMATIQUE
----------------------------
  run_all.ps1      Lanceur principal (tweaks automatiques)
  restore_all.ps1  Restauration complete
  scripts\         Scripts individuels par categorie
  restore\         Scripts de restauration correspondants
  tools\           Outils tiers utilises par les scripts
                   (OOSU10.exe, SetTimerResolution.exe, MeasureSleep.exe)
  backup\          Cree au premier lancement — sauvegarde de l'etat initial


DOSSIER old\
------------
Contient les anciens dossiers du pack dont le contenu est desormais integre
dans les scripts automatiques. Conserves a titre d'archive.
  old\2 - Logiciels automatises  OOSU10 (maintenant dans tools\)
  old\4 - Scripts                Scripts originaux (integres dans scripts\)
  old\12 - SetTimerResolution    Exe maintenant dans tools\
  old\manual                     Remplace par les readme.txt par dossier
