@echo off
setlocal enabledelayedexpansion

echo Limpiando entorno anterior...
if exist build_python rmdir /s /q build_python
if exist app.zip del app.zip

echo Creando entorno de empaquetado...
mkdir build_python

echo Copiando codigo fuente...
robocopy . build_python /E /XD build_python venv .git __pycache__ tmp downloads results
:: Robocopy retorna exit codes menores a 8 cuando es exitoso
if %errorlevel% geq 8 exit /b %errorlevel%

echo Instalando dependencias de Python (requirements.txt)...
venv\Scripts\python.exe -m pip install -r requirements.txt --target build_python --platform win_amd64 --python-version 3.12 --only-binary=:all:
venv\Scripts\python.exe -m pip install -r requirements-win.txt --target build_python --platform win_amd64 --python-version 3.12 --only-binary=:all:

echo Empaquetando en app.zip...
cd build_python
..\venv\Scripts\python.exe -c "import shutil; shutil.make_archive('../app', 'zip', '.')"
cd ..

echo Copiando a assets de Flutter...
if not exist "..\sonero-app\assets\app" mkdir "..\sonero-app\assets\app"
copy app.zip "..\sonero-app\assets\app\app.zip"

echo Limpiando temporales...
rmdir /s /q build_python
del app.zip

echo Listo app.zip generado y copiado a Flutter assets.
