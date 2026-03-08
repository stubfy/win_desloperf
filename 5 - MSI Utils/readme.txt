5 - MSI UTILS
Activation des interruptions MSI sur les peripheriques
======================================================

CE QUE CA FAIT
--------------
Active le mode MSI (Message Signaled Interrupts) sur les composants
principaux du PC. En mode MSI, les peripheriques communiquent avec le
processeur via des ecritures memoire directes plutot que via des signaux
electriques partages, ce qui reduit la latence de traitement des
interruptions et elimine les conflits d'IRQ.

L'impact concret : moins de DPC (Deferred Procedure Calls) empiles,
frametime plus stable, latence d'entree plus reguliere.


DETAIL TECHNIQUE
----------------
Par defaut, les peripheriques PCI/PCIe utilisent le mode INTx (line-based
interrupts). Dans ce mode, plusieurs peripheriques peuvent partager la meme
ligne d'interruption (IRQ sharing), ce qui oblige le processeur a interroger
chaque peripherique pour savoir lequel a genere l'interruption.

En mode MSI (Message Signaled Interrupts, defini dans la spec PCIe), le
peripherique envoie une ecriture memoire directement a l'adresse cible de
l'APIC (Advanced Programmable Interrupt Controller). Cela :
- Elimine le partage d'IRQ (chaque peripherique a un vecteur unique)
- Reduit le DPC latency (moins d'attente dans la file d'interruptions)
- Permet MSI-X : jusqu'a 2048 vecteurs par peripherique, un par file CPU

Les outils fournis (PCIutil.exe et MSI_util_v3.exe) lisent l'etat MSI
de chaque peripherique et permettent de l'activer ou de le desactiver.


PERIPHERIQUES A ACTIVER
------------------------
Compatibles et recommandes :
  - Carte graphique (GPU)
  - Carte reseau Ethernet
  - Carte reseau WiFi
  - Controleur NVMe (SSD NVMe)
  - Controleurs AHCI SATA recents (SSD et disques SATA)
  - Controleurs USB Intel, AMD ou ASMedia
  - AMD PSP / Intel Management Engine

Risques (a eviter si non maitrise) :
  - Pont PCI vers PCI (PCI to PCI bridge)
  - Intel PCIe Controller (x16)
  - Intel PCI Express Root Port / PCI Express Root Port


A NE PAS ACTIVER — RISQUE DE BSOD
-----------------------------------
  - Cartes d'acquisition ELGATO
  - Controleur High Definition Audio (pilote audio integre)
  - Cartes son Soundblaster, ASUS Xonar, Creative
  - Anciens controleurs USB 1.0 / 1.1 / 2.0 (PC de plus de 10 ans)

Note : si le mode MSI est deja actif sur un controleur USB, c'est que
le pilote le supporte nativement — ne rien modifier dans ce cas.


PROCEDURE
---------
1. Ouvrir MSI_util_v3.exe en administrateur
2. Identifier les peripheriques cibles dans la liste
3. Pour chaque peripherique compatible, cliquer sur la colonne MSI
   et selectionner "MSI" (ou "MSI-X" si disponible)
4. Appliquer et redemarrer le PC
5. Verifier apres redemarrage que les peripheriques fonctionnent
   correctement (son, reseau, USB)

En cas de BSOD au redemarrage : demarrer en Mode Sans Echec et
desactiver le mode MSI sur le dernier peripherique modifie.


RESTAURATION
------------
Ouvrir MSI_util_v3.exe en administrateur, remettre chaque
peripherique en mode "Line Based" (INTx), redemarrer.
