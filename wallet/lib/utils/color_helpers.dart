import 'package:flutter/material.dart';

/// Parses a hex color string (with or without `#`, 6 or 8 hex digits).
Color colorFromHex(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
  if (h.length == 8) return Color(int.parse(h, radix: 16));
  return const Color(0xFF6366F1);
}

/// Builds a two-stop gradient from [base] tuned for the current brightness.
List<Color> gradientForColor(Color base, {required bool isDark}) {
  if (isDark) {
    return [
      Color.alphaBlend(base.withValues(alpha: 0.55), const Color(0xFF1E1E2E)),
      Color.alphaBlend(base.withValues(alpha: 0.35), const Color(0xFF2A2A3E)),
    ];
  }
  final hsl = HSLColor.fromColor(base);
  final lighter = hsl
      .withLightness((hsl.lightness + 0.12).clamp(0, 1.0))
      .withSaturation((hsl.saturation - 0.06).clamp(0, 1.0))
      .toColor();
  final darker = hsl
      .withLightness((hsl.lightness - 0.10).clamp(0, 1.0))
      .withSaturation((hsl.saturation + 0.06).clamp(0, 1.0))
      .toColor();
  return [lighter, darker];
}
