# Sonero App 🎵

[English](#english) | [Español](#español)

---

<a name="english"></a>
# Sonero App (English)

> [!IMPORTANT]
> **Direct Compiled Binaries Download**
> 
> *   🚀 **[Download Sonero Windows Installer (Full Installer)](file:///c:/Users/hbriceno/Desktop/sonero/sonero-app/installers/sonero_installer.exe)** (Contains the Flutter player + the Python audio and recognition engine).
> *   📱 **[Download Sonero Android App (.APK)](file:///c:/Users/hbriceno/Desktop/sonero/sonero-app/build/app/outputs/flutter-apk/app-release.apk)** (Lightweight client to sync and play music).
> *   *Note: If you are cloning the repository, the binaries will be generated in these folders after running the compilation commands described below.*

---

Sonero is an intelligent music player designed to optimize your focus, productivity, and emotional state based on the telemetry of your listening habits. It uses artificial intelligence (Gemini API), tempo analysis (BPM), and affective state transitions (Iso-Principle) to adapt the music to your cognitive needs.

---

## ⚙️ System Architecture (Windows vs. Android)

Sonero has a hybrid architecture to efficiently support desktop and mobile platforms:

```mermaid
graph TD
    subgraph Windows ["Windows Client (Full Stack)"]
        FlutterWin["Flutter Windows UI"]
        PyBackend["Local Python Backend - sonero_backend.exe"]
        SQLiteWin[("Local SQLite Database")]
        
        FlutterWin -->|HTTP Requests localhost| PyBackend
        PyBackend -->|Read / Write| SQLiteWin
    end

    subgraph Android ["Android Client (Client Only)"]
        FlutterAndroid["Flutter Android UI"]
    end

    subgraph Cloud ["Cloud / VPS Server (Optional)"]
        CloudBackend["Cloud Python Backend / VPS"]
        SQLiteCloud[("Cloud SQLite Database")]
        
        CloudBackend -->|Read / Write| SQLiteCloud
    end

    FlutterAndroid -->|HTTP Requests - Configurable URL| CloudBackend
    
    %% API External integrations
    PyBackend -->|Shazam API| ShazamAPI["Audio Recognition"]
    PyBackend -->|Gemini API| GeminiAPI["Reports & Natural Context"]
    CloudBackend -->|Shazam API| ShazamAPI
    CloudBackend -->|Gemini API| GeminiAPI
```

*   **Windows (Local Full Stack)**: When starting the Windows application, Flutter automatically launches a local subprocess with the Python backend (`sonero_backend.exe` at `http://127.0.0.1:8000`). All heavy tasks (microphone/system recording, Shazam audio recognition, downloads with `yt-dlp`, and SQLite storage) are resolved on your own machine.
*   **Android (Lightweight Client)**: Android does not run Python locally. Instead, the Android app connects remotely to the Python backend (hosted on your own server, VPS, or your local PC on the same Wi-Fi network). You can configure the backend address in **Settings > API Connection** within the mobile app.

---

## ✨ Key Features

*   🧠 **Focus Score (EF)**: Calculates your concentration level in each session based on the rate of songs listened to without interruption combined with the music's instrumentalness.
*   📈 **Weekly AI Report**: Gemini analyzes your most listened tracks, distractor tracks (early skips), performance by time of day (Morning, Afternoon, Evening/Night), and music genres to write a personalized psychological productivity report.
*   🌊 **Emotional Iso-Principle**: If you are stressed or frustrated, the algorithm generates a 5-song transition queue that gradually decreases energy by 10% per track and increases affective valence to safely bring you to a state of calm.
*   🔄 **Real Google Sync**: Log in securely and synchronize your history and statistics between your Windows PC and your Android device via your Google account.

---

## 🔒 Google Cloud Configuration (OAuth 2.0)

To use account synchronization in your local build or fork:
1. Create a project in the [Google Cloud Console](https://console.cloud.google.com/).
2. Configure the OAuth Consent Screen.
3. Create **OAuth Client ID** credentials for a **Desktop Application**.
4. Copy your **Client ID** and **Client Secret**.
5. Open the Sonero app, navigate to **Settings > Google Cloud Integration** and enter your credentials.

---

## 🛠️ Build Instructions (Developers)

### 🧹 Project Cleanup
If you want to clear Python cache files (`__pycache__`), PyInstaller spec files, and clean Flutter temporary files, double-click or run the script in the root:
```bash
.\build_clean.bat
```

### 1. Full Compilation (Windows Installer)
You can compile and package the Python backend together with the Flutter client into a single final Windows `.exe` installer by running:
```bash
.\build_all.bat
```
*   *Requirements: Install [Inno Setup 6](https://jrsoftware.org/isinfo.php) in the default path (`C:\Program Files (x86)\Inno Setup 6\ISCC.exe`) to package the final installer.*
*   The installer will be generated at: `sonero-app\installers\sonero_installer.exe`

### 2. Compile Python Backend Separately
If you only want to compile the backend executable `sonero_backend.exe` using the virtual environment's Python version:
```bash
cd sonero-api
.\build_exe.bat
```
The executable will be generated at: `sonero-api\dist\sonero_backend\sonero_backend.exe`.

### 3. Compile Android Version (.APK)
To compile the Android mobile application:
1. Ensure you have the Android SDK installed.
2. Enter the frontend folder and compile:
   ```bash
   cd sonero-app
   flutter build apk --release
   ```
The file will be generated at: `sonero-app\build\app\outputs\flutter-apk\app-release.apk`.

### ⚡ Embed OAuth Credentials in Official Build
To generate an official version ready for end-users without requiring them to configure their own Google Client ID/Secret, compile with `--dart-define` parameters:
```bash
cd sonero-app
flutter build windows --release --dart-define=DEFAULT_GOOGLE_CLIENT_ID_WINDOWS=YOUR_CLIENT_ID --dart-define=DEFAULT_GOOGLE_CLIENT_SECRET_WINDOWS=YOUR_CLIENT_SECRET
```

---

<a name="español"></a>
# Sonero App (Español)

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
    subgraph Windows ["Cliente Windows (Full Stack)"]
        FlutterWin["Flutter Windows UI"]
        PyBackend["Backend Python local - sonero_backend.exe"]
        SQLiteWin[("Base de datos SQLite local")]
        
        FlutterWin -->|Peticiones HTTP localhost| PyBackend
        PyBackend -->|Lee / Escribe| SQLiteWin
    end

    subgraph Android ["Cliente Android (Client Only)"]
        FlutterAndroid["Flutter Android UI"]
    end

    subgraph Cloud ["Servidor / Nube (Opcional)"]
        CloudBackend["Backend Python en la Nube / VPS"]
        SQLiteCloud[("Base de datos SQLite en Nube")]
        
        CloudBackend -->|Lee / Escribe| SQLiteCloud
    end

    FlutterAndroid -->|Peticiones HTTP - URL Configurable| CloudBackend
    
    %% API External integrations
    PyBackend -->|Shazam API| ShazamAPI["Reconocimiento de Audio"]
    PyBackend -->|Gemini API| GeminiAPI["Reportes & Contexto Natural"]
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
