9 - INTERRUPT AFFINITY
Epinglage des interruptions GPU sur un coeur CPU dedie
======================================================

CE QUE CA FAIT
--------------
Par defaut, Windows distribue les interruptions materielles (IRQ) sur
l'ensemble des cœurs logiques du processeur. Les interruptions generees
par le GPU passent donc potentiellement sur des cœurs deja occupes par
des taches de jeu, ce qui cree de la contention et augmente la variance
de latence (jitter).

Ce parametre epingle les interruptions du GPU sur un cœur CPU specifique
et dedie, separant physiquement le traitement des IRQ GPU du thread de
rendu principal.


DETAIL TECHNIQUE
----------------
Les interruptions du GPU transitent par la chaine :
  GPU -> Pont PCI-PCI (PCI Bridge) -> Root Complex PCI -> APIC -> CPU

L'outil intPolicy_x64.exe ecrit une politique d'affinite dans le registre :

  HKLM\SYSTEM\CurrentControlSet\Enum\PCI\<DeviceID>\<InstanceID>\
    Device Parameters\Interrupt Management\Affinity Policy\
      DevicePolicy       = 4  (IrqPolicySpecifiedProcessors)
      AssignmentSetOverride = <bitmask du cœur cible>

DevicePolicy=4 indique au driver de router les DPC vers le cœur specifie
par le bitmask. Par exemple, cœur 2 = bitmask 0x00000004 (bit 2).

Le cœur 2 est recommande car il evite le cœur 0 (utilise par l'OS et
les interruptions systeme) et reste sur un cœur physique distinct en
presence d'Hyper-Threading (cœur 1 logique = paire HT du cœur 0 physique).


RISQUE
------
Un mauvais choix de cœur ou un mauvais peripherique peut augmenter la
latence plutot que la reduire. Identifier precisement la chaine GPU ->
PCI Bridge -> Root Complex avant d'appliquer ce parametre.


PROCEDURE
---------
ETAPE 1 — Identifier le pont PCI du GPU

1. Ouvrir le Gestionnaire de peripheriques (raccourci Gestionnaire.lnk)
2. Menu Affichage > Peripheriques par connexion
3. Localiser la carte graphique dans l'arbre des connexions
4. Identifier le "Pont PCI vers PCI" parent immediat du GPU
5. Clic droit sur ce pont > Proprietes > Details
6. Selectionner "Nom de l'objet du peripherique physique" dans la liste
7. Noter la valeur (ex: \Device\NTPNP_PCI0010)

ETAPE 2 — Configurer l'affinite

1. Ouvrir intPolicy_x64.exe en administrateur
2. Dans la liste, localiser :
   - La carte graphique (GPU)
   - Le pont PCI associe (PCI to PCI Bridge identifie ci-dessus)
   - La racine complexe PCI (PCI Express Root Complex)
3. Pour chacun de ces trois elements, definir l'affinite sur le CPU 2
4. Appliquer et redemarrer


RESTAURATION
------------
Ouvrir intPolicy_x64.exe > selectionner chaque peripherique modifie >
choisir "Default" comme politique d'affinite > appliquer > redemarrer.
