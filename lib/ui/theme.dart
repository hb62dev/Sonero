import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Colors ────────────────────────────────────────────────────────────────
  static const bg         = Color(0xFF0A0A10);
  static const surface    = Color(0xFF111118);
  static const surfaceAlt = Color(0xFF1A1A24);
  static const border     = Color(0xFF2A2A38);
  static const accent1    = Color(0xFF7B2FFF);
  static const accent2    = Color(0xFF2F7BFF);
  static const success    = Color(0xFF22C55E);
  static const error      = Color(0xFFEF4444);
  static const textPrimary   = Color(0xFFF0F0F8);
  static const textSecondary = Color(0xFF8888A8);

  static const gradient = LinearGradient(
    colors: [accent1, accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      surface: surface,
      primary: accent1,
      secondary: accent2,
      error: error,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    ),
    iconTheme: const IconThemeData(color: textSecondary),
    dividerColor: border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent1,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
  );
}
