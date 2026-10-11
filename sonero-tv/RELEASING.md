# Publicar Sonero TV

## Una sola vez: crear la clave de firma

Android solo instala una actualización encima de la app existente si está firmada con **la misma clave**. Si la clave se pierde, cada persona tendría que desinstalar y volver a instalar. Guárdala fuera del repo y con copia de seguridad (por ejemplo, en un gestor de contraseñas).

```bash
keytool -genkeypair -v -keystore ~/sonero-keys/sonero-tv-release.jks \
  -keyalg RSA -keysize 4096 -validity 10000 -alias sonero-tv
```

Para compilar en tu computadora, crea `sonero-tv/android/key.properties` (está en `.gitignore`):

```properties
storeFile=/Users/<tú>/sonero-keys/sonero-tv-release.jks
storePassword=…
keyAlias=sonero-tv
keyPassword=…
```

Para que GitHub publique las versiones, añade en **Settings → Secrets and variables → Actions**:

| Secreto | Valor |
|---|---|
| `TV_KEYSTORE_BASE64` | `base64 -i ~/sonero-keys/sonero-tv-release.jks` |
| `TV_KEYSTORE_PASSWORD` | contraseña del keystore |
| `TV_KEY_ALIAS` | `sonero-tv` |
| `TV_KEY_PASSWORD` | contraseña de la clave |

## Cada versión

1. Sube la versión en `sonero-tv/pubspec.yaml` (`version: 1.1.0+2`: el número tras `+` siempre debe crecer).
2. Haz commit y crea la etiqueta: `git tag tv-v1.1.0 && git push origin tv-v1.1.0`.
3. El flujo `.github/workflows/sonero-tv-release.yml` compila, firma y publica `sonero-tv-1.1.0.apk` en Releases.

Antes de publicar, revisa que el backend siga siendo compatible con las TVs que ya tienen la versión anterior (ver "Compatibilidad entre versiones" en el README).
