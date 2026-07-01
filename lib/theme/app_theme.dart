import 'package:flutter/material.dart';

// Aman Design System — Foundations
// Palette mirrors tokens in the brand-refresh CSS spec.
// Source: Aman Brand Refresh PDF (color Swatchs.pdf).
class AppColors {
  // ===== Brand scales =====

  // Teal (Pantone 3125 C) — primary
  static const Color teal20 = Color(0xFFCCEDF4);
  static const Color teal40 = Color(0xFF99DBE9);
  static const Color teal60 = Color(0xFF66CADD);
  static const Color teal80 = Color(0xFF33B8D2);
  static const Color teal100 = Color(0xFF00AEC7);
  static const Color teal110 = Color(0xFF02758C);

  // Navy (Pantone 302 C) — supporting
  static const Color navy60 = Color(0xFF33627D);
  static const Color navy80 = Color(0xFF66899D);
  static const Color navy100 = Color(0xFF002A47);
  static const Color navyDeep = Color(0xFF003B5C);

  // Orange (Pantone 7578 C) — positive emphasis
  static const Color orange20 = Color(0xFFF8E1D5);
  static const Color orange40 = Color(0xFFF1C4AC);
  static const Color orange70 = Color(0xFFE6976D);
  static const Color orange100 = Color(0xFFDC6B2F);

  // Brick red (Pantone 7621 C) — warning / urgent
  static const Color brick20 = Color(0xFFEED3D4);
  static const Color brick40 = Color(0xFFDDA7A9);
  static const Color brick70 = Color(0xFFC46569);
  static const Color brick100 = Color(0xFFAB2328);

  // Carbon neutrals
  static const Color carbon20 = Color(0xFFD6D6D6);
  static const Color carbon40 = Color(0xFFADADAD);
  static const Color carbon70 = Color(0xFF707070);
  static const Color carbon100 = Color(0xFF333333);

  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);

  // ===== Semantic aliases (kept stable for existing call sites) =====

  // Primary
  static const Color primary = teal100;
  static const Color primaryDark = teal110;
  static const Color primaryLight = teal20;

  // Buttons
  static const Color buttonTeal = teal100;
  static const Color buttonOrange = orange100;
  static const Color buttonRed = brick100;

  // Backgrounds
  static const Color background = Color(0xFFF2F4F7); // --bg-base

  // Text
  static const Color textDark = navy100; // --fg-1
  static const Color textMedium = carbon70; // --fg-2
  static const Color textLight = carbon40; // --fg-3
  static const Color textWhite = white;

  // Input
  static const Color border = Color(0xFFE0E6ED); // --border-subtle
  static const Color inputBg = Color(0xFFFAFBFC); // --bg-input

  // Tab
  static const Color tabActive = teal100;
  static const Color tabInactive = carbon40;

  // States
  static const Color success = teal100;
  static const Color warning = orange100;
  static const Color danger = brick100;
}

class AppTheme {
  // Aman brand typeface — bundled as a local asset (see pubspec.yaml fonts).
  static const String _fontFamily = 'Alexandria';

  static TextStyle _alexandria({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.textDark,
    double? height,
  }) {
    return TextStyle(
      fontFamily: _fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  // Headings
  static TextStyle get heading1 => _alexandria(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textWhite,
      );

  static TextStyle get heading2 => _alexandria(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textDark,
      );

  static TextStyle get heading3 => _alexandria(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textDark,
      );

  // Body
  static TextStyle get bodyLarge => _alexandria(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textDark,
      );

  static TextStyle get bodyMedium => _alexandria(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textMedium,
      );

  static TextStyle get bodySmall => _alexandria(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textLight,
      );

  // Buttons
  static TextStyle get buttonText => _alexandria(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textWhite,
      );

  static TextStyle get linkText => _alexandria(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.primary,
      );

  // Labels
  static TextStyle get labelText => _alexandria(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textMedium,
      );

  static TextStyle get inputText => _alexandria(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textDark,
      );

  static TextStyle get hintText => _alexandria(
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
      fontFamily: _fontFamily,
      colorScheme: const ColorScheme.light(
        primary: AppColors.teal100,
        onPrimary: AppColors.white,
        secondary: AppColors.orange100,
        onSecondary: AppColors.white,
        error: AppColors.brick100,
        onError: AppColors.white,
        surface: AppColors.white,
        onSurface: AppColors.navy100,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
