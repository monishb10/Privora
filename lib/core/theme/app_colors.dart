import 'package:flutter/material.dart';

/// Centralized color palette for Privora based on the design specification:
/// A calm, polished private gallery with soft white surfaces, confident blue accents,
/// elegant spacing, and visually restrained styling.
class AppColors {
  AppColors._();

  // --- Official Privora Theme Tokens ---

  /// App background: #F7F9FD (calm, airy canvas)
  static const Color mainBackground = Color(0xFFF7F9FD);

  /// Card and sheet surface: #FFFFFF (crisp white)
  static const Color cardSurface = Color(0xFFFFFFFF);

  /// Primary blue: #2B63D9 (confident primary blue for buttons & active indicators)
  static const Color primaryActionBlue = Color(0xFF2B63D9);

  /// Pressed primary: #214DB0 (deeper blue for pressed / active interactive states)
  static const Color pressedPrimary = Color(0xFF214DB0);

  /// Soft blue surface: #EBF2FF (gentle tinted background for chips, badges, wash)
  static const Color softBlueSurface = Color(0xFFEBF2FF);

  /// Main text: #172B4D (deep navy-slate for high contrast and readability)
  static const Color primaryText = Color(0xFF172B4D);

  /// Secondary text: #5D6B82 (muted slate for supporting labels and subtitles)
  static const Color secondaryTextColor = Color(0xFF5D6B82);

  /// Decorative border: #DCE5F2 (subtle structure line without harsh outlines)
  static const Color borderDivider = Color(0xFFDCE5F2);

  /// Success: #18735D (restrained forest-emerald green)
  static const Color successColor = Color(0xFF18735D);

  /// Error/destructive: #B93845 (crimson red for destructive alerts & actions)
  static const Color errorDestructive = Color(0xFFB93845);

  // --- Brand Heritage Accents (from official Privora logo) ---
  static const Color brandSkyBlue = Color(0xFF59C8F3);
  static const Color darkBlueEmphasis = Color(0xFF172B4D);

  // --- Semantic Aliases for Compatibility Across Components ---
  static const Color background = mainBackground;
  static const Color surface = cardSurface;
  static const Color elevatedSurface = softBlueSurface;
  static const Color primaryAccent = primaryActionBlue;
  static const Color secondaryAccent = brandSkyBlue;
  static const Color mainText = primaryText;
  static const Color secondaryText = secondaryTextColor;
  static const Color disabled = Color(0xFFA6B4C9);
  static const Color disabledElements = Color(0xFFA6B4C9);
  static const Color danger = errorDestructive;
  static const Color border = borderDivider;
  static const Color success = successColor;
  static const Color surfaceCard = cardSurface;
  static const Color primaryTextColor = primaryText;
  static const Color subtlePlaceholder = secondaryTextColor;
  static const Color warning = Color(0xFFD97706);

  // Subtle restrained shadows and overlays
  static const Color overlay = Color(0x660F172A);
  static const Color cardShadow = Color(0x0A172B4D);

  // Category palette (used as local accents while respecting the theme)
  static const List<Color> categoryPalette = [
    Color(0xFF2B63D9), // Primary Blue
    Color(0xFF0284C7), // Sky Blue
    Color(0xFF0D9488), // Teal
    Color(0xFF18735D), // Forest Green
    Color(0xFF6366F1), // Indigo
    Color(0xFF7C3AED), // Violet
    Color(0xFFC026D3), // Fuchsia
    Color(0xFFDB2777), // Rose
    Color(0xFFEA580C), // Coral Orange
    Color(0xFF475569), // Slate
  ];
}
