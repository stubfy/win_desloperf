8 - GESTIONNAIRE DE PERIPHERIQUES
Economie d'energie USB et suppression des peripheriques inutiles
================================================================

CE QUE CA FAIT
--------------
Windows coupe automatiquement l'alimentation des peripheriques USB
(clavier, souris, concentrateurs) apres une periode d'inactivite pour
economiser de l'energie. Ce comportement peut provoquer des micro-coupures
d'entree ou un delai de reveil perceptible sur les peripheriques de jeu.

Ce dossier contient le raccourci vers le Gestionnaire de peripheriques
et les instructions pour desactiver cette gestion d'energie au niveau
individuel des peripheriques.


DISTINCTION AVEC LE SCRIPT AUTOMATIQUE
---------------------------------------
Le script 11_usb.ps1 (lance par run_all.ps1) desactive la suspension
selective USB au niveau du plan d'alimentation via powercfg. Cette action
agit sur la politique globale du bus USB mais pas sur les nœuds de
peripheriques individuels.

La procedure manuelle ci-dessous agit au niveau de chaque peripherique
dans son DevNode : elle desactive la propriete DEVPROP AllowIdleIrpInD3
sur le nœud specifique, ce qui empeche le pilote hub USB de transmettre
les commandes de suspension a ce peripherique en particulier. Les deux
actions sont complementaires.


PROCEDURE — ECONOMIE D'ENERGIE USB
------------------------------------
1. Ouvrir le Gestionnaire de peripheriques (raccourci Gestionnaire.lnk)
2. Pour chaque peripherique liste ci-dessous :
   - Clic droit > Proprietes > onglet "Gestion de l'alimentation"
   - Decocher "Autoriser l'ordinateur a eteindre ce peripherique
     pour economiser de l'energie"
   - OK

Peripheriques a traiter :
  Claviers
    > Clavier HID / Clavier USB

  Controleurs de bus USB
    > Controleur USB (tous ceux de la liste)

  Peripheriques d'interface utilisateur (HID)
    > Tous les peripheriques HID presentes

  Souris et autres dispositifs de pointage
    > Souris HID / Souris USB


PROCEDURE — DESACTIVATION DES PERIPHERIQUES INUTILES
------------------------------------------------------
Les peripheriques suivants peuvent etre desactives s'ils ne sont pas
utilises, pour supprimer leurs DPC et interruptions associes.

  Controleurs audio, jeu et video :
    > Desactiver ce qui n'est pas utilise (cartes son secondaires,
      controleurs de jeu non connectes)

  Peripheriques systeme :
    > Controleur High Definition Audio (si son USB ou carte son PCI
      dediee utilisee a la place)
    > Intel Management Engine Interface (si gestion a distance non
      requise)
    > Bus redirecteur de peripherique du bureau a distance
    > Enumerateur de lecteur virtuel Microsoft
    > Pilote d'infrastructure de virtualisation Microsoft Hyper-V

  Peripheriques logiciels :
    > Microsoft Root Enum
    > Synthetiseur de table de son Microsoft (si son MIDI non utilise)

Attention : ne desactiver que ce dont vous etes certain de ne pas
avoir besoin. En cas de doute, ne pas toucher — il est toujours possible
de reactivear via Affichage > Afficher les peripheriques caches.


RESTAURATION
------------
Onglet "Gestion de l'alimentation" : recocher la case.
Pour les peripheriques desactives : clic droit > Activer le peripherique.
