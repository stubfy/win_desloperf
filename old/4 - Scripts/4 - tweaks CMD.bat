@echo off
sc stop SysMain
sc config SysMain start= disabled

sc stop DPS
sc config DPS start= disabled

sc stop Spooler
sc config Spooler start= disabled

sc stop TabletInputService
sc config TabletInputService start= disabled

sc stop RmSvc
sc config RmSvc start= disabled

bcdedit /set disabledynamictick yes

powercfg -h off

bcdedit /set bootmenupolicy legacy

sc config DiagTrack start= disabled
sc config dmwappushservice start= disabled

rem Disable Warnings due to Firewall / Defender being disabled
reg add HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance /v Enabled /t REG_DWORD /d 0 /f
reg add "HKLM\Software\Microsoft\Windows Defender Security Center\Notifications" /v DisableNotifications /t REG_DWORD /d 1 /f