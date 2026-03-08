10 - NETWORK WIP
Optimisation avancee de la carte reseau (NIC)
=============================================

CE QUE CA FAIT
--------------
Desactive les fonctionnalites de la carte reseau congues pour les serveurs
et les environnements multi-connexions, qui introduisent du batching et
de la latence supplementaire sur un PC gaming avec une seule connexion active.

Inclut egalement TCP Optimizer (outil tiers) pour regler les parametres
de la pile TCP/IP Windows.


DETAIL TECHNIQUE
----------------
Les offloads NIC deplacent du traitement TCP/IP vers le firmware de la
carte reseau pour reduire la charge CPU sur les serveurs. Sur un PC gaming :

- Large Send Offload (LSO) : regroupe plusieurs paquets TCP sortants en
  un seul segment avant de les envoyer. Reduit les interruptions mais
  augmente la latence de chaque paquet individuel.

- Interrupt Moderation : regroupe plusieurs interruptions NIC en une
  seule avant de les remonter au CPU. Tres utile a 10 Gbps, nuisible
  en gaming (delai supplementaire entre reception du paquet et traitement).

- Receive/Transmit Buffers : taille du ring buffer DMA entre le NIC et
  la memoire systeme. A 2048, on evite les drops sous charge tout en
  limitant la latence de remplissage du buffer.

- Flow Control (PAUSE frames) : mecanisme de regulation du debit entre
  le NIC et le switch. Peut introduire des pauses artificielles.

- Energy Efficient Ethernet (EEE) : met le transceiver en veille lors
  des periodes de faible activite. Provoque des pics de latence au reveil.

Les reglages ci-dessous ciblent specifiquement le Intel I226-V. Les noms
exacts des parametres peuvent varier selon la carte reseau installee.


PROCEDURE — GESTIONNAIRE DE PERIPHERIQUES
------------------------------------------
1. Ouvrir le Gestionnaire de peripheriques
2. Cartes reseau > clic droit sur l'adaptateur > Proprietes
3. Onglet "Avance" — appliquer les valeurs suivantes :

  ARP Offload                    : Desactive
  DMA Coalescing                 : Desactive
  Enable PME                     : Desactive
  Energy Efficient Ethernet      : Desactive
  Flow Control                   : Desactive
  Interrupt Moderation           : Desactive
  Interrupt Moderation Rate      : Off
  IPv4 Checksum Offload          : Active (Rx et Tx)
  Large Send Offload V2 (IPv4)   : Desactive
  Large Send Offload V2 (IPv6)   : Desactive
  Log Link State Event           : Desactive
  NS Offload                     : Desactive
  Packet Priority & VLAN         : Desactive
  Receive Buffers                : 2048
  Selective Suspend              : Desactive
  Selective Suspend Idle Timeout : 5
  Speed & Duplex                 : Choisir la vitesse correspondant
                                   au port Ethernet du routeur
                                   (eviter Auto-Negotiation si possible)
  TCP Checksum Offload IPv4      : Rx & Tx Active
  TCP Checksum Offload IPv6      : Rx & Tx Active
  Transmit Buffers               : 2048
  UDP Checksum Offload IPv4      : Rx & Tx Active
  UDP Checksum Offload IPv6      : Rx & Tx Active
  Wait for Link                  : Off
  Wake from S0ix on Magic Packet : Desactive
  Wake on Link Settings          : Desactive
  Wake on Magic Packet           : Desactive
  Wake on Pattern Match          : Desactive

4. Onglet "Gestion de l'alimentation" :
   Decocher "Autoriser l'ordinateur a eteindre ce peripherique
   pour economiser de l'energie"


PROCEDURE — TCP OPTIMIZER
--------------------------
1. Ouvrir TCPOptimizer.exe en administrateur
2. Appliquer les reglages du profil Export.spg fourni dans ce dossier
   (File > Load Settings > selectionner Export.spg)
3. Ajuster le MTU selon ce que propose votre FAI
   (generalement 1500 pour Ethernet standard, 1492 pour PPPoE)
4. Cliquer "Apply Changes" et redemarrer

Le profil FirstBackup.spg contient les valeurs TCP d'origine enregistrees
lors de la premiere utilisation — l'appliquer pour restaurer les reglages
TCP par defaut.


RESTAURATION
------------
Onglet "Avance" du NIC : cliquer "Restore Defaults" ou "Restaurer les
parametres par defaut" si disponible, sinon remettre chaque valeur
manuellement.
TCP : appliquer FirstBackup.spg dans TCP Optimizer.
