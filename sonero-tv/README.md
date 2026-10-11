# Sonero TV 📺

App para **Android TV / Google TV** que reproduce tu biblioteca de Sonero en el televisor por WiFi, **sin internet**. La música sigue en tu computadora; la TV la reproduce en tiempo real desde ella.

## Qué hace

- **Encuentra sola** la computadora con Sonero en la red (o escribes su IP).
- **Emparejamiento con PIN**: solo las TVs que tú autorizas pueden escuchar tu música.
- Navegas la biblioteca y las playlists con el **control remoto** (flechas + OK, y los botones multimedia).
- **"Reproducir en TV"** desde Sonero en la computadora, y control (pausa, siguiente, volumen) desde la computadora o desde el **celular** en `http://<IP-de-la-computadora>:8091`.
- **Letras sincronizadas** (guardadas en la computadora, funcionan sin internet).
- **Modo ambiente**: tras 25 s sin tocar el control, portada difuminada, reloj y la línea de la letra actual.
- **Estadísticas** de escucha; lo que suena en la TV cuenta en las estadísticas de Sonero (y en su servidor MCP).

## Instalar en el televisor

La app no está en Google Play: se instala una vez desde la Release de GitHub.

1. En la TV: **Ajustes → Privacidad/Seguridad → Apps de fuentes desconocidas** y permite la app con la que vas a instalar.
2. Opción A (sin cables): instala **Downloader** (de AFTVnews) desde Google Play en la TV, abre la URL del `.apk` de la última Release y pulsa *Instalar*.
   Opción B (desde la computadora): activa *Depuración por red* en la TV y ejecuta
   `adb connect <IP-de-la-TV>` y luego `adb install sonero-tv-X.Y.Z.apk`.
3. Abre **Sonero TV** desde el inicio de la TV.

## Conectar

1. En la computadora: **Sonero → Compartir → TV**, activa **Sonero TV** y pulsa **Emparejar TV**.
2. En la TV: elige tu computadora en la lista y escribe el PIN de 6 dígitos.

Requisitos: la TV y la computadora en la **misma red WiFi** (no hace falta que tenga internet), y Sonero abierto en la computadora. Si usas una VPN en la computadora, puede bloquear la conexión.

## Compatibilidad entre versiones

La TV habla con la computadora mediante un protocolo versionado (`api` en `GET /tv/info`, hoy `1`). Reglas para no obligar a reinstalar:

- El backend (`sonero-api/services/tv_server.py`) **solo añade** campos y endpoints dentro de `api: 1`; nunca quita ni cambia el significado de los existentes.
- Un cambio incompatible sube a `api: 2` y el backend debe seguir sirviendo `api: 1` mientras existan TVs con la versión anterior.
- La app ignora campos y comandos que no conoce.

## Desarrollo

```bash
flutter pub get
flutter run            # con un emulador de Android TV o una TV con depuración activada
```

El servidor está en `sonero-api/services/tv_server.py` (puerto 8091, descubrimiento UDP 8092).

## Publicar una versión

Ver [RELEASING.md](RELEASING.md).
