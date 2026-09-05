import 'package:flutter/material.dart';

/// Centralized color palette for Privora as mandated by the design system.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0F1014);
  static const Color surface = Color(0xFF181A20);
  static const Color elevatedSurface = Color(0xFF22242C);
  static const Color primaryAccent = Color(0xFFE6B566);
  static const Color secondaryAccent = Color(0xFF6ED6BF);
  static const Color mainText = Color(0xFFF7F5F0);
  static const Color secondaryText = Color(0xFFA7A9B2);
  static const Color danger = Color(0xFFFF6B6B);

  // Additional utility shades derived harmoniously
  static const Color border = Color(0xFF2E323D);
  static const Color overlay = Color(0xCC0F1014);
  static const Color cardShadow = Color(0x40000000);
  static const Color success = Color(0xFF6ED6BF);
  static const Color warning = Color(0xFFE6B566);

  // Curated category color palette for user selection
  static const List<Color> categoryPalette = [
    Color(0xFFE6B566), // Golden Sand
    Color(0xFF6ED6BF), // Mint Emerald
    Color(0xFF7AA2F7), // Soft Azure
    Color(0xFFBB9AF7), // Lavender Dream
    Color(0xFFF7768E), // Coral Rose
    Color(0xFFFF9E64), // Warm Amber
    Color(0xFF73DACA), // Deep Aqua
    Color(0xFF2AC3DE), // Ocean Cyan
    Color(0xFF9ECE6A), // Olive Sage
    Color(0xFFDB4B4B), // Crimson Red
  ];
}
