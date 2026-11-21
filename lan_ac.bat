@echo off
chcp 65001 >nul
echo ========================================================
echo  SEN.AI - Yerel Wi-Fi (LAN) Port 8070 Erisim Acici
echo ========================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [UYARI] Yonetici izni gerekli!
    echo Lutfen bu dosyaya SAG TIKLAYIP "Yonetici olarak calistir" secin.
    echo.
    pause
    exit /b 1
)
echo [1/2] Ethernet ag profili Ozel (Private) yapiliyor...
powershell -NoProfile -Command "Get-NetConnectionProfile -InterfaceAlias 'Ethernet' -ErrorAction SilentlyContinue | Set-NetConnectionProfile -NetworkCategory Private"
echo [2/2] Windows Guvenlik Duvari'nda TCP 8070 izni ekleniyor...
netsh advfirewall firewall delete rule name="YerelAI Studio LAN 8070" >nul 2>&1
netsh advfirewall firewall delete rule name="SEN.AI LAN 8070" >nul 2>&1
netsh advfirewall firewall add rule name="SEN.AI LAN 8070" dir=in action=allow protocol=TCP localport=8070 profile=private,domain
echo.
echo TAMAMLANDI! Ayni Wi-Fi agindaki telefondan su adresi acabilirsiniz:
echo   http://192.168.1.22:8070
echo.
pause
