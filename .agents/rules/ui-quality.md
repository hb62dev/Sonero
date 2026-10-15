# Reglas de UI — Sonero App

## PROHIBIDO: Overflow errors (rayas amarillas/negras)

**NUNCA** se debe hacer un cambio en UI que produzca un error de overflow (`BOTTOM OVERFLOWED BY X PIXELS`, `RIGHT OVERFLOWED`, etc.).

### Cómo prevenir overflow:
1. **Siempre** usar `Expanded`, `Flexible`, o `SingleChildScrollView` dentro de `Column`/`Row` cuando el contenido puede exceder el espacio disponible.
2. **Siempre** considerar el tamaño mínimo del viewport (web mobile, 320px width, ~500px height).
3. **Nunca** poner alturas fijas (`height: X`) en layouts que dependen del tamaño de pantalla sin un `clamp` o `min/max`.
4. **Siempre** envolver listas y contenido dinámico en `SingleChildScrollView` o `ListView`.
5. **Siempre** usar `SafeArea` correctamente para evitar que el contenido se oculte detrás de barras del sistema.
6. **Antes de cada cambio de UI**, verificar mentalmente que el layout funciona en viewport pequeño.

### Si hay overflow:
- Corregir INMEDIATAMENTE antes de mostrar al usuario.
- Usar `SingleChildScrollView` como solución rápida si el contenido es estático.
- Usar `Flexible(child: ...)` si el widget puede reducir su tamaño.
- Usar `overflow: TextOverflow.ellipsis` para textos largos.

## PROHIBIDO: Errores de compilación
- **NUNCA** hacer hot restart/reload sin verificar que el código compila.
- Si un `Map<String, dynamic>` se usa, acceder con `['key']`, NO con `.key`.
- Verificar tipos antes de cada cambio.

## Calidad general
- Cada cambio debe funcionar a la primera. Preguntar si algo no está claro.
- No adivinar, no asumir. Si no se entiende, preguntar.

## PROHIBIDO: Error widgets rojos/amarillos visibles
- **NUNCA** debe verse una pantalla roja de error ni rayas amarillas/negras de overflow en la app.
- `ErrorWidget.builder` en `main.dart` SIEMPRE debe suprimir errores (devolver `SizedBox.shrink()`), incluso en modo debug.
- **NO** usar `if (!kDebugMode)` como condición para suprimir — se suprimen SIEMPRE.
- Los errores se imprimen en consola con `debugPrint` para depuración, pero NUNCA se muestran al usuario.
