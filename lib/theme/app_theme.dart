import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primary
  static const Color primary = Color(0xFF00BFA5);
  static const Color primaryDark = Color(0xFF009688);
  static const Color primaryLight = Color(0xFFE0F7F4);
  static const Color primaryVeryLight = Color(0xFFF0FBF9);

  // Buttons
  static const Color buttonTeal = Color(0xFF00BFA5);
  static const Color buttonOrange = Color(0xFFFF7043);
  static const Color buttonRed = Color(0xFFE53935);

  // Background
  static const Color background = Color(0xFFF2F4F7);
  static const Color white = Color(0xFFFFFFFF);

  // Text
  static const Color textDark = Color(0xFF1A2B3C);
  static const Color textMedium = Color(0xFF5A6A7A);
  static const Color textLight = Color(0xFF9EA7B0);
  static const Color textWhite = Color(0xFFFFFFFF);

  // Input
  static const Color border = Color(0xFFE0E6ED);
  static const Color inputBg = Color(0xFFFAFBFC);

  // Tab
  static const Color tabActive = Color(0xFF00BFA5);
  static const Color tabInactive = Color(0xFF9EA7B0);
}

class AppTheme {
  static TextStyle _ibmPlexArabic({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.textDark,
    double? height,
  }) {
    return GoogleFonts.ibmPlexSansArabic(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  // Headings
  static TextStyle get heading1 => _ibmPlexArabic(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textWhite,
      );

  static TextStyle get heading2 => _ibmPlexArabic(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textDark,
      );

  static TextStyle get heading3 => _ibmPlexArabic(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textDark,
      );

  // Body
  static TextStyle get bodyLarge => _ibmPlexArabic(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textDark,
      );

  static TextStyle get bodyMedium => _ibmPlexArabic(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textMedium,
      );

  static TextStyle get bodySmall => _ibmPlexArabic(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textLight,
      );

  // Buttons
  static TextStyle get buttonText => _ibmPlexArabic(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textWhite,
      );

  static TextStyle get linkText => _ibmPlexArabic(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.primary,
      );

  // Labels
  static TextStyle get labelText => _ibmPlexArabic(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textMedium,
      );

  static TextStyle get inputText => _ibmPlexArabic(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textDark,
      );

  static TextStyle get hintText => _ibmPlexArabic(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textLight,
      );

  // Input decoration
  static InputDecoration inputDecoration({
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTheme.hintText,
      filled: true,
      fillColor: AppColors.inputBg,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  // Primary button style
  static ButtonStyle primaryButton({Color? backgroundColor}) {
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor ?? AppColors.buttonTeal,
      foregroundColor: AppColors.textWhite,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 0,
      textStyle: buttonText,
    );
  }

  // ThemeData
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.buttonOrange,
        surface: AppColors.white,
      ),
      textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
