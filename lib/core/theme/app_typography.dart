import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Standard typography system for Privora.
/// Uses Playfair Display for the brand logo wordmark.
/// Uses Manrope (with Inter / sans-serif fallback) for UI text.
/// Hierarchy: Screen titles ~26-28px, section titles ~19-20px, body ~15-16px, supporting labels ~12-13px.
class AppTypography {
  AppTypography._();

  /// Serif wordmark font family (Playfair Display)
  static const String fontHeading = 'PlayfairDisplay';

  /// Clean sans-serif UI font family
  static const String fontBody = 'Manrope';

  /// Fallback chain prioritizing locally bundled fonts, then system sans-serif
  static const List<String> fontFallbacks = ['Inter', 'Roboto', 'sans-serif'];

  /// Default application font family
  static const String fontFamily = fontBody;

  // =========================================================================
  // Brand Header System (Playfair Display)
  // =========================================================================

  /// Privora Wordmark (App Title) - 27 px Bold
  static const TextStyle brandTitle = TextStyle(
    fontFamily: fontHeading,
    fontSize: 27,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.primaryText,
    height: 1.2,
  );

  /// Display Large (Hero / Splash) - 28 px Bold
  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontHeading,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.primaryText,
    height: 1.2,
  );

  /// Display Medium (Auth / PIN Headers) - 26 px SemiBold
  static const TextStyle displayMedium = TextStyle(
    fontFamily: fontHeading,
    fontSize: 26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.primaryText,
    height: 1.25,
  );

  // =========================================================================
  // UI Sans-Serif System (Manrope / Inter / System Fallback)
  // =========================================================================

  /// Screen Title (e.g. Page Headers) - 27 px Bold
  static const TextStyle screenTitle = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 27,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.primaryText,
    height: 1.25,
  );

  /// Section Title (Categories section, sheet headers) - 20 px SemiBold
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.primaryText,
    height: 1.3,
  );

  /// Title Large - 20 px SemiBold (alias)
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.primaryText,
    height: 1.3,
  );

  /// Title Medium (Card titles, dialog headings) - 17 px SemiBold
  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: AppColors.primaryText,
    height: 1.35,
  );

  /// Title Small (Subtitles) - 15 px Medium
  static const TextStyle titleSmall = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    color: AppColors.secondaryTextColor,
    height: 1.4,
  );

  /// Category Name - 16 px SemiBold
  static const TextStyle categoryName = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: AppColors.primaryText,
    height: 1.3,
  );

  /// Body Large - 16 px Regular
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    color: AppColors.primaryText,
    height: 1.5,
  );

  /// Body Medium - 15 px Regular
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.15,
    color: AppColors.primaryText,
    height: 1.45,
  );

  /// Body Small (Hints, captions) - 13 px Regular
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    color: AppColors.secondaryTextColor,
    height: 1.4,
  );

  /// Photo Counts & Meta Info - 13 px Medium
  static const TextStyle photoCount = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: AppColors.secondaryTextColor,
    height: 1.35,
  );

  /// Primary Button Text - 15.5 px SemiBold
  static const TextStyle buttonText = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    color: Colors.white,
    height: 1.2,
  );

  /// Label Large (Buttons, chips) - 15 px SemiBold
  static const TextStyle labelLarge = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: AppColors.primaryText,
    height: 1.2,
  );

  /// Label Medium (Inputs, secondary buttons) - 12.5 px Medium
  static const TextStyle labelMedium = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    color: AppColors.secondaryTextColor,
    height: 1.25,
  );

  /// Label Small (Navigation captions, tags) - 11.5 px SemiBold
  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: AppColors.secondaryTextColor,
    height: 1.2,
  );

  /// Navigation Label - 11.5 px SemiBold
  static const TextStyle navLabel = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    height: 1.2,
  );

  /// Page Title alias
  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 27,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.primaryText,
    height: 1.25,
  );

  /// PIN Digit Display - 28 px Bold
  static const TextStyle pinDigit = TextStyle(
    fontFamily: fontBody,
    fontFamilyFallback: fontFallbacks,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.primaryText,
  );
}
