import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF1A1A2E);
  static const Color secondary = Color(0xFF16213E);
  static const Color accent = Color(0xFF0F3460);
  static const Color highlight = Color(0xFF00E676); // Green highlight

  static const Color glassWhite = Color(0x33FFFFFF);
  static const Color glassBlack = Color(0x33000000);

  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white70;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassGradient = LinearGradient(
    colors: [Color(0x1AFFFFFF), Color(0x0DFFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
