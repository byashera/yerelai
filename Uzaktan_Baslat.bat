@echo off
cd /d "%~dp0"
echo YerelAI Studio ve Cloudflare HTTPS Tuneli baslatiliyor...
start "YerelAI Backend" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0kurulum.ps1"
timeout /t 3 /nobreak >nul
if exist "%~dp0.cloudflared\cloudflared.exe" (
  "%~dp0.cloudflared\cloudflared.exe" tunnel --url http://127.0.0.1:8070 --no-autoupdate
) else (
  echo .cloudflared\cloudflared.exe bulunamadi!
)
pause
