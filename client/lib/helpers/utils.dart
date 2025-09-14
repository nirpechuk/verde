import 'package:flutter/material.dart';

// Color Constants
const Color highlight = Color(0xFFF0EAD2);

// Enhanced color palette with better contrast while maintaining environmental theme
// Credible/Positive colors (Green family)
const Color lightModeMedium = Color.fromARGB(255, 76, 175, 80);  // More vibrant green
const Color lightModeDark = Color.fromARGB(255, 46, 125, 50);   // Rich dark green

// Not Credible/Negative colors (Earth/Orange-Red family for contrast)
const Color lightModeNegative = Color.fromARGB(255, 239, 108, 0);    // Vibrant orange
const Color lightModeNegativeDark = Color.fromARGB(255, 191, 54, 12); // Deep orange-red

// Dark mode colors (Brown family)
const Color darkModeMedium = Color(0xFFA98467);
const Color darkModeDark = Color(0xFF6C584C);

// Dark mode negative colors
const Color darkModeNegative = Color(0xFFD84315);      // Orange-red for dark mode
const Color darkModeNegativeDark = Color(0xFFBF360C);  // Deeper orange-red

const double kFabButtonSpacing = 13.0;
const kIconSize = 50.0;

// Unified Design System Constants
const double kFloatingButtonSize = 56.0;
const double kMainFabSize = 84.0; // 1.5x the size of other buttons
const double kFloatingButtonBorderRadius = 28.0;
const double kMainFabBorderRadius = 42.0; // Maintains circular shape
const double kFloatingButtonElevation = 8.0;
const double kFloatingButtonIconSize = 24.0;
const double kFloatingButtonPadding = 16.0;
const double kFloatingButtonSpacing = 12.0;

// Shadow configuration
const List<BoxShadow> kFloatingButtonShadow = [
  BoxShadow(
    color: Color(0x33000000), // 20% black
    blurRadius: 8,
    offset: Offset(0, 4),
    spreadRadius: 0,
  ),
];
