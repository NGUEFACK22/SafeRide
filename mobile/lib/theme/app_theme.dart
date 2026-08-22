import 'package:flutter/material.dart';

/// Thème SafeRide AI d'après les maquettes (bleu / blanc / noir / rouge SOS)
class AppTheme {
  // Couleurs maquette
  static const primaryBlue = Color(0xFF0F62FE); // bouton principal, bottom nav active
  static const primaryBlueDark = Color(0xFF0B4DCC);
  static const lightBlueBadge = Color(0xFFEAF0FF); // "compte vérifié", SUPPORT bg
  static const lightBlueBorder = Color(0xFFD6E0FF);
  static const background = Color(0xFFF8F9FF); // fond général très clair bleuté
  static const cardBlack = Color(0xFF111111); // carte scanner
  static const sosRed = Color(0xFFC1272D); // SOS URGENCE
  static const sosRedDark = Color(0xFF9B1B20);
  static const textDark = Color(0xFF0B1C48);
  static const textGrey = Color(0xFF6B7280);
  static const successBg = Color(0xFFE6F4EA);
  static const successBorder = Color(0xFFB7DFC5);
  static const successText = Color(0xFF0A7A2E);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryBlue,
      primary: primaryBlue,
      surface: Colors.white,
      background: background,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(color: textDark, fontSize: 16, fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: textDark),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primaryBlue, width: 1.4)),
        hintStyle: const TextStyle(color: textGrey, fontSize: 14),
        labelStyle: const TextStyle(color: textGrey, fontSize: 13),
        prefixIconColor: Colors.grey.shade500,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textDark,
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryBlue,
        unselectedItemColor: Color(0xFF9AA0AE),
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
    );
  }
}
