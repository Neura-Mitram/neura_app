import 'package:flutter/material.dart';

final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  useMaterial3: true,
  scaffoldBackgroundColor: Colors.white,
  primaryColor: const Color(0xFF2F67B5),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: Color(0xFF222222),
    elevation: 0,
  ),
  colorScheme: const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF2F67B5),
    onPrimary: Colors.white,
    secondary: Color(0xFFEDF1F7),
    onSecondary: Color(0xFF2F67B5),
    surface: Colors.white,
    onSurface: Color(0xFF222222),
    error: Colors.red,
    onError: Colors.white,
  ),
  textTheme: const TextTheme(
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: Color(0xFF222222),
    ),
    bodyLarge: TextStyle(fontSize: 16, color: Color(0xFF222222)),
    bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF222222)),
    labelSmall: TextStyle(fontSize: 12, color: Colors.grey),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF2F67B5),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.grey[100],
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  ),
);

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xFF0E0E0E),
  primaryColor: const Color(0xFF2F67B5),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0E0E0E),
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  colorScheme: const ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF2F67B5),
    onPrimary: Colors.black,
    secondary: Color(0xFF1F1F1F),
    onSecondary: Color(0xFF2F67B5),
    surface: Color(0xFF0E0E0E),
    onSurface: Colors.white70,
    error: Colors.redAccent,
    onError: Colors.black,
  ),
  textTheme: const TextTheme(
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    ),
    bodyLarge: TextStyle(fontSize: 16, color: Colors.white),
    bodyMedium: TextStyle(fontSize: 14, color: Colors.white70),
    labelSmall: TextStyle(fontSize: 12, color: Colors.grey),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF2F67B5),
      foregroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      textStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF1F1F1F),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  ),
);
