import 'package:flutter/material.dart';

/// Central color palette for the app. Keeping colors here (instead of
/// scattered hex values across screens) makes rebranding trivial.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFF9C116);
  static const Color primaryDark = Color(0xFFD1A20B);
  static const Color background = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF3F5FB);
  static const Color textPrimary = Color(0xFF16192C);
  static const Color textSecondary = Color(0xFF6B7180);

  static const Color error = Color(0xFFE0483E);
  static const Color success = Color(0xFF2FAE60);
  static const Color successBackground = Color(0xFFE6F7ED);
  static const Color border = Color(0xFFE3E6ED);
  static const Color divider = Color(0xFFEDEFF4);

  static const Color heroBackground = Color(0xFFFCF3DC);
  static const Color infoBackground = Color(0xFFE9F1FC);
  static const Color accent = Color(0xFF3B82F6);

  static const Color errorBackground = Color(0xFFFBE9E7);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color purpleBackground = Color(0xFFF1EBFD);

  /// Around the phone-width frame on wide (desktop web) screens.
  static const Color frameBackdrop = Color(0xFFEEF0F4);
}
