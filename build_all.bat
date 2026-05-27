@echo off
echo ========================================================
echo  Construyendo Sonero App (Windows Full Stack Installer)
echo ========================================================

cd /d "%~dp0"

echo [1/4] Compilando Backend Python (PyInstaller)...
cd sonero-api
call build_exe.bat
if %errorlevel% neq 0 (
  echo Error compilando el backend.
  pause
  exit /b 1
)
cd ..

echo [2/4] Compilando Frontend Flutter (Windows)...
cd sonero-app
set CMAKE_TLS_VERIFY=0
call flutter build windows --release
if %errorlevel% neq 0 (
  echo Error compilando Flutter.
  pause
  exit /b 1
)

echo [3/4] Copiando Backend compilado a la carpeta Release...
mkdir "build\windows\x64\runner\Release\sonero_backend" 2>nul
xcopy "..\sonero-api\dist\sonero_backend" "build\windows\x64\runner\Release\sonero_backend" /E /I /Y

echo [4/4] Creando instalador (Inno Setup)...
:: Asume que iscc está en el PATH de Inno Setup
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" sonero_installer.iss
if %errorlevel% neq 0 (
  echo Error al generar el instalador final con Inno Setup.
  pause
  exit /b 1
)
cd ..

echo.
echo ========================================================
echo  ¡Compilación Exitosa!
echo  El instalador esta en: sonero-app\installers\
echo ========================================================
pause
