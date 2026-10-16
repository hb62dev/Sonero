# Comandos de Sonero (macOS)

Chuleta para trabajar con Sonero desde la terminal: servidor, Flutter, Android, compilación y acciones de la app.
Todo está pensado para zsh en tu Mac. Los `.bat` de la raíz solo funcionan en Windows.

---

## 0. Preparación (una sola vez)

Las rutas del proyecto son largas y tienen espacios. Guárdalas en variables añadiendo esto a `~/.zshrc`
(cambia las rutas si mueves el proyecto):

```bash
export SONERO="$HOME/Library/Application Support/Claude/scratch-workspaces/fc9d5973-59d2-4fa9-a0c9-852cc38e1907/6357bd5a-d393-4807-842b-f0543bc9f917/scratch-2026-10-09-90bdfb/Sonero-actualizacion"
export SONERO_DATA="$HOME/Library/Application Support/Claude/scratch-workspaces/fc9d5973-59d2-4fa9-a0c9-852cc38e1907/6357bd5a-d393-4807-842b-f0543bc9f917/scratch-2026-10-09-90bdfb/Sonero/sonero-api"
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools:$HOME/Library/Android/sdk/emulator"
export CHROME_EXECUTABLE="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
```

`CHROME_EXECUTABLE` hace que Flutter use Brave para la versión web (no tienes Chrome instalado).

- `SONERO`: el código (repo git, rama `actualizacion`).
- `SONERO_DATA`: donde están tu base de datos (`media.db`), tu música (`downloads/`) y el entorno de Python (`venv/`).

Después, recarga la configuración:

```bash
source ~/.zshrc
```

> ⚠️ Las dos carpetas están dentro de una carpeta temporal de una sesión de Claude. Si se borra esa sesión,
> se borran. Sube la rama a GitHub y copia tu `media.db` y `downloads/` a un lugar fijo
> (p. ej. `~/Development/Sonero`).

---

## 1. Servidor (backend Python)

### Arrancar

Solo en esta computadora (`127.0.0.1:8000`):

```bash
cd "$SONERO/sonero-api" && BASE_DIR="$SONERO_DATA" MUSIC_DIR="$SONERO_DATA/downloads" VIDEO_DIR="$SONERO_DATA/downloads/videos" TMP_DIR="$SONERO_DATA/tmp" RESULTS_DIR="$SONERO_DATA/results" "$SONERO_DATA/venv/bin/python" main.py
```

Accesible desde el móvil por Wi-Fi: el mismo comando con `HOST=0.0.0.0` al principio:

```bash
cd "$SONERO/sonero-api" && HOST=0.0.0.0 BASE_DIR="$SONERO_DATA" MUSIC_DIR="$SONERO_DATA/downloads" VIDEO_DIR="$SONERO_DATA/downloads/videos" TMP_DIR="$SONERO_DATA/tmp" RESULTS_DIR="$SONERO_DATA/results" "$SONERO_DATA/venv/bin/python" main.py
```

> Las variables `BASE_DIR`, `MUSIC_DIR`, etc. son necesarias porque el código y los datos están en
> carpetas distintas. Sin ellas, el servidor crearía una base de datos vacía junto al código.

`Ctrl+C` lo detiene.

### Comprobar, detener y depurar

Ver si está corriendo y qué proceso usa el puerto:

```bash
lsof -nP -iTCP:8000 -sTCP:LISTEN
```

Comprobar que responde:

```bash
curl -s http://127.0.0.1:8000/api/v1/mixes | head -c 300
```

Detener el servidor (si quedó corriendo en segundo plano):

```bash
kill $(lsof -tiTCP:8000 -sTCP:LISTEN)
```

Documentación interactiva de toda la API, para probar endpoints desde el navegador:

```bash
open http://127.0.0.1:8000/docs
```

### Dependencias de Python

```bash
"$SONERO_DATA/venv/bin/pip" install -r "$SONERO/sonero-api/requirements.txt"
```

Opcional, para "Analizar audio" (BPM, energía):

```bash
"$SONERO_DATA/venv/bin/pip" install -r "$SONERO/sonero-api/requirements-audio.txt"
```

### Opciones (`sonero-api/.env` o variables de entorno)

