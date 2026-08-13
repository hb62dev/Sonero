@echo off
echo ========================================================
echo  Construyendo Sonero App (Windows Full Stack Installer)
echo ========================================================

cd /d "%~dp0"

echo [1/4] Compilando Backend Python (PyInstaller)...
cd ..\sonero-api
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

echo [3/4] Copiando Backend compilado, DLLs de C++ y FFmpeg a la carpeta Release...
mkdir "build\windows\x64\runner\Release\sonero_backend" 2>nul
xcopy "..\sonero-api\dist\sonero_backend" "build\windows\x64\runner\Release\sonero_backend" /E /I /Y

echo Copiando DLLs de C++ para la aplicacion y el backend...
copy "C:\Windows\System32\vcruntime140.dll" "build\windows\x64\runner\Release\" /Y
copy "C:\Windows\System32\vcruntime140_1.dll" "build\windows\x64\runner\Release\" /Y
copy "C:\Windows\System32\msvcp140.dll" "build\windows\x64\runner\Release\" /Y
copy "C:\Windows\System32\vcruntime140.dll" "build\windows\x64\runner\Release\sonero_backend\" /Y
copy "C:\Windows\System32\vcruntime140_1.dll" "build\windows\x64\runner\Release\sonero_backend\" /Y
copy "C:\Windows\System32\msvcp140.dll" "build\windows\x64\runner\Release\sonero_backend\" /Y

echo Buscando y copiando FFmpeg...
for /f "delims=" %%i in ('where.exe ffmpeg 2^>nul') do set FFMPEG_PATH=%%i
for /f "delims=" %%i in ('where.exe ffprobe 2^>nul') do set FFPROBE_PATH=%%i

if not "%FFMPEG_PATH%"=="" (
  echo Copiando ffmpeg.exe desde %FFMPEG_PATH%...
  copy "%FFMPEG_PATH%" "build\windows\x64\runner\Release\sonero_backend\" /Y
) else (
  echo WARNING: ffmpeg.exe no se encontro en el PATH.
)
if not "%FFPROBE_PATH%"=="" (
  echo Copiando ffprobe.exe desde %FFPROBE_PATH%...
  copy "%FFPROBE_PATH%" "build\windows\x64\runner\Release\sonero_backend\" /Y
) else (
  echo WARNING: ffprobe.exe no se encontro en el PATH.
)


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
