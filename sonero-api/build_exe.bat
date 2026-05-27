@echo off
echo ============================================
echo  Compilando Sonero Backend con PyInstaller
echo ============================================

cd /d "%~dp0"

echo Usando venv Python...
venv\Scripts\python.exe -m PyInstaller --noconfirm --onedir --console --name sonero_backend ^
  --hidden-import uvicorn.logging ^
  --hidden-import uvicorn.loops ^
  --hidden-import uvicorn.loops.auto ^
  --hidden-import uvicorn.protocols ^
  --hidden-import uvicorn.protocols.http ^
  --hidden-import uvicorn.protocols.http.auto ^
  --hidden-import uvicorn.protocols.websockets ^
  --hidden-import uvicorn.protocols.websockets.auto ^
  --hidden-import uvicorn.lifespan ^
  --hidden-import uvicorn.lifespan.on ^
  --hidden-import uvicorn.lifespan.off ^
  --hidden-import pydantic ^
  --hidden-import pydantic_core ^
  --hidden-import pydantic_settings ^
  --hidden-import sqlalchemy ^
  --hidden-import sqlalchemy.dialects.sqlite ^
  --hidden-import aiofiles ^
  --hidden-import sounddevice ^
  --hidden-import soundfile ^
  --hidden-import numpy ^
  --hidden-import mutagen ^
  --hidden-import PIL ^
  --hidden-import httpx ^
  --hidden-import yt_dlp ^
  --collect-submodules routers ^
  --collect-submodules schemas ^
  --collect-submodules services ^
  --add-data "routers;routers" ^
  --add-data "schemas;schemas" ^
  --add-data "services;services" ^
  --add-data "config.py;." ^
  --add-data "database.py;." ^
  --add-data "init_db.py;." ^
  --add-data "models.py;." ^
  --add-data ".env;." ^
  main.py

if %errorlevel% neq 0 (
  echo ERROR: PyInstaller fallo.
  pause
  exit /b 1
)

echo.
echo ============================================
echo  sonero_backend.exe listo en dist\sonero_backend\
echo ============================================
pause
