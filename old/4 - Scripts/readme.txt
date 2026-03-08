Si right click > run avec powershell ne fonctionne pas, à executer an admin pour utiliser les scripts ps1 :

Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass


pour les scripts ps1 il faut utiliser cd avec une fenetre powershell admin et run avec ./nomduscript.ps1