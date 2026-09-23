import 'package:flutter/material.dart';

/// Système de design centralisé pour Rova.
/// Toutes les couleurs et styles de texte de l'app doivent passer par ici,
/// pour garder une identité visuelle cohérente sur tous les écrans.
class HadColors {
  static const ink = Color(0xFF06263A);
  static const inkSoft = Color(0xFF547080);
  static const cream = Color(0xFFF3F8F8);
  static const surface = Color(0xFFFFFFFF);
  static const border = Color(0xFFD6E1E2);
  static const clay = Color(0xFF087F88);
  static const claySoft = Color(0xFFD6F0F1);
  static const sage = Color(0xFF087F88);
  static const sageSoft = Color(0xFFD6F0F1);
  static const amber = Color(0xFFFFF4DF);
}

class HadText {
  static const eyebrow = TextStyle(
    color: HadColors.clay,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: .4,
  );

  static const heroTitle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w900,
    color: HadColors.ink,
    height: 1.15,
  );

  static const sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: HadColors.ink,
  );

  static const body = TextStyle(
    fontSize: 15,
    color: HadColors.ink,
    height: 1.4,
  );

  static const bodySoft = TextStyle(fontSize: 14, color: HadColors.inkSoft);

  static const metricValue = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: HadColors.ink,
  );

  static const metricLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: HadColors.inkSoft,
  );
}

ThemeData hadTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: HadColors.cream,
    colorScheme: ColorScheme.fromSeed(
      seedColor: HadColors.clay,
      primary: HadColors.clay,
      secondary: HadColors.sage,
      surface: HadColors.surface,
      onSurface: HadColors.ink,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: HadColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: HadColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HadColors.clay,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HadColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: HadColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: HadColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: HadColors.clay, width: 1.4),
      ),
    ),
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
