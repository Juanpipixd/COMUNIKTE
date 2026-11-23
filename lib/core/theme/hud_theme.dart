import 'package:flutter/material.dart';

/// Tema HUD de Alto Contraste para Motociclistas (COMUNIKTE).
/// Diseñado para máxima visibilidad en condiciones de alta luminosidad solar o noche,
/// con botones sobredimensionados operables fácilmente con guantes gruesos.
class HudTheme {
  HudTheme._();

  // Colores Base HUD
  static const Color background = Color(0xFF0D0F12);
  static const Color surface = Color(0xFF171B21);
  static const Color surfaceElevated = Color(0xFF222831);
  static const Color border = Color(0xFF2D3748);

  // Colores de Acento y Estado (Neón de Alto Contraste)
  static const Color accentNeon = Color(0xFF00E676);      // Verde Activo / Conectado
  static const Color warningNeon = Color(0xFFFFD600);     // Amarillo Conectando / Alerta
  static const Color dangerNeon = Color(0xFFFF1744);      // Rojo Desconectado / Mic Mute
  static const Color cyanNeon = Color(0xFF00E5FF);        // Cyan Bluetooth SCO / Audio
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);

  // Dimensiones y Ergonomía para Guantes
  static const double minTouchTarget = 64.0;
  static const double giantTouchTarget = 96.0;
  static const double borderRadius = 20.0;

  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accentNeon,
      colorScheme: const ColorScheme.dark(
        primary: accentNeon,
        secondary: cyanNeon,
        surface: surface,
        error: dangerNeon,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: textPrimary,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: textPrimary,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        labelLarge: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(minTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          backgroundColor: surfaceElevated,
          foregroundColor: textPrimary,
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      iconTheme: const IconThemeData(
        color: textPrimary,
        size: 32,
      ),
    );
  }
}
