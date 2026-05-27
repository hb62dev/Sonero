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
  final Color glassSurface;
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
    required this.glassSurface,
    required this.gradient,
    this.sidebarBg,
  });

  @override
  ThemeExtension<SoneroColors> copyWith({
    Color? bg, Color? surface, Color? surfaceAlt, Color? border,
    Color? success, Color? error, Color? textPrimary, Color? textSecondary,
    Color? glassSurface, Color? sidebarBg, LinearGradient? gradient,
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
      glassSurface: glassSurface ?? this.glassSurface,
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
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t)!,
      sidebarBg: Color.lerp(sidebarBg, other.sidebarBg, t),
      gradient: LinearGradient.lerp(gradient, other.gradient, t) ?? gradient,
    );
  }
}

class AppTheme {
  static ThemeData getTheme(SettingsProvider settings, {required bool isDark}) {
    final accent = settings.accentColor;

    final bg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF3F4F6); // Slightly lighter black for solid dark
    final surface = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);
    final surfaceAlt = isDark ? const Color(0xFF242424) : const Color(0xFFF9FAFB);
    final glassSurface = surface; // No more glass, just use surface
    final border = isDark ? const Color(0xFF333333) : const Color(0xFFC7CBD1); // Darker, more solid borders in light mode
    final textPrimary = isDark ? const Color(0xFFF0F0F8) : const Color(0xFF1C1C1E); // Softer black for better readability
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF636366); // Apple-like secondary gray

    const success = Color(0xFF22C55E);
    const error = Color(0xFFEF4444);

    final gradient = LinearGradient(
      colors: [accent, accent.withValues(alpha: 0.8)],
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
      glassSurface: glassSurface,
      sidebarBg: isDark ? const Color(0xFF141414) : const Color(0xFFF9FAFB), // Very light gray sidebar
      gradient: gradient,
    );

    final baseTextTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        primary: accent, // Explicitly set primary
        secondary: accent, // Explicitly set secondary to avoid faint tonal generation
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: surface,
        error: error,
      ),
      textTheme: GoogleFonts.interTextTheme(baseTextTheme).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ).copyWith(
        bodyLarge: GoogleFonts.inter(textStyle: baseTextTheme.bodyLarge, fontWeight: FontWeight.w500, color: textPrimary),
        bodyMedium: GoogleFonts.inter(textStyle: baseTextTheme.bodyMedium, fontWeight: FontWeight.w500, color: textPrimary),
        bodySmall: GoogleFonts.inter(textStyle: baseTextTheme.bodySmall, fontWeight: FontWeight.w400, color: textSecondary),
        titleMedium: GoogleFonts.inter(textStyle: baseTextTheme.titleMedium, fontWeight: FontWeight.w600, color: textPrimary),
        titleSmall: GoogleFonts.inter(textStyle: baseTextTheme.titleSmall, fontWeight: FontWeight.w500, color: textSecondary),
        labelLarge: GoogleFonts.inter(textStyle: baseTextTheme.labelLarge, fontWeight: FontWeight.w500, color: textPrimary),
        labelMedium: GoogleFonts.inter(textStyle: baseTextTheme.labelMedium, fontWeight: FontWeight.w500, color: textSecondary),
        labelSmall: GoogleFonts.inter(textStyle: baseTextTheme.labelSmall, fontWeight: FontWeight.w400, color: textSecondary),
      ),
      iconTheme: IconThemeData(color: isDark ? textSecondary : textPrimary),
      dividerColor: border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      cardTheme: CardTheme(
        color: surfaceAlt,
        elevation: isDark ? 4 : 8,
        shadowColor: isDark ? Colors.black.withOpacity(0.4) : accent.withOpacity(0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 1), // Apple-like subtle border
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: surfaceAlt,
        elevation: 24,
        shadowColor: Colors.black.withOpacity(0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border, width: 1),
        ),
        titleTextStyle: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: textPrimary, fontSize: 14),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          foregroundColor: textPrimary,
          elevation: isDark ? 0 : 3,
          shadowColor: isDark ? Colors.transparent : Colors.black.withOpacity(0.15),
          hoverColor: accent.withOpacity(0.15),
          highlightColor: accent.withOpacity(0.25),
          padding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isDark ? border.withOpacity(0.5) : border, width: 1.5),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black,
          elevation: isDark ? 6 : 8,
          shadowColor: accent.withOpacity(isDark ? 0.5 : 0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return Colors.white.withOpacity(0.2);
            if (states.contains(WidgetState.pressed)) return Colors.white.withOpacity(0.3);
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          backgroundColor: isDark ? accent.withOpacity(0.05) : Colors.white,
          elevation: isDark ? 0 : 2,
          shadowColor: isDark ? Colors.transparent : accent.withOpacity(0.15),
          side: BorderSide(color: accent, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return accent.withOpacity(0.1);
            if (states.contains(WidgetState.pressed)) return accent.withOpacity(0.2);
            return null;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          elevation: isDark ? 0 : 3,
          shadowColor: isDark ? Colors.transparent : Colors.black.withOpacity(0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isDark ? Colors.transparent : border, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return textPrimary.withOpacity(0.05);
            return null;
          }),
        ),
      ),
      extensions: [soneroColors],
    );
  }
}

extension ThemeContext on BuildContext {
  SoneroColors get colors => Theme.of(this).extension<SoneroColors>()!;
}

