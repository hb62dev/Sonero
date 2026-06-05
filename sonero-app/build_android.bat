@echo off
setlocal

echo ========================================================
echo  Construyendo Sonero App (Android APK Nativo)
echo ========================================================

cd /d "%~dp0"

echo [1/1] Compilando APK en Flutter...
call flutter build apk

if %errorlevel% neq 0 (
  echo Error compilando Flutter APK.
  pause
  exit /b 1
)

echo.
echo ========================================================
echo  ¡Compilación del APK Exitosa!
echo  El APK está en: build\app\outputs\flutter-apk\app-release.apk
echo ========================================================
pause
