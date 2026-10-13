import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seedColor = Color(0xFF2F7D32);
  static const _backgroundColor = Color(0xFFF7FAF5);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
      surface: _backgroundColor,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _backgroundColor,
      textTheme:
          const TextTheme(
            displayLarge: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w700,
              height: 1.05,
              letterSpacing: -1.5,
            ),
            headlineSmall: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
            titleLarge: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
            bodyLarge: TextStyle(fontSize: 17, height: 1.55),
            bodyMedium: TextStyle(fontSize: 15, height: 1.5),
            labelLarge: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ).apply(
            bodyColor: const Color(0xFF263326),
            displayColor: const Color(0xFF18321A),
          ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
    );
  }
}
