6 - MOUSE ACCEL FIX
Suppression de l'acceleration souris (fix MarkC)
=================================================

CE QUE CA FAIT
--------------
Windows applique par defaut une acceleration dynamique au mouvement du
curseur : plus la souris est deplacee rapidement, plus le curseur parcourt
une distance importante par rapport a la distance physique reelle. Ce
comportement rend impossible de developper une memoire musculaire fiable
pour les jeux, puisque le meme mouvement physique peut donner des resultats
differents selon la vitesse d'execution.

Ce fix remplace les courbes d'acceleration par des valeurs lineaires,
garantissant un rapport 1:1 strict entre le deplacement physique de la
souris et le deplacement du curseur a l'ecran.


DETAIL TECHNIQUE
----------------
Windows calcule le deplacement du curseur en appliquant deux courbes de
Bezier stockees dans le registre :

  HKCU\Control Panel\Mouse
    SmoothMouseXCurve  (courbe horizontale — 40 octets)
    SmoothMouseYCurve  (courbe verticale — 40 octets)
    MouseSpeed         (0 = acceleration desactivee, 1 ou 2 = activee)
    MouseThreshold1    (seuil d'acceleration basse vitesse)
    MouseThreshold2    (seuil d'acceleration haute vitesse)

Le fix MarkC remplace ces courbes par des segments lineaires calcules
specifiquement pour chaque niveau de scaling d'affichage (DPI Windows).
Cette precision est necessaire parce que Windows applique une mise a
l'echelle supplementaire au mouvement du curseur en fonction du rapport
entre la resolution logique et la resolution physique de l'ecran.

Le script automatique (02_registry.ps1 via tweaks_consolidated.reg)
applique deja le fix pour un scaling a 100%. Ce dossier est uniquement
necessaire pour les autres niveaux de scaling.


QUEL FICHIER .REG APPLIQUER
----------------------------
Ouvrir Parametres > Systeme > Affichage et verifier le pourcentage
d'echelle affiche pour votre ecran principal.

  100%  -> Deja applique par les scripts automatiques
  125%  -> Ouvrir le dossier "Windows 10 Fixes" > appliquer le .reg 125%
  150%  -> Ouvrir le dossier "Windows 10 Fixes" > appliquer le .reg 150%
  175%  -> Ouvrir le dossier "Windows 10 Fixes" > appliquer le .reg 175%
  200%  -> Ouvrir le dossier "Windows 10 Fixes" > appliquer le .reg 200%

Double-cliquer sur le fichier .reg correspondant et confirmer la fusion.
Deconnexion/reconnexion de session requise pour que le changement
prenne effet.


RESTAURATION
------------
Appliquer le fichier Windows_10+8.x_Default.reg a la racine de ce
dossier pour revenir aux valeurs d'acceleration Windows par defaut.


NOTE SUR WINDOWS 11
-------------------
Windows 11 22H2+ propose une option "Precision du pointeur amelioree"
dans Parametres > Bluetooth et peripheriques > Souris > Parametres
supplementaires de la souris. Cette option est equivalente au fix pour
le scaling 100%, mais le fix MarkC reste plus precis pour les autres
niveaux de scaling.
