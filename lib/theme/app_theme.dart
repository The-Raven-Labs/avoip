import 'package:flutter/material.dart';

class AppTheme {
  // Brand palette from the Authentic AV login design.
  static const Color brandPrimary = Color(0xFF6D28D9);
  static const Color brandPrimaryDark = Color(0xFF581C87);
  static const Color brandPrimaryLight = Color(0xFFF3E8FF);
  static const Color brandPrimarySoft = Color(0xFFEDE9FE);
  static const Color brandBackground = Color(0xFFFFFFFF);
  static const Color brandCard = Color(0xFFFFFFFF);
  static const Color brandBackgroundSecondary = Color(0xFFF9FAFB);
  static const Color brandTextPrimary = Color(0xFF111827);
  static const Color brandTextSecondary = Color(0xFF475569);
  static const Color brandTextMuted = Color(0xFF64748B);
  static const Color brandBorder = Color(0xFFE5E7EB);
  static const Color brandBorderInput = Color(0xFFD1D5DB);
  static const Color brandSuccess = Color(0xFF16A34A);
  static const Color brandSuccessBackground = Color(0xFFDCFCE7);
  static const Color brandWarning = Color(0xFFF59E0B);
  static const Color brandWarningBackground = Color(0xFFFEF3C7);
  static const Color brandError = Color(0xFFDC2626);
  static const Color brandErrorBackground = Color(0xFFFEE2E2);
  static const Color brandInfo = Color(0xFF2563EB);

  // Shared app colors. Existing screens use these aliases so the modules
  // inherit the new light brand palette consistently.
  static const Color accentWhite = brandPrimary;
  static const Color accentDark = brandTextPrimary;
  static const Color backgroundLight = brandBackground;
  static const Color highlightGrey = brandBackgroundSecondary;
  static const Color borderLight = brandBorder;
  static const Color textMain = brandTextPrimary;
  static const Color textMuted = brandTextMuted;

  static const Color statusOnline = brandSuccess;
  static const Color statusWarning = brandWarning;
  static const Color statusError = brandError;
  static const Color statusOffline = brandTextMuted;

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      fontFamily: '.SF Pro Text',
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.light,
        seedColor: brandPrimary,
        primary: brandPrimary,
        secondary: brandPrimarySoft,
        background: backgroundLight,
      ),
      scaffoldBackgroundColor: backgroundLight,
      highlightColor: brandPrimarySoft,
      splashColor: brandPrimaryLight,
      hoverColor: brandPrimarySoft,
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundLight,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textMain,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: '.SF Pro Text', // Primary
        ),
        iconTheme: IconThemeData(color: textMain),
      ),
      cardTheme: CardThemeData(
        color: highlightGrey,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderLight),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: textMain,
          fontWeight: FontWeight.w700,
          fontSize: 28,
          fontFamily: '.SF Pro Display',
          letterSpacing: -0.5,
        ), // Professional dashboard header
        headlineMedium: TextStyle(
          color: textMain,
          fontWeight: FontWeight.w600,
          fontSize: 20,
          fontFamily: '.SF Pro Text',
          letterSpacing: -0.2,
        ),
        titleLarge: TextStyle(
          color: textMain,
          fontWeight: FontWeight.w600,
          fontSize: 16,
          fontFamily: '.SF Pro Text',
        ),
        bodyLarge: TextStyle(
          color: textMain,
          fontSize: 14,
          fontFamily: '.SF Pro Text',
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          color: textMuted,
          fontSize: 12,
          fontFamily: '.SF Pro Text',
          height: 1.4,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ), // Dense layout
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: '.SF Pro Text',
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
