@echo off
echo ========================================================
echo  Limpiando archivos de compilacion de Sonero
echo ========================================================

cd /d "%~dp0"

echo [1/3] Limpiando archivos del backend Python...
if exist "sonero-api\build" (
  echo Eliminando carpeta build...
  rmdir /s /q "sonero-api\build"
)
if exist "sonero-api\dist" (
  echo Eliminando carpeta dist...
  rmdir /s /q "sonero-api\dist"
)
if exist "sonero-api\build_python_android" (
  echo Eliminando carpeta build_python_android...
  rmdir /s /q "sonero-api\build_python_android"
)
del /q "sonero-api\*.spec" 2>nul
del /q "sonero-api\python_error.log" 2>nul
del /q "sonero-api\python_startup.log" 2>nul
del /q "python_error.log" 2>nul
del /q "python_startup.log" 2>nul
del /q "sonero-api\tmp\*" 2>nul

echo Eliminando __pycache__ del backend...
for /d /r "sonero-api" %%p in (__pycache__) do (
  if exist "%%p" rmdir /s /q "%%p" 2>nul
)

echo [2/3] Limpiando archivos del frontend Flutter...
cd sonero-app
if exist "build" (
  call flutter clean
) else (
  echo La carpeta build de Flutter ya esta limpia.
)
cd ..

echo [3/3] Limpieza final...
echo.
echo ========================================================
echo  ¡Limpieza Completada con Exito!
echo ========================================================
pause
