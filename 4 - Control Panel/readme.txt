4 - CONTROL PANEL
Reglages manuels via l'interface Windows
=========================================

CE QUE CA FAIT
--------------
Certains parametres Windows ne sont accessibles qu'a travers l'interface
graphique — soit parce qu'ils dependent d'une session utilisateur active,
soit parce qu'ils passent par des API WinRT non exposees en ligne de
commande, soit parce qu'ils modifient des parametres par composant (par
ecran, par application) qui ne se generalisent pas en une seule cle registre.

Ce dossier contient des raccourcis vers chaque page de reglage concernee.
Ouvrir chaque raccourci et appliquer le reglage indique ci-dessous.


LISTE DES REGLAGES A APPLIQUER
-------------------------------

0 - Planificateur graphique (ms-settings:display-advancedgraphics)
    Activer "Planification GPU avec acceleration materielle" (HAGS).
    Reduit la latence d'entree sur GPU NVIDIA GTX 1000+ et AMD RX 5000+
    en permettant au GPU de gerer lui-meme l'ordonnancement de ses tampons.
    Technique : active HwSchMode=2 dans HKLM\SYSTEM\CurrentControlSet\
    Control\GraphicsDrivers, ce qui confie l'ordonnancement des frames
    au pilote GPU plutot qu'au scheduler Windows.

1 - Notifications (ms-settings:notifications)
    Desactiver "Ne pas deranger", desactiver "Concentration", onglet
    Parametres supplementaires : tout decocher.
    Empeche les interruptions pendant les parties et supprime les DPC
    lies a l'affichage des toasts de notification.

2 - Stockage (ms-settings:storagesense)
    Desactiver le nettoyage automatique (Storage Sense).
    Evite les acces disque en arriere-plan pendant les sessions de jeu.

3 - Couleurs (ms-settings:colors)
    Mode sombre, desactiver la transparence, couleur d'accentuation
    noire, desactiver l'accentuation sur la barre des taches, activer
    l'accentuation sur les barres de titre.
    La transparence (DWM blur) consomme du GPU ; la desactiver reduit
    la charge graphique du bureau.

4 - Applications installees (ms-settings:appsfeatures)
    Supprimer les applications pre-installees encore presentes
    (celles non retirees automatiquement par le script 08_debloat.ps1
    car elles varient selon les editions Windows).

5 - Loupe (ms-settings:easeofaccess-magnifier)
    Desactiver la loupe Windows si elle n'est pas utilisee.

6 - Confidentialite (ms-settings:privacy)
    Verifier que tout ce qui precede "Autorisations des applications"
    est desactive : diagnostics, encre et frappe, historique d'activite,
    publicites, etc.

7 - Effets visuels
    Suivre la capture d'ecran fournie (Effets Visuels Settings.png).
    Panneau de configuration > Systeme > Parametres systeme avances >
    Avance > Performances > Parametres.
    Choisir "Ajuster afin d'obtenir les meilleures performances", puis
    recocher uniquement "Afficher les vignettes" et "Lisser les polices
    de caracteres a l'ecran" pour garder une lisibilite correcte.
    Desactiver les animations reduit les DPC du gestionnaire de fenetres
    (DWM) et les redraws inutiles de l'interface.

8 - Options d'alimentation
    Selectionner le plan "Ultimate Performance" (ajoute par run_all.ps1).
    Desactiver la mise en veille.
    Technique : ce plan desactive les etats C-states profonds et les
    transitions P-state agressives, maintenant le CPU a sa frequence
    maximale en permanence pour eliminer la latence de reveil du processeur.

9 - Pare-feu
    Desactiver le pare-feu Windows si un autre pare-feu est en place,
    ou conserver si c'est la seule protection reseau active.

10 - Accessibilite clavier (ms-settings:easeofaccess-keyboard)
    Desactiver les touches remanentes (Sticky Keys).
    Activer la touche Impr Ecran pour ouvrir l'outil capture.

11 - Barre des taches (ms-settings:taskbar)
    Ajuster le comportement de la barre des taches selon preference.
    Activer l'affichage des secondes dans l'horloge (tout en bas des
    options de la page).
