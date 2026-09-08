import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Standard typography system for Privora.
/// Uses Playfair Display for app title, page titles, auth titles, and section headings.
/// Uses Inter for category names, photo counts, body text, buttons, inputs, and nav labels.
class AppTypography {
  AppTypography._();

  /// Serif heading font family (Playfair Display)
  static const String fontHeading = 'PlayfairDisplay';

  /// Clean sans-serif font family (Inter)
  static const String fontBody = 'Inter';

  /// Default application font family
  static const String fontFamily = fontBody;

  // =========================================================================
  // Playfair Display System (Classical, Elegant, High-Authority)
  // =========================================================================

  /// Privora Brand Title (AppBar / Brand Header) - Playfair Display Bold, 25 px
  static const TextStyle brandTitle = TextStyle(
    fontFamily: fontHeading,
    fontSize: 25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.primaryText,
    height: 1.2,
  );

  /// Page Title (Auth, Pin, Page headers) - Playfair Display Bold, 28 px
  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontHeading,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.primaryText,
    height: 1.25,
  );

  /// Major Section Heading - Playfair Display SemiBold, 22 px
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontHeading,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.primaryText,
    height: 1.3,
  );

  /// Display Large (Hero Splash / Welcome) - Playfair Display Bold, 30 px
  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontHeading,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.mainText,
    height: 1.2,
  );

  /// Display Medium (Auth Headers / PIN Screens) - Playfair Display Bold, 26 px
  static const TextStyle displayMedium = TextStyle(
    fontFamily: fontHeading,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.mainText,
    height: 1.25,
  );

  // =========================================================================
  // Inter Sans-Serif System (Crisp, Legible, Functional)
  // =========================================================================

  /// Category Name - Inter SemiBold, 17 px
  static const TextStyle categoryName = TextStyle(
    fontFamily: fontBody,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: AppColors.mainText,
    height: 1.3,
  );

  /// Photo Counts & Meta Info - Inter Medium, 13 px
  static const TextStyle photoCount = TextStyle(
    fontFamily: fontBody,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: AppColors.secondaryText,
    height: 1.35,
  );

  /// Primary Button Text - Inter SemiBold, 15 px
  static const TextStyle buttonText = TextStyle(
    fontFamily: fontBody,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: Colors.white,
    height: 1.2,
  );

  /// Navigation Label - Inter SemiBold, 11.5 px
  static const TextStyle navLabel = TextStyle(
    fontFamily: fontBody,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    height: 1.2,
  );

  /// Title Large - Inter SemiBold, 20 px
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontBody,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.mainText,
    height: 1.3,
  );

  /// Title Medium - Inter SemiBold, 17 px
  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontBody,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.mainText,
    height: 1.35,
  );

  /// Title Small - Inter Medium, 15 px
  static const TextStyle titleSmall = TextStyle(
    fontFamily: fontBody,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: AppColors.secondaryText,
    height: 1.4,
  );

  /// Body Large - Inter Regular, 16 px
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontBody,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.15,
    color: AppColors.mainText,
    height: 1.5,
  );

  /// Body Medium - Inter Regular, 14 px
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontBody,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
    color: AppColors.mainText,
    height: 1.45,
  );

  /// Body Small - Inter Regular, 12 px
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontBody,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    color: AppColors.secondaryText,
    height: 1.4,
  );

  /// Label Large - Inter SemiBold, 14 px
  static const TextStyle labelLarge = TextStyle(
    fontFamily: fontBody,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: AppColors.mainText,
    height: 1.2,
  );

  /// Label Medium - Inter Medium, 12 px
  static const TextStyle labelMedium = TextStyle(
    fontFamily: fontBody,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: AppColors.secondaryText,
    height: 1.2,
  );

  /// Label Small - Inter SemiBold, 10 px
  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontBody,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: AppColors.secondaryText,
    height: 1.2,
  );

  /// PIN Digit Display - Inter Bold, 28 px
  static const TextStyle pinDigit = TextStyle(
    fontFamily: fontBody,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.mainText,
  );
}
