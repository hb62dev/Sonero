@echo off
cd /d "%~dp0"

echo [1/2] Verificando backend en puerto 8000...
powershell -Command "try { (Invoke-WebRequest -Uri 'http://127.0.0.1:8000/health' -UseBasicParsing -TimeoutSec 2).StatusCode } catch { exit 1 }" >nul 2>&1
if %errorlevel% neq 0 (
  echo Iniciando backend Python...
  start /b "" "%~dp0sonero-api\venv\Scripts\python.exe" "%~dp0sonero-api\main.py"
  timeout /t 3 /nobreak >nul
) else (
  echo Backend ya activo y respondiendo.
)

echo [2/2] Abriendo Sonero Desktop...
cd sonero-app
start "" "%~dp0sonero-app\build\windows\x64\runner\Debug\sonero_app.exe"
exit
