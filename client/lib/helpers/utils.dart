import 'package:flutter/material.dart';

// Color Constants
const Color highlight = Color(0xFFF0EAD2);
const Color lightModeMedium = Color.fromARGB(255, 52, 125, 0);
const Color lightModeDark = Color(0xFF143601);
const Color darkModeMedium = Color(0xFFA98467);
const Color darkModeDark = Color(0xFF6C584C);

const double kFabButtonSpacing = 13.0;
const kIconSize = 50.0;

// Unified Design System Constants
const double kFloatingButtonSize = 67.0;
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
