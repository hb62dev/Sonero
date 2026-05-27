# 🎵 Shazam API

Microservicio REST en **FastAPI + Python** que escucha audio, identifica canciones con Shazam y las descarga como **MP3 a 320 kbps** desde YouTube.

Dos modos de captura:
- 🖥️ **Audio del sistema** — captura lo que reproduce el PC (Chrome, Spotify, VLC…) sin micrófono
- 🎙️ **Micrófono físico** — como la app de Shazam en el teléfono

---

## Tabla de contenidos

- [Características](#-características)
- [Requisitos](#-requisitos)
- [Instalación](#-instalación)
- [Configuración](#-configuración)
- [Iniciar el servidor](#-iniciar-el-servidor)
- [Referencia de la API](#-referencia-de-la-api)
- [Guía de fuentes de audio](#-guía-de-fuentes-de-audio)
- [Herramientas de diagnóstico](#-herramientas-de-diagnóstico)
- [Modo Batch](#-modo-batch--descargar-tu-librería-de-shazam)
- [Ejemplos con curl](#-ejemplos-con-curl)
- [Solución de problemas](#-solución-de-problemas)
- [Arquitectura](#-arquitectura)
- [Distribución como ejecutable](#-distribución-como-ejecutable)

---

## ✨ Características

| Capacidad | Tecnología |
|---|---|
| 🔍 Reconocimiento de canciones | `shazamio` — misma API que la app oficial |
| 🖥️ Captura de audio del sistema | `pyaudiowpatch` — WASAPI Loopback (sin Stereo Mix) |
| 🎙️ Captura de micrófono | `sounddevice` — cualquier dispositivo de entrada |
| 🔎 Búsqueda en YouTube | `yt-dlp` con `ytsearch1:` |
| ⬇️ Descarga de audio | `yt-dlp` + FFmpeg → **MP3 320 kbps** |
| ⚡ Pipeline asíncrono | Jobs en background, polling por estado |
| 📥 Descarga masiva | Importa historial de Shazam desde CSV |
| 🎛️ Selección de dispositivo | Por request o por `.env` |
| 📋 Documentación interactiva | Swagger UI en `/docs` |

---

## 📋 Requisitos

| Herramienta | Versión | Notas |
|---|---|---|
| Python | **3.12** | 3.13/3.14 no soportados (dependencias nativas) |
| FFmpeg | 7+ | Conversión a MP3 |
| Windows | 7+ | Para WASAPI loopback (`source: "system"`) |

> El modo `source: "mic"` funciona en Windows, macOS y Linux.
> El modo `source: "system"` es exclusivo de Windows (WASAPI).

---

## 🚀 Instalación

### 1. Clonar

```bash
git clone https://github.com/TU_USUARIO/shazam-api.git
cd shazam-api
```

### 2. Python 3.12

Si tienes Python 3.13 o 3.14, instala la versión 3.12 con el launcher de Windows:

```powershell
py install 3.12
py -3.12 --version   # Python 3.12.x
```

### 3. Entorno virtual

```powershell
py -3.12 -m venv venv
```

### 4. Dependencias

```powershell
venv\Scripts\pip install -r requirements.txt
```

### 5. FFmpeg

```powershell
winget install --id Gyan.FFmpeg -e
# Cierra y abre la terminal, luego verifica:
ffmpeg -version
```

---

## ⚙️ Configuración

Crea un archivo `.env` en la raíz del proyecto:

```env
# Puerto del servidor
PORT=8000

# Host: 0.0.0.0 = accesible en red, 127.0.0.1 = solo local
HOST=0.0.0.0

# Dispositivo de micrófono (solo aplica con source: "mic").
# Ejecuta scan_devices.py para encontrar el índice correcto.
# AUDIO_DEVICE=4

# Duración de grabación por defecto en segundos
DEFAULT_LISTEN_DURATION=10
```

### Variables disponibles

| Variable | Default | Descripción |
|---|---|---|
| `HOST` | `0.0.0.0` | Dirección de escucha |
| `PORT` | `8000` | Puerto |
| `AUDIO_DEVICE` | `null` | Índice de dispositivo de micrófono (null = default del sistema) |
| `DEFAULT_LISTEN_DURATION` | `10` | Segundos de grabación por defecto |
| `SAMPLE_RATE` | `44100` | Frecuencia de muestreo en Hz |

---

## ▶️ Iniciar el servidor

```powershell
# Desarrollo (recarga automática al cambiar archivos)
venv\Scripts\python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload

# Producción
venv\Scripts\python main.py
```

Swagger UI disponible en → **http://localhost:8000/docs**

---

## 📡 Referencia de la API

### `POST /api/v1/listen`

Inicia el pipeline completo: **grabar → reconocer → buscar → descargar**.
Devuelve un `job_id` inmediatamente para hacer polling del estado.

**Request body:**

```json
{
  "duration": 10,
  "auto_download": true,
  "source": "system",
  "device_index": null
}
```

| Campo | Tipo | Default | Descripción |
|---|---|---|---|
| `duration` | `int` | `10` | Segundos de grabación |
| `auto_download` | `bool` | `true` | `false` → solo reconoce, no descarga |
| `source` | `"mic"` \| `"system"` | `"mic"` | Fuente de audio (ver [guía](#-guía-de-fuentes-de-audio)) |
| `device_index` | `int \| null` | `null` | Solo para `source: "mic"`. Índice del dispositivo de entrada |

**Response:**

```json
{
  "job_id": "a3f8b2c1",
  "status": "pending",
  "message": "Pipeline iniciado. Escuchando 10s..."
}
```

---

### `GET /api/v1/listen/jobs/{job_id}`

Consulta el estado de un job. Ideal para polling cada 2–3 segundos.

**Estados del pipeline:**

```
pending → listening → recognizing → searching → downloading → done
                                                           ↘ failed
```

| Estado | Descripción |
|---|---|
| `pending` | En cola |
| `listening` | Grabando audio |
| `recognizing` | Enviando a Shazam API |
| `searching` | Buscando en YouTube |
| `downloading` | Descargando y convirtiendo a MP3 |
| `done` | Completado |
| `failed` | Error (ver campo `error`) |

**Response cuando `status: "done"`:**

```json
{
  "job_id": "a3f8b2c1",
  "status": "done",
  "step": "✅ Listo: Ariis - GOZALO",
  "progress": 100,
  "track": {
    "title": "GOZALO",
    "artist": "Ariis",
    "album": "GOZALO - EP",
    "cover_url": "https://is1-ssl.mzstatic.com/...",
    "genre": "Dance",
    "year": "2025",
    "shazam_url": "https://www.shazam.com/track/...",
    "track_key": "726931599"
  },
  "file_path": "C:\\...\\downloads\\Ariis - GOZALO.mp3",
  "error": null
}
```

---

### `GET /api/v1/listen/jobs`

Lista todos los jobs de la sesión actual.

---

### `DELETE /api/v1/listen/jobs/{job_id}`

Elimina un job de la memoria. No elimina el archivo descargado.

---

### `POST /api/v1/batch/from-csv`

Descarga automáticamente toda tu librería de Shazam desde el CSV exportado.

**Formato del CSV (exportado desde la app de Shazam):**

```
Shazam Library
Index,TagTime,Title,Artist,URL,TrackKey
1,2024-01-15 20:30:00,GOZALO,Ariis,https://...,726931599
2,2024-01-16 10:15:00,Flowers,Miley Cyrus,https://...,123456
```

**Cómo exportar:** Shazam app → Perfil → ⚙️ Configuración → Exportar librería Shazam

**Request:** `multipart/form-data`, campo `file` con el CSV.

**Response:**

```json
{
  "job_id": "b4e9c3d2",
  "status": "pending",
  "message": "Batch iniciado. Usa /batch/jobs/{job_id} para ver el progreso."
}
```

---

### `GET /api/v1/batch/jobs/{job_id}`

```json
{
  "job_id": "b4e9c3d2",
  "status": "running",
  "total": 550,
  "completed": 127,
  "failed": 3,
  "current": "🔎 Miley Cyrus - Flowers",
  "errors": ["No encontrado en YouTube: Artista X - Título raro"]
}
```

---

### `GET /api/v1/downloads`

Lista todos los MP3 descargados.

```json
{
  "total": 3,
  "downloads": [
    { "filename": "Ariis - GOZALO.mp3", "size_mb": 8.4, "created_at": 1714000000.0 },
    { "filename": "Miley Cyrus - Flowers.mp3", "size_mb": 9.1, "created_at": 1714001000.0 }
  ]
}
```

---

### `GET /api/v1/downloads/{filename}`

Descarga un archivo MP3 (stream HTTP). Útil para integrarlo con un cliente.

---

### `DELETE /api/v1/downloads/{filename}`

Elimina un archivo MP3 del servidor.

---

### `GET /api/v1/devices`

Lista todos los dispositivos de entrada de audio disponibles.
Úsalo para encontrar el `device_index` correcto para `source: "mic"`.

```json
{
  "current_device": null,
  "current_device_name": "System default",
  "devices": [
    { "index": 0,  "name": "Microsoft Sound Mapper - Input", "channels": 2 },
    { "index": 4,  "name": "Primary Sound Capture Driver",   "channels": 2 },
    { "index": 5,  "name": "Microphone Array (AMD Audio Device)", "channels": 2 }
  ]
}
```

---

### `POST /api/v1/devices/select/{index}`

Cambia el dispositivo de micrófono activo para la sesión actual sin reiniciar el servidor.
Para un cambio permanente, edita `AUDIO_DEVICE` en `.env`.

---

### `GET /health`

```json
{
  "status": "ok",
  "service": "shazam-api",
  "version": "1.0.0",
  "downloads_dir": "C:\\...\\shazam-api\\downloads"
}
```

---

## 🎧 Guía de fuentes de audio

### `source: "system"` — Audio del PC (recomendado)

Captura el audio que está reproduciendo el sistema operativo directamente usando **WASAPI Loopback** vía `pyaudiowpatch`. No necesita micrófono físico ni configuración en Windows.

```
Chrome / Spotify / VLC / cualquier app
        ↓  (señal digital, calidad perfecta)
WASAPI Loopback → Shazam API → YouTube → MP3
```

**JSON:**
```json
{
  "duration": 10,
  "source": "system",
  "auto_download": true
}
```

**Requisitos:**
- Windows 7 o superior (WASAPI viene por defecto)
- Audio reproduciéndose en el PC durante la grabación

**Notas:**
- `device_index` se ignora en este modo — siempre captura del dispositivo de salida por defecto (auriculares/altavoces seleccionados en Windows)
- Si cambias el dispositivo de salida (de auriculares a altavoces), la próxima grabación usará el nuevo dispositivo automáticamente

---

### `source: "mic"` — Micrófono físico

Graba lo que capta el micrófono del sistema. Funcional en Windows, macOS y Linux.

```
Teléfono / TV / altavoz externo (reproduce música)
        ↓  (sonido en el aire)
Micrófono del PC → Shazam API → YouTube → MP3
```

**JSON:**
```json
{
  "duration": 15,
  "source": "mic",
  "device_index": 4
}
```

**Consejos:**
- Sube el volumen de la fuente al máximo posible
- Aleja el PC de ventiladores y ruido de fondo
- Usa `duration: 15` o `20` si la canción no se reconoce a los 10s
- Usa `GET /api/v1/devices` o `scan_devices.py` para encontrar el dispositivo correcto

---

### Elegir el `device_index` correcto

```powershell
# Escanea todos los dispositivos y muestra cuál tiene señal
venv\Scripts\python scan_devices.py
```

Salida de ejemplo:

```
Testing all input devices (2s each) - play audio or speak now!
----------------------------------------------------------------------
  [ 0] Microsoft Sound Mapper - Input           RMS=0.00004  silent
  [ 4] Primary Sound Capture Driver             RMS=0.02627  <-- AUDIO DETECTED!
  [ 5] Microphone Array (AMD Audio Device)      RMS=0.01135  <-- AUDIO DETECTED!
  [16] Stereo Mix (Realtek HD Audio Stereo)     RMS=0.00000  silent
  [17] Microphone (Realtek HD Audio Mic input)  RMS=0.00000  silent
----------------------------------------------------------------------
Usa el índice con AUDIO DETECTED en device_index o en .env
```

Luego en el JSON de `/listen`:

```json
{ "source": "mic", "device_index": 4 }
```

O permanentemente en `.env`:

```env
AUDIO_DEVICE=4
```

---

## 🛠️ Herramientas de diagnóstico

### `scan_devices.py` — Escanear dispositivos de audio

Graba 2 segundos de cada dispositivo de entrada y muestra el nivel de señal (RMS).
Útil para identificar cuál captura audio correctamente.

```powershell
# Habla o pon música mientras corre
venv\Scripts\python scan_devices.py
```

### `test_wasapi.py` — Probar WASAPI loopback

Verifica que el loopback del sistema funciona y guarda `test_loopback.wav`.

```powershell
# Pon audio en el PC antes de ejecutar
venv\Scripts\python test_wasapi.py
```

---

## 📥 Modo Batch — Descargar tu librería de Shazam

Descarga automáticamente todas las canciones de tu historial de Shazam.

### Paso 1: Exportar desde la app

1. Abre Shazam en el teléfono
2. Ve a **Perfil → ⚙️ Configuración → Exportar librería Shazam**
3. Recibirás un email con `shazamlibrary.csv`

### Paso 2: Subir el CSV

Desde Swagger UI (`POST /api/v1/batch/from-csv`) o con curl:

```bash
curl -X POST http://localhost:8000/api/v1/batch/from-csv \
  -F "file=@shazamlibrary.csv"
```

### Paso 3: Monitorear

```bash
# Reemplaza {job_id} con el ID devuelto
curl http://localhost:8000/api/v1/batch/jobs/{job_id}
```

**Tiempo estimado:** ~2 min por canción. Para 550 canciones ≈ 18 horas en background.

> 💡 Deja el servidor corriendo toda la noche con el batch activo.

---

## 💻 Ejemplos con curl

### Audio del sistema (lo que suena en el PC)

```bash
# 1. Pon música en YouTube/Spotify, luego:
curl -X POST http://localhost:8000/api/v1/listen \
  -H "Content-Type: application/json" \
  -d '{"duration": 10, "source": "system", "auto_download": true}'

# 2. Guarda el job_id y consulta cada 3 segundos:
curl http://localhost:8000/api/v1/listen/jobs/{job_id}
```

### Micrófono físico (con música en el ambiente)

```bash
curl -X POST http://localhost:8000/api/v1/listen \
  -H "Content-Type: application/json" \
  -d '{"duration": 15, "source": "mic", "device_index": 4, "auto_download": true}'
```

### Solo reconocer, sin descargar

```bash
curl -X POST http://localhost:8000/api/v1/listen \
  -H "Content-Type: application/json" \
  -d '{"duration": 10, "source": "system", "auto_download": false}'
```

### Listar y descargar archivos

```bash
# Listar todos los MP3
curl http://localhost:8000/api/v1/downloads

# Descargar un archivo específico
curl -OJ http://localhost:8000/api/v1/downloads/Ariis%20-%20GOZALO.mp3

# Eliminar un archivo
curl -X DELETE http://localhost:8000/api/v1/downloads/Ariis%20-%20GOZALO.mp3
```

### Batch CSV

```bash
curl -X POST http://localhost:8000/api/v1/batch/from-csv \
  -F "file=@C:/Users/TU_USUARIO/Downloads/shazamlibrary.csv"
```

---

## 🔧 Solución de problemas

### ❌ "No se reconoció ninguna canción"

| Causa probable | Solución |
|---|---|
| No había audio sonando durante la grabación | Asegúrate que la música esté activa |
| Señal de micrófono débil | Sube el volumen / acerca la fuente |
| Dispositivo de entrada incorrecto | Ejecuta `scan_devices.py` y usa el índice correcto |
| Canción muy poco conocida | Prueba con `duration: 20` o con otra canción |

### ❌ `source: "system"` no captura audio (RMS = 0)

| Causa probable | Solución |
|---|---|
| No hay audio reproduciéndose | Pon música antes de ejecutar `/listen` |
| El dispositivo de salida está en mute | Sube el volumen del sistema |
| Auriculares bluetooth con drivers limitados | Conéctate por cable, o usa altavoces |

### ❌ Error al instalar `shazamio-core` (Rust)

La librería `shazamio` 0.8+ requiere Python ≤ 3.12 para compilar su core nativo:

```powershell
py install 3.12
py -3.12 -m venv venv
venv\Scripts\pip install -r requirements.txt
```

### ❌ `ffmpeg not found`

```powershell
winget install --id Gyan.FFmpeg -e
# Cierra y vuelve a abrir la terminal
ffmpeg -version
```

### ❌ RMS bajo en todos los dispositivos (`scan_devices.py`)

El micrófono puede estar silenciado en Windows:
1. Click derecho en el ícono de volumen → **Sonidos**
2. Pestaña **Grabación**
3. Click derecho en el micrófono → **Propiedades → Niveles**
4. Sube el volumen y desmarca "Silenciar"

### ❌ El servidor no arranca / módulo no encontrado

Asegúrate de estar usando el `venv` correcto:

```powershell
venv\Scripts\python -m uvicorn main:app --reload
# No usar `python` directamente si no está en el PATH del venv
```

---

## 🏗️ Arquitectura

```
shazam-api/
├── main.py                  # Entry point — FastAPI, CORS, lifespan
├── config.py                # Settings con pydantic-settings + .env
├── requirements.txt
├── .env                     # Variables de entorno (gitignored)
├── .gitignore
├── README.md
│
├── routers/
│   ├── listen.py            # POST /listen — pipeline principal con jobs
│   ├── batch.py             # POST /batch/from-csv — descarga masiva
│   ├── downloads.py         # GET/DELETE /downloads — gestión de MP3
│   └── devices.py           # GET /devices — lista dispositivos de audio
│
├── services/
│   ├── recorder.py          # Grabación: mic (sounddevice) + sistema (pyaudiowpatch)
│   ├── recognizer.py        # Reconocimiento con shazamio
│   ├── searcher.py          # Búsqueda en YouTube con yt-dlp ytsearch
│   └── downloader.py        # Descarga MP3 320kbps con yt-dlp + FFmpeg
│
├── schemas/
│   ├── song.py              # Modelo TrackInfo (título, artista, álbum, portada…)
│   └── jobs.py              # Modelos JobStatus y BatchJobStatus
│
├── scan_devices.py          # Utilitario: escanea dispositivos de audio con RMS
│
├── downloads/               # MP3 descargados (gitignored)
└── tmp/                     # Grabaciones WAV temporales (gitignored)
```

### Flujo del pipeline de reconocimiento

```
POST /api/v1/listen
        │
        ▼  [BackgroundTask]
   ┌─────────────┐
   │  recorder   │  source="system" → WASAPI Loopback (pyaudiowpatch)
   │             │  source="mic"    → sounddevice (device_index)
   └──────┬──────┘
          │  WAV temporal
          ▼
   ┌─────────────┐
   │  recognizer │  shazamio → Shazam API → TrackInfo
   └──────┬──────┘
          │  TrackInfo (título, artista, álbum, portada)
          ▼
   ┌─────────────┐
   │  searcher   │  yt-dlp ytsearch1:"Artista - Título" → URL de YouTube
   └──────┬──────┘
          │  URL
          ▼
   ┌─────────────┐
   │  downloader │  yt-dlp descarga stream → FFmpeg → MP3 320kbps
   └──────┬──────┘
          │
          ▼
   JobStatus { status: "done", file_path, track }
```

### Flujo de polling del cliente

```
1. POST /api/v1/listen  →  { "job_id": "a3f8b2c1" }

2. loop cada 2s:
     GET /api/v1/listen/jobs/a3f8b2c1
     → { status: "listening",    progress: 10 }
     → { status: "recognizing",  progress: 35 }
     → { status: "searching",    progress: 55 }
     → { status: "downloading",  progress: 70 }
     → { status: "done",         progress: 100, file_path: "...mp3" }
```

---

## 📦 Stack tecnológico

| Componente | Librería | Versión |
|---|---|---|
| Framework API | `fastapi` | 0.136+ |
| Servidor ASGI | `uvicorn[standard]` | 0.46+ |
| Reconocimiento | `shazamio` | 0.8+ |
| Descarga/búsqueda YouTube | `yt-dlp` | 2026+ |
| Captura de micrófono | `sounddevice` | 0.5+ |
| Captura sistema (WASAPI) | `pyaudiowpatch` | 0.2.12+ |
| Lectura/escritura WAV | `soundfile` | 0.13+ |
| Procesamiento de señal | `numpy` | 2.4+ |
| Conversión MP3 | `ffmpeg` (externo) | 8+ |
| Configuración | `pydantic-settings` | 2+ |

---

## 🗜️ Distribución como ejecutable

Empaqueta el servidor como `.exe` con PyInstaller para distribuirlo sin instalar Python:

```powershell
venv\Scripts\pip install pyinstaller

venv\Scripts\pyinstaller main.py `
  --onefile `
  --name shazam-api `
  --hidden-import uvicorn.logging `
  --hidden-import uvicorn.loops `
  --hidden-import uvicorn.loops.auto `
  --hidden-import uvicorn.protocols `
  --hidden-import uvicorn.protocols.http `
  --hidden-import uvicorn.protocols.http.auto `
  --hidden-import uvicorn.lifespan `
  --hidden-import uvicorn.lifespan.on
```

El resultado será `dist/shazam-api.exe`.

> **Nota:** FFmpeg debe estar instalado en el sistema del usuario final (o incluir `ffmpeg.exe` en la misma carpeta que el `.exe`).

---

## 📄 Licencia

MIT — uso libre para proyectos personales y comerciales.