| Variable | Para qué |
|---|---|
| `HOST=0.0.0.0` | Que el móvil pueda conectarse por Wi-Fi |
| `PORT=8000` | Cambiar el puerto |
| `MCP_ENABLED=false` | Desactivar el servidor MCP |
| `MCP_TOKEN=<secreto>` | Exigir contraseña a los agentes IA |

---

## 2. Flutter: lo básico

Ejecuta todo desde la carpeta de la app:

```bash
cd "$SONERO/sonero-app"
```

| Comando | Para qué |
|---|---|
| `flutter pub get` | Instalar dependencias (tras cambiar `pubspec.yaml` o clonar) |
| `flutter analyze` | Buscar errores y avisos sin compilar |
| `flutter test` | Correr los tests de `test/` |
| `flutter gen-l10n` | Regenerar traducciones tras editar `lib/l10n/app_es.arb` |
| `flutter clean && flutter pub get` | Borrar compilaciones viejas; arregla la mayoría de errores raros |
| `flutter pub outdated` | Ver qué paquetes tienen versiones nuevas |
| `flutter doctor -v` | Diagnosticar la instalación (SDK, Android, Xcode, licencias) |
| `flutter upgrade` | Actualizar Flutter |
| `flutter --version` | Versión instalada |

Analizar solo un archivo:

```bash
flutter analyze lib/ui/library/for_you_tab.dart
```

Formatear el código (este proyecto usa líneas de 120 caracteres):

```bash
dart format -l 120 lib/
```

---

## 3. Dispositivos y emuladores

```bash
flutter devices
```

```bash
flutter emulators
```

Abrir tu emulador de Android TV:

```bash
flutter emulators --launch SoneroTV
```

Crear un emulador de teléfono nuevo:

```bash
flutter emulators --create --name SoneroPhone
```

### Móvil Android real

1. En el móvil activa **Opciones de desarrollador** (toca 7 veces "Número de compilación") → **Depuración USB**.
2. Conéctalo por USB y acepta el aviso en el móvil.

```bash
adb devices
```

Depuración inalámbrica (Android 11+): en el móvil, **Depuración inalámbrica → Vincular con código**.

```bash
adb pair IP_DEL_MOVIL:PUERTO_DE_VINCULACION
```

```bash
adb connect IP_DEL_MOVIL:PUERTO
```

Si `adb` se queda colgado:

```bash
adb kill-server && adb start-server
```

---

## 4. Correr la app en desarrollo

```bash
flutter run
```

Si hay varios dispositivos, elige uno con `-d` (el id sale en `flutter devices`):

```bash
flutter run -d SoneroTV
```

En el navegador. Es la forma más rápida de probar la interfaz en tu Mac, porque el proyecto tiene carpeta `web/`.
Se abre en Brave gracias a `CHROME_EXECUTABLE` (sección 0):

```bash
flutter run -d chrome
```

Sin abrir navegador automáticamente (luego abre `http://localhost:5000` en el que quieras):

```bash
flutter run -d web-server --web-port 5000
```

Modos de ejecución:

| Comando | Modo |
|---|---|
| `flutter run` | Debug: hot reload, más lento |
| `flutter run --profile` | Rendimiento real con herramientas de medición |
| `flutter run --release` | Como la versión final, sin hot reload |

Teclas mientras corre `flutter run`:

| Tecla | Acción |
|---|---|
| `r` | Hot reload: aplica cambios de UI al instante, conserva el estado |
| `R` | Hot restart: reinicia la app, pierde el estado |
| `v` | Abrir DevTools (inspector de widgets, rendimiento, red) |
| `p` | Mostrar las guías de layout |
| `c` | Limpiar la pantalla |
| `q` | Salir |

> El hot reload no aplica cambios en `main()`, en `initState` ya ejecutados ni en el código Python.
> Para el servidor, reinícialo (sección 1).

> Esta app no tiene carpeta `macos/` ni `ios/`, así que no corre como app de escritorio Mac ni en iPhone.
> Para añadir el escritorio Mac: `flutter create --platforms=macos .` (crea archivos nuevos; revísalos
> antes de hacer commit).

---

## 5. Conectar la app móvil con el servidor

La app Android no lleva el servidor dentro: se conecta al de tu Mac. La dirección se cambia en la app, en
**Ajustes → Conexión de API**.

