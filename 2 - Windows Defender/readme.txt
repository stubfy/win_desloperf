2 - WINDOWS DEFENDER
Desactivation du moteur antivirus en temps reel
================================================

CE QUE CA FAIT
--------------
Windows Defender tourne en permanence en arriere-plan et analyse chaque
fichier ouvert ou execute en temps reel. Sur un PC gaming dedie, ce
comportement consomme des ressources CPU et introduit des acces disque
imprevus pendant les parties, ce qui peut provoquer des stutters.

Ce dossier contient un script PowerShell pour desactiver les six services
qui composent Defender au niveau noyau.

ATTENTION : Desactiver Defender supprime entierement la protection antivirus
en temps reel. A reserver aux machines exclusivement dediees au gaming,
sans navigation web non filtree ni reception de fichiers externes.


POURQUOI LE MODE SANS ECHEC EST OBLIGATOIRE
--------------------------------------------
Sur Windows 11 25H2, Defender est protege par deux mecanismes :
- Tamper Protection : empeche toute modification de la configuration
  Defender depuis un processus normal, meme en administrateur.
- Protected Process Light (PPL) : les services WinDefend et WdFilter
  s'executent en tant que processus proteges, non terminables par le
  gestionnaire de taches ou PowerShell en mode normal.

En Mode Sans Echec, Tamper Protection est inactif et les pilotes minifilter
(WdFilter) ne se chargent pas. La modification du registre devient alors
possible.


SERVICES CONCERNES
------------------
Le script desactive ces six services en mettant leur valeur "Start" a 4
(desactive) dans le registre :

  WinDefend    Service principal Defender (moteur AV)          defaut : 3
  Sense        Microsoft Defender for Endpoint (telemetrie EDR) defaut : 3
  WdFilter     Pilote minifilter — s'insere dans la pile I/O    defaut : 0
  WdNisDrv     Pilote inspection reseau                         defaut : 3
  WdNisSvc     Service inspection reseau                        defaut : 3
  WdBoot       Pilote de demarrage precoce (ELAM)               defaut : 0

WdFilter est particulierement impactant : en tant que minifilter, il
intercepte toutes les operations sur le systeme de fichiers (IRP_MJ_CREATE,
IRP_MJ_READ, etc.) via le Filter Manager (fltmgr.sys). Le desactiver
elimine ce point d'interception dans la pile I/O.


PROCEDURE
---------
1. Ouvrir msconfig (Win+R > msconfig > Entree)
2. Onglet "Demarrage" > cocher "Demarrage securise" > mode Minimal > OK
3. Redemarrer — Windows demarre en Mode Sans Echec
4. Ouvrir PowerShell en administrateur
5. Executer : Set-ExecutionPolicy Bypass -Scope Process
6. Executer le script : .\DisableDefender.ps1
7. Rouvrir msconfig > decocher "Demarrage securise" > OK
8. Redemarrer normalement

Note : sur certaines configurations 25H2, meme en Mode Sans Echec, les
modifications peuvent etre bloquees si Smart App Control est actif. Dans
ce cas, desactiver Smart App Control d'abord via Securite Windows >
Protection contre les applications et les fichiers.


RESTAURATION
------------
Pour reactivater Defender, appliquer les valeurs par defaut :

  WinDefend : Start = 3
  Sense      : Start = 3
  WdFilter   : Start = 0
  WdNisDrv   : Start = 3
  WdNisSvc   : Start = 3
  WdBoot     : Start = 0

Ou utiliser le fichier restore fourni dans ce dossier (meme procedure
Mode Sans Echec requise).
