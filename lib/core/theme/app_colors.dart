import 'package:flutter/material.dart';

/// Centralized color palette for Privora based on the clean, modern
/// blue-and-white visual identity mandated by the Privora logo.
class AppColors {
  AppColors._();

  // --- Official Privora Color System ---
  /// Brand sky blue (#59C8F3) - extracted from the official Privora logo.
  static const Color brandSkyBlue = Color(0xFF59C8F3);

  /// Primary action blue (#0A84C6) - high contrast blue for primary buttons & interactive elements.
  static const Color primaryActionBlue = Color(0xFF0A84C6);

  /// Dark blue for emphasis (#075A85) - deep slate blue for key visual anchors.
  static const Color darkBlue = Color(0xFF075A85);
  static const Color darkBlueEmphasis = Color(0xFF075A85);

  /// Main app background (#F7FCFF) - light airy clean background.
  static const Color mainBackground = Color(0xFFF7FCFF);

  /// Card and dialog surface (#FFFFFF) - crisp pure white surfaces.
  static const Color cardSurface = Color(0xFFFFFFFF);

  /// Soft blue surface (#EAF8FE) - delicate light blue for chips, secondary surfaces & badges.
  static const Color softBlueSurface = Color(0xFFEAF8FE);

  /// Border and divider line (#C9EAF7) - soft blue borders instead of heavy outlines.
  static const Color borderDivider = Color(0xFFC9EAF7);

  /// Primary readable text (#101820) - near-black for maximum readability on light backgrounds.
  static const Color primaryText = Color(0xFF101820);

  /// Secondary text (#52636D) - muted slate for captions, subtitles, and hints.
  static const Color secondaryTextColor = Color(0xFF52636D);

  /// Disabled UI elements (#A9BAC3).
  static const Color disabledElements = Color(0xFFA9BAC3);

  /// Error & destructive actions (#D92D20).
  static const Color errorDestructive = Color(0xFFD92D20);

  /// Success state (#15803D).
  static const Color successColor = Color(0xFF15803D);

  // --- Semantic Aliases for Global Consistency ---
  static const Color background = mainBackground;
  static const Color surface = cardSurface;
  static const Color elevatedSurface = softBlueSurface;
  static const Color primaryAccent = primaryActionBlue;
  static const Color secondaryAccent = brandSkyBlue;
  static const Color mainText = primaryText;
  static const Color secondaryText = secondaryTextColor;
  static const Color disabled = disabledElements;
  static const Color danger = errorDestructive;
  static const Color border = borderDivider;
  static const Color success = successColor;
  static const Color surfaceCard = cardSurface;
  static const Color primaryTextColor = primaryText;
  static const Color subtlePlaceholder = disabledElements;
  static const Color warning = Color(0xFFE08A00);

  // Subtle shadows & overlays (soft blue/dark tint, zero heavy glow)
  static const Color overlay = Color(0x66101820);
  static const Color cardShadow = Color(0x0D075A85);

  // Curated category color palette (clean, modern, vibrant; no dark gold/yellow dominance)
  static const List<Color> categoryPalette = [
    Color(0xFF0A84C6), // Primary Action Blue
    Color(0xFF59C8F3), // Brand Sky Blue
    Color(0xFF075A85), // Deep Navy Blue
    Color(0xFF0284C7), // Azure Blue
    Color(0xFF0D9488), // Clean Teal
    Color(0xFF15803D), // Emerald Green
    Color(0xFF6366F1), // Royal Indigo
    Color(0xFF8B5CF6), // Soft Violet
    Color(0xFFEC4899), // Warm Rose
    Color(0xFFF97316), // Coral Amber
  ];
}