| Dónde corre la app | Dirección en Ajustes | Requisito |
|---|---|---|
| Móvil por **USB** | `http://127.0.0.1:8000` | Ejecuta `adb reverse tcp:8000 tcp:8000` (repítelo cada vez que reconectes) |
| Móvil por **Wi-Fi** | `http://IP_DE_TU_MAC:8000` | Servidor arrancado con `HOST=0.0.0.0`; misma red Wi-Fi |
| **Emulador** Android | `http://10.0.2.2:8000` | Nada más (`10.0.2.2` es tu Mac vista desde el emulador) |
| **Chrome** en tu Mac | `http://127.0.0.1:8000` | Nada más |

USB: el móvil usa el servidor del Mac como si fuera suyo:

```bash
adb reverse tcp:8000 tcp:8000
```

Ver la IP de tu Mac en el Wi-Fi:

```bash
ipconfig getifaddr en0
```

Comprobar desde el móvil: abre `http://IP_DE_TU_MAC:8000/docs` en su navegador. Si no carga, revisa
`HOST=0.0.0.0` y que el firewall de macOS permita conexiones entrantes a Python.

---

## 6. Compilar e instalar

Ejecuta todo desde `$SONERO/sonero-app`.

### Android

APK único (funciona en cualquier móvil):

```bash
flutter build apk --release
```

Resultado: `build/app/outputs/flutter-apk/app-release.apk`.

APKs más pequeños, uno por tipo de procesador (para un móvil moderno usa el `arm64-v8a`):

```bash
flutter build apk --release --split-per-abi
```

App Bundle, para publicar en Google Play:

```bash
flutter build appbundle --release
```

Con número de versión (`--build-number` debe subir en cada versión que instales encima de otra):

```bash
flutter build apk --release --build-name=1.1.0 --build-number=2
```

Instalar en el móvil conectado; `-r` conserva los datos de la app:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Compilar e instalar en un paso:

```bash
flutter build apk --release && adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Abrir la carpeta del APK en Finder (para pasarlo por AirDrop, Drive, etc.):

```bash
open build/app/outputs/flutter-apk/
```

> La versión release está firmada con la clave de depuración (`android/app/build.gradle.kts`). Sirve para
> instalarla tú, pero no para Google Play.

### Web

```bash
flutter build web --release
```

Resultado en `build/web/`. Para probarla:

```bash
cd build/web && python3 -m http.server 8080
```

### Windows

Solo se puede compilar en una PC con Windows: `build_all.bat` en la raíz genera el instalador con el
backend incluido. Con credenciales de Google:

```bash
flutter build windows --release --dart-define=DEFAULT_GOOGLE_CLIENT_ID_WINDOWS=TU_ID --dart-define=DEFAULT_GOOGLE_CLIENT_SECRET_WINDOWS=TU_SECRETO
```

---

## 7. Logs y depuración en el móvil

El identificador de la app es `com.example.sonero_app`.

Logs de Flutter (los `print` y errores de Dart):

```bash
flutter logs
```

Logs de Android filtrados por la app (útil si se cierra sola):

```bash
adb logcat --pid=$(adb shell pidof -s com.example.sonero_app)
```

Solo errores:

```bash
adb logcat '*:E'
```

Abrir la app:

```bash
adb shell monkey -p com.example.sonero_app 1
```

Forzar cierre:

```bash
adb shell am force-stop com.example.sonero_app
```

Captura de pantalla del móvil al Mac:

```bash
adb exec-out screencap -p > captura.png
```

Grabar la pantalla del móvil (`Ctrl+C` para parar):

```bash
adb shell screenrecord /sdcard/video.mp4
```

```bash
adb pull /sdcard/video.mp4
```

> ⚠️ Estos dos **borran datos de la app en el móvil** (ajustes, sesión). Úsalos solo si quieres empezar de cero:
> `adb shell pm clear com.example.sonero_app` (borra los datos) y
> `adb uninstall com.example.sonero_app` (desinstala).

---

## 8. Acciones de la app desde la terminal (API)

Todas necesitan el servidor corriendo. Para ver todos los endpoints con sus parámetros: `open http://127.0.0.1:8000/docs`.

