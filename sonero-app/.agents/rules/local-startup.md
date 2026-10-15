# Regla: Arranque Local del Proyecto Sonero

Cuando el usuario pida **ejecutar/arrancar/correr el proyecto en local**, SIEMPRE se deben levantar **ambos servicios** en este orden:

## 1. Backend API (sonero-api)

```powershell
& "c:\Users\dsant\OneDrive\Desktop\sonero\sonero-api\venv\Scripts\python.exe" -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

- Directorio de trabajo: `c:\Users\dsant\OneDrive\Desktop\sonero\sonero-api`
- Se ejecuta como daemon (background)
- Esperar a que responda en `http://127.0.0.1:8000/health` antes de continuar
- Es un servidor FastAPI con Uvicorn

## 2. Frontend Flutter (sonero-app)

```powershell
flutter run -d web-server --web-port=3005 --web-hostname=localhost
```

- Directorio de trabajo: `c:\Users\dsant\OneDrive\Desktop\sonero\sonero-app`
- Se ejecuta como daemon (background)
- El frontend espera el backend en `http://127.0.0.1:8000`
- El usuario espera ver la app en `http://localhost:3005`

## Notas importantes

- **Siempre** levantar el backend PRIMERO, luego el frontend.
- Las rutas con espacios deben ir entre comillas y usar `&` en PowerShell.
- El backend usa un virtualenv de Python ubicado en `sonero-api\venv\`.
- NO correr Flutter en modo Windows (`-d windows`) porque requiere Developer Mode habilitado.
- NO correr con `-d chrome` (abre una ventana nueva), usar `-d web-server` para servir en el puerto.
- El usuario se refiere a esto como "correr en localhost" o "ejecutar en local".
- El puerto del frontend es **3005**, NO 3000.
- CORS del backend ya incluye `localhost:3005` y `127.0.0.1:3005`.
