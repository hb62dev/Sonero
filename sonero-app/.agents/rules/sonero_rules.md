# Reglas Estrictas — Proyecto Sonero

## PROHIBIDO
- ❌ Entregar código con errores de tipos, imports faltantes o sintaxis rota
- ❌ Hacer `git push`, `git commit`, `flutter build` sin que el usuario lo pida
- ❌ Cambiar cosas que el usuario NO pidió
- ❌ Dar excusas — si algo falla, se corrige inmediatamente
- ❌ Hacer cambios parciales o a medias

## OBLIGATORIO
- ✅ Cada cambio solicitado se implementa EXACTAMENTE como se pidió
- ✅ Verificar que el código compila ANTES de reportar como listo (usar `flutter analyze`)
- ✅ Incluir TODOS los imports necesarios en cada archivo modificado
- ✅ Respetar tipos estrictos (`List<Track>`, no `List<dynamic>`)
- ✅ Probar visualmente con el browser agent cuando sea un cambio de UI
- ✅ Un solo intento correcto, no múltiples intentos fallidos

## Contexto Técnico del Proyecto
- **Framework**: Flutter Web (Dart)
- **Servidor local**: `npx serve build/web -l 3000` (puerto 3000)
- **Backend API**: Python uvicorn en puerto 8000
- **Estado**: Provider pattern (`PlayerProvider`, `LibraryProvider`, `SettingsProvider`)
- **Modelo principal**: `Track` de `lib/models/track.dart`
- **Player expandido**: `lib/ui/player/mobile_player_sheet.dart`
- **Biblioteca**: `lib/ui/library/library_page.dart`
- **Mini player**: `lib/ui/player/mini_player.dart`
- **Carrusel cola**: `lib/ui/player/queue_carousel_view.dart`
- **Tema**: `lib/ui/theme.dart` con `context.colors`

## Preferencias del Usuario
- Imagen de canción: siempre cuadrada con esquinas redondeadas
- Reproductor desktop: fullscreen, layout horizontal (cover izq + controles der)
- Animaciones hover: sutiles, casi imperceptibles
- Solo ver cambios en localhost en tiempo real
- NO compilar ni hacer push sin que lo pida
