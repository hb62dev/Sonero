import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/settings_provider.dart';

class SoneroColors extends ThemeExtension<SoneroColors> {
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color success;
  final Color error;
  final Color textPrimary;
  final Color textSecondary;
  final Color? sidebarBg;
  final LinearGradient gradient;

  const SoneroColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.success,
    required this.error,
    required this.textPrimary,
    required this.textSecondary,
    required this.gradient,
    this.sidebarBg,
  });

  @override
  ThemeExtension<SoneroColors> copyWith({
    Color? bg, Color? surface, Color? surfaceAlt, Color? border,
    Color? success, Color? error, Color? textPrimary, Color? textSecondary,
    Color? sidebarBg, LinearGradient? gradient,
  }) {
    return SoneroColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      success: success ?? this.success,
      error: error ?? this.error,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      sidebarBg: sidebarBg ?? this.sidebarBg,
      gradient: gradient ?? this.gradient,
    );
  }

  @override
  ThemeExtension<SoneroColors> lerp(ThemeExtension<SoneroColors>? other, double t) {
    if (other is! SoneroColors) return this;
    return SoneroColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      sidebarBg: Color.lerp(sidebarBg, other.sidebarBg, t),
      gradient: LinearGradient.lerp(gradient, other.gradient, t) ?? gradient,
    );
  }
}

class AppTheme {
  static ThemeData getTheme(SettingsProvider settings, {required bool isDark}) {
    final accent = settings.accentColor;

    // Dark mode colors
    final bg = isDark ? const Color(0xFF0A0A10) : const Color(0xFFF3F4F6);
    final surface = isDark ? const Color(0xFF111118) : const Color(0xFFFFFFFF);
    final surfaceAlt = isDark ? const Color(0xFF1A1A24) : const Color(0xFFF9FAFB);
    final border = isDark ? const Color(0xFF2A2A38) : const Color(0xFFE5E7EB);
    final textPrimary = isDark ? const Color(0xFFF0F0F8) : const Color(0xFF111827);
    final textSecondary = isDark ? const Color(0xFF8888A8) : const Color(0xFF6B7280);

    const success = Color(0xFF22C55E);
    const error = Color(0xFFEF4444);

    final gradient = LinearGradient(
      colors: [accent, accent.withValues(alpha: 0.6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final soneroColors = SoneroColors(
      bg: bg,
      surface: surface,
      surfaceAlt: surfaceAlt,
      border: border,
      success: success,
      error: error,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      sidebarBg: settings.sidebarColor,
      gradient: gradient,
    );

    final baseTextTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: surface,
        error: error,
      ),
      textTheme: GoogleFonts.interTextTheme(baseTextTheme).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      iconTheme: IconThemeData(color: textSecondary),
      dividerColor: border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      extensions: [soneroColors],
    );
  }
}

extension ThemeContext on BuildContext {
  SoneroColors get colors => Theme.of(this).extension<SoneroColors>()!;
}

