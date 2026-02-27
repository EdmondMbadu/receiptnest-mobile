import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static final light = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.symmetric(vertical: 8),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    ),
  );

  static final dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF34D399),
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    cardTheme: const CardThemeData(
      margin: EdgeInsets.symmetric(vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: Colors.grey.shade900,
    ),
  );
}