### Mixes ("Para ti")

Listar mixes (id, título, número de canciones):

```bash
curl -s http://127.0.0.1:8000/api/v1/mixes | python3 -m json.tool
```

Ver un mix con sus canciones y valoraciones (cambia `13` por el id):

```bash
curl -s http://127.0.0.1:8000/api/v1/mixes/13 | python3 -m json.tool
```

Regenerar los mixes automáticos (lo mismo que "Actualizar mixes"):

```bash
curl -s -X POST http://127.0.0.1:8000/api/v1/mixes/generate
```

Valorar una canción de un mix (`1` me gusta, `0` me da igual, `-1` no me gusta, `null` quitar):

```bash
curl -s -X PUT http://127.0.0.1:8000/api/v1/mixes/13/items/250/rating -H 'Content-Type: application/json' -d '{"rating": 1}'
```

Borrar un mix (no toca tus archivos de música):

```bash
curl -s -X DELETE http://127.0.0.1:8000/api/v1/mixes/13
```

### Biblioteca

Analizar el audio de las canciones nuevas (BPM, energía):

```bash
curl -s -X POST http://127.0.0.1:8000/api/v1/library/analyze
```

Ver el progreso del análisis:

```bash
curl -s http://127.0.0.1:8000/api/v1/library/analyze
```

Buscar artista, álbum, género y año que falten (se revisa desde la app antes de guardar):

```bash
curl -s -X POST http://127.0.0.1:8000/api/v1/library/enrich
```

### Base de datos (solo lectura)

Haz una copia antes de tocar nada:

```bash
cp "$SONERO_DATA/media.db" ~/Desktop/media-backup-$(date +%F).db
```

Explorar la base de datos sin modificarla:

```bash
sqlite3 -readonly "$SONERO_DATA/media.db" ".tables"
```

```bash
sqlite3 -readonly -header -column "$SONERO_DATA/media.db" "SELECT rating, title, artist, mix_title FROM song_ratings ORDER BY updated_at DESC;"
```

### Agente IA (MCP)

Conectar Sonero a Claude Code (una vez):

```bash
claude mcp add --transport http sonero http://127.0.0.1:8000/mcp
```

```bash
claude mcp list
```

Si el servidor se reinició y el agente perdió la conexión, reconéctalo desde el cliente (en Claude Code: `/mcp`).

---

## 9. Git

Ejecuta todo desde `$SONERO`.

```bash
cd "$SONERO"
```

| Comando | Para qué |
|---|---|
| `git status` | Qué archivos cambiaron |
| `git diff` | Ver los cambios línea a línea |
| `git log --oneline -10` | Últimos commits |
| `git add -A && git commit -m "mensaje"` | Guardar los cambios en un commit |
| `git push origin actualizacion` | Subir la rama a GitHub |
| `git pull` | Traer cambios de GitHub |
| `git switch main` | Cambiar a la rama `main` |
| `git stash` / `git stash pop` | Guardar cambios a un lado y recuperarlos |

---

## 10. Problemas comunes

| Síntoma | Solución |
|---|---|
| `Address already in use` al arrancar el servidor | Ya hay uno corriendo: `kill $(lsof -tiTCP:8000 -sTCP:LISTEN)` |
| La biblioteca aparece vacía | Arrancaste el servidor sin las variables `BASE_DIR`/`MUSIC_DIR` (sección 1) |
| El móvil no conecta con el servidor | Revisa la tabla de la sección 5; prueba `/docs` en el navegador del móvil |
| "Para ti necesita el servidor de Sonero" | La app está en modo nativo, sin servidor: configura la URL en Ajustes |
| `ModuleNotFoundError` en Python | Usaste otro Python: usa `"$SONERO_DATA/venv/bin/python"` |
| La compilación de Android falla sin motivo claro | `flutter clean && flutter pub get` y vuelve a compilar |
| `adb: no devices` | Cable o depuración USB; `adb kill-server && adb start-server` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | El APK instalado se firmó con otra clave: desinstala la app (pierdes sus datos) y vuelve a instalar |
| Cambié Python y no se nota | Reinicia el servidor: no tiene recarga automática |
| Cambié Dart y no se nota | `r` (hot reload) o `R` (hot restart) en la terminal de `flutter run` |
