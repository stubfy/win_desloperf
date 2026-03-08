@echo off

set primaryDNS=1.1.1.1
set secondaryDNS=1.0.0.1

for /f "tokens=2 delims=: " %%a in ('ipconfig ^| findstr /i /c:"Carte"') do (
    netsh interface ipv4 set dns name="%%a" static %primaryDNS% primary
    netsh interface ipv4 add dns name="%%a" %secondaryDNS% index=2
)