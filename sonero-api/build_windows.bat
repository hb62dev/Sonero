@echo off
echo Installing PyInstaller and Windows dependencies using virtual environment...
if not exist venv (
  echo Error: Virtual environment 'venv' not found! Please run python -m venv venv first.
  pause
  exit /b 1
)

venv\Scripts\pip.exe install pyinstaller
venv\Scripts\pip.exe install -r requirements.txt
venv\Scripts\pip.exe install -r requirements-win.txt

echo.
echo Building executable using virtual environment...
venv\Scripts\python.exe -m PyInstaller --name "sonero-api" --onefile main.py

echo.
echo Done! The executable is located in the dist\ folder.
pause
