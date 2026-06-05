import 'package:flutter/material.dart';

class MinimalTheme {
  // Brand colors for Minimal White Theme
  static const Color background = Color(0xFFF8F9FA); // Off-white background
  static const Color surface = Color(0xFFFFFFFF); // Pure white surface
  static const Color surfaceLight = Color(0xFFF1F3F5); // Slightly gray for inputs
  
  static const Color primary = Color(0xFF228BE6); // Clean blue accent
  static const Color primaryLight = Color(0xFFE7F5FF); // Light blue for selections
  static const Color secondary = Color(0xFF20C997); // Teal accent for success/active
  static const Color accent = Color(0xFF748FFC); // Indigo accent
  
  static const Color textPrimary = Color(0xFF212529); // Dark gray/almost black
  static const Color textSecondary = Color(0xFF495057); // Medium gray
  static const Color textMuted = Color(0xFF868E96); // Light gray

  // Glassmorphic / Semi-transparent Decoration for wallpaper support
  static Decoration glassDecoration({
    Color color = const Color(0xE6FFFFFF), // 90% opaque white
    double borderRadius = 16,
    double borderWidth = 1,
    Color borderColor = const Color(0x1A000000), // 10% black
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor,
        width: borderWidth,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x08000000), // Very subtle shadow
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

  // Light Theme configuration
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: surface,
      ),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.2,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.normal,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 14,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x1A000000), width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        hintStyle: const TextStyle(color: textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x1A000000), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: IconThemeData(color: primary),
        unselectedIconTheme: IconThemeData(color: textSecondary),
        selectedLabelTextStyle: TextStyle(color: primary, fontWeight: FontWeight.bold),
        unselectedLabelTextStyle: TextStyle(color: textSecondary),
        elevation: 1,
      ),
    );
  }
}
