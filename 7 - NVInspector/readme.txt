7 - NVINSPECTOR
Profils pilote NVIDIA et reglages NIS / DLSS
=============================================

CE QUE CA FAIT
--------------
NVIDIA Profile Inspector Revamped (NVPI-R) donne acces a l'ensemble des
parametres du pilote NVIDIA, y compris ceux non exposes dans le Panneau
de configuration NVIDIA ou NVIDIA App. Il permet de creer et modifier des
profils par jeu avec des options avancees de rendu, de synchronisation et
de latence.

Les fichiers .reg fournis dans ce dossier configurent des options
specifiques de DLSS et NIS independamment de NVPI-R.


FICHIERS .REG FOURNIS
----------------------

1. Disable DLSS UI.reg
   Desactive l'indicateur DLSS a l'ecran (overlay "DLSS" en jeu).
   Cle : HKLM\SOFTWARE\NVIDIA Corporation\Global\NGXCore
   Valeur : ShowDlssIndicator = 0

2. Enable DLSS UI.reg
   Reactive l'indicateur DLSS (pour diagnostic).
   Valeur : ShowDlssIndicator = 0x400

3. New NIS [Default].reg
   Active le nouvel algorithme NIS (NVIDIA Image Scaling v2).
   Cle : HKLM\SYSTEM\CurrentControlSet\Services\nvlddmkm\Parameters\FTS
   Valeur : EnableGR535 = 1
   Compatible : GPU RTX 20 series et plus recents.
   NIS est un algorithme de super-resolution spatiale base sur DLSS 2
   (reseau de neurones adaptatif) ; il produit une image plus nette
   que la version precedente, surtout aux faibles taux d'echelle.

4. Old NIS.reg
   Active l'ancien algorithme NIS (version legacy).
   Valeur : EnableGR535 = 0
   Compatible : GPU GTX 10 series et anterieurs.

Appliquer l'un ou l'autre selon la generation de GPU. Ne pas appliquer
les deux simultanement. Redemarrage non requis mais recommande pour
que le pilote reinitialise le pipeline NIS.

Note : activer NIS dans le Panneau de configuration NVIDIA ou NVIDIA App
est requis avant que les .reg prennent effet (NIS necessite un rafraichissement
de l'affichage que NVPI-R n'effectue pas).


UTILISATION DE NVPI-R
----------------------
1. Ouvrir NVPI-Revamped\NvidiaProfileInspectorRevamped.exe
2. Selectionner un profil dans la liste deroulante (ex: Base Profile,
   ou creer un profil par jeu via "Add Profile")
3. Modifier les parametres desires dans les onglets (Sync, Antialiasing,
   Texture Filtering, etc.)
4. Cliquer "Apply Changes" pour sauvegarder le profil dans le pilote

NVPI-R ecrit directement dans le magasin de profils du pilote NVIDIA
(nvdrsdb.bin) via NvAPI. Les modifications sont persistantes et
s'appliquent a toutes les sessions, independamment de l'utilisateur.


REGLAGE NIS PAR JEU
--------------------
Valeur de nettete recommandee :
  Nouvel NIS (EnableGR535=1) : 10 a 30%
  Ancien NIS (EnableGR535=0) : 10 a 30% (si debruitage a 0%)
                                35 a 55% (si debruitage a 40%)


RESTAURATION
------------
Appliquer les valeurs inverses des .reg (ShowDlssIndicator=0 par defaut,
supprimer la cle EnableGR535). NVPI-R peut restaurer les profils par
defaut via "Reset Profile".
