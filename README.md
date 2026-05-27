# Sonero App 🎵

> [!IMPORTANT]
> **Descarga Directa de Binarios Compilados**
> 
> *   🚀 **[Descargar instalador de Sonero para Windows (Full Installer)](file:///c:/Users/hbriceno/Desktop/sonero/sonero-app/installers/sonero_installer.exe)** (Contiene el reproductor Flutter + el motor de audio y reconocimiento en Python).
> *   📱 **[Descargar aplicación de Sonero para Android (.APK)](file:///c:/Users/hbriceno/Desktop/sonero/sonero-app/build/app/outputs/flutter-apk/app-release.apk)** (Cliente ligero para sincronizar y reproducir música).
> *   *Nota: Si estás clonando el repositorio, los binarios se generarán en esas carpetas tras ejecutar los comandos de compilación descritos más abajo.*

---

Sonero es un reproductor inteligente de música diseñado para optimizar tu concentración, productividad y estado emocional en base a la telemetría de tus hábitos de escucha. Utiliza inteligencia artificial (Gemini API), análisis de tempo (BPM) y la transición de estados afectivos (Iso-Principio) para adaptar la música a tus necesidades cognitivas.

---

## ⚙️ Arquitectura del Sistema (Windows vs. Android)

Sonero tiene una arquitectura híbrida para dar soporte a plataformas de escritorio y móviles de forma eficiente:

```mermaid
graph TD
    subgraph Windows [Cliente Windows (Full Stack)]
        FlutterWin[Flutter Windows UI]
        PyBackend[Backend Python local - sonero_backend.exe]
        SQLiteWin[(Base de datos SQLite local)]
        
        FlutterWin -->|Peticiones HTTP localhost| PyBackend
        PyBackend -->|Lee / Escribe| SQLiteWin
    end

    subgraph Android [Cliente Android (Client Only)]
        FlutterAndroid[Flutter Android UI]
    end

    subgraph Cloud [Servidor / Nube (Opcional)]
        CloudBackend[Backend Python en la Nube / VPS]
        SQLiteCloud[(Base de datos SQLite en Nube)]
        
        CloudBackend -->|Lee / Escribe| SQLiteCloud
    end

    FlutterAndroid -->|Peticiones HTTP - URL Configurable| CloudBackend
    
    %% API External integrations
    PyBackend -->|Shazam API| ShazamAPI[Reconocimiento de Audio]
    PyBackend -->|Gemini API| GeminiAPI[Reportes & Contexto Natural]
    CloudBackend -->|Shazam API| ShazamAPI
    CloudBackend -->|Gemini API| GeminiAPI
```

*   **Windows (Full Stack Local)**: Al iniciar la aplicación de Windows, Flutter levanta automáticamente un subproceso local con el backend de Python (`sonero_backend.exe` en `http://127.0.0.1:8000`). Todas las tareas pesadas (grabación del micrófono/sistema, reconocimiento de audio con Shazam, descargas con `yt-dlp` y almacenamiento en SQLite) se resuelven en tu propia máquina.
*   **Android (Cliente Ligero)**: Android no ejecuta Python localmente. En su lugar, la app de Android se conecta de forma remota al backend de Python (alojado en un servidor propio, VPS o tu PC local en la misma red de Wi-Fi). Puedes configurar la dirección del backend en **Ajustes > Conexión de API** en la aplicación móvil.

---

## ✨ Características Principales

*   🧠 **Focus Score (EF)**: Calcula tu nivel de concentración en cada sesión basándose en la tasa de canciones escuchadas sin interrupciones combinada con la instrumentalidad de la música.
*   📈 **Reporte Semanal con IA**: Gemini analiza tus canciones más escuchadas, canciones distractoras (skips tempranos), rendimiento por horas (Mañana, Tarde, Noche) y géneros musicales para redactar un informe de productividad psicológica personalizado.
*   🌊 **Iso-Principio Emocional**: Si estás estresado o frustrado, el algoritmo genera una cola de transición de 5 canciones que disminuye gradualmente la energía en un 10% por pista y aumenta la valencia afectiva para llevarte de forma segura a un estado de calma.
*   🔄 **Sincronización Real con Google**: Inicia sesión de forma segura y sincroniza tu historial y estadísticas entre tu PC Windows y tu dispositivo Android a través de tu cuenta de Google.

---

## 🔒 Configuración de Google Cloud (OAuth 2.0)

Para usar la sincronización de cuenta en tu compilación local o fork:
1. Crea un proyecto en la [Google Cloud Console](https://console.cloud.google.com/).
2. Configura la Pantalla de Consentimiento OAuth (Consent Screen).
3. Crea credenciales de **ID de cliente de OAuth** para **Aplicación de escritorio** (Desktop App).
4. Copia tu **Client ID** y **Client Secret**.
5. Abre la aplicación Sonero, navega a **Ajustes > Integración con Google Cloud** e introduce tus claves.

---

## 🛠️ Instrucciones de Compilación (Desarrolladores)

### 🧹 Limpieza del Proyecto
Si deseas borrar archivos de caché de Python (`__pycache__`), especificaciones de PyInstaller y limpiar temporales de Flutter, haz doble clic o ejecuta el script en la raíz:
```bash
.\build_clean.bat
```

### 1. Compilación Completa (Windows Installer)
Puedes compilar y empaquetar el backend de Python junto con el cliente Flutter en un único instalador final de Windows `.exe` ejecutando:
```bash
.\build_all.bat
```
*   *Requisitos: Tener instalado [Inno Setup 6](https://jrsoftware.org/isinfo.php) en la ruta por defecto (`C:\Program Files (x86)\Inno Setup 6\ISCC.exe`) para empaquetar el instalador final.*
*   El instalador se generará en: `sonero-app\installers\sonero_installer.exe`

### 2. Compilar el Backend Python por separado
Si solo deseas compilar el ejecutable del backend `sonero_backend.exe` usando la versión de Python del entorno virtual:
```bash
cd sonero-api
.\build_exe.bat
```
El ejecutable se generará en: `sonero-api\dist\sonero_backend\sonero_backend.exe`.

### 3. Compilar la versión de Android (.APK)
Para compilar la aplicación móvil de Android:
1. Asegúrate de tener instalado el SDK de Android.
2. Entra a la carpeta del frontend y compila:
   ```bash
   cd sonero-app
   flutter build apk --release
   ```
El archivo se generará en: `sonero-app\build\app\outputs\flutter-apk\app-release.apk`.

### ⚡ Incrustar Credenciales OAuth en Compilación Oficial
Para generar una versión oficial lista para usar donde el usuario final no tenga que configurar su Client ID/Secret de Google, compila con parámetros `--dart-define`:
```bash
cd sonero-app
flutter build windows --release --dart-define=DEFAULT_GOOGLE_CLIENT_ID_WINDOWS=TU_CLIENT_ID --dart-define=DEFAULT_GOOGLE_CLIENT_SECRET_WINDOWS=TU_CLIENT_SECRET
```
