import 'package:flutter/material.dart';

/// Shared theme definitions for the light and dark schemes.
///
/// The accent color (007ACC, VS Code blue) is kept consistent across both
/// themes so the brand identity stays the same; only the surface / text
/// colors invert.
class AppTheme {
  AppTheme._();

  static const Color accent = Color(0xFF007ACC);

  // ---- Light theme -------------------------------------------------------

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFFFFFFF),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: 'monospace',
    );
  }

  // ---- Dark theme --------------------------------------------------------

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      fontFamily: 'monospace',
    );
  }
}
