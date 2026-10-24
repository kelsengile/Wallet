import 'package:flutter/material.dart';

import 'constants.dart';

/// Built-in themes. Everything else comes from the color picker.
enum AppThemeOption {
  light('Light', Color(0xFFF2F2F2)),
  dark('Dark', Color(0xFF000000));

  final String label;

  /// Color shown in the picker.
  final Color swatch;

  const AppThemeOption(this.label, this.swatch);
}

class AppTheme {
  AppTheme._();

  // Only used for the error colors on custom themes.
  static const _cream = Color(0xFFF3E7CE);
  static const _ink = Color(0xFF2B2108);

  // Dark: black and gray
  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFE0E0E0),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF3A3A3A),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFF9E9E9E),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF2A2A2A),
    onSecondaryContainer: Color(0xFFE0E0E0),
    error: Color(0xFFCF6679),
    onError: Color(0xFF000000),
    surface: Color(0xFF000000),
    onSurface: Color(0xFFEDEDED),
    onSurfaceVariant: Color(0xFF9E9E9E),
    surfaceContainer: Color(0xFF121212),
    surfaceContainerHighest: Color(0xFF1E1E1E),
    outline: Color(0xFF616161),
    outlineVariant: Color(0xFF2E2E2E),
  );

  // Light: white/gray with black accents
  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF000000),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD6D6D6),
    onPrimaryContainer: Color(0xFF000000),
    secondary: Color(0xFF616161),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE6E6E6),
    onSecondaryContainer: Color(0xFF1A1A1A),
    error: Color(0xFFB00020),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFF2F2F2),
    onSurface: Color(0xFF000000),
    onSurfaceVariant: Color(0xFF616161),
    surfaceContainer: Color(0xFFE8E8E8),
    surfaceContainerHighest: Color(0xFFDDDDDD),
    outline: Color(0xFF9E9E9E),
    outlineVariant: Color(0xFFCFCFCF),
  );

  static ThemeData get light => _build(_lightScheme);
  static ThemeData get dark => _build(_darkScheme);

  /// The theme for a built-in choice.
  static ThemeData byOption(AppThemeOption option) {
    switch (option) {
      case AppThemeOption.light:
        return _build(_lightScheme);
      case AppThemeOption.dark:
        return _build(_darkScheme);
    }
  }

  // ---------- Custom color ----------

  static double _contrast(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final hi = l1 > l2 ? l1 : l2;
    final lo = l1 > l2 ? l2 : l1;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// True when light content reads better than dark content on [bg].
  static bool _isDarkBackground(Color bg) =>
      _contrast(bg, Colors.white) >= _contrast(bg, Colors.black);

  /// A color with the same hue as [seed], starting at [lightness] and
  /// pushed lighter/darker until it has [minContrast] against [bg].
  /// Grays stay gray (no tint) so neutral picks don't turn red.
  static Color _tone(
    Color seed, {
    required double saturation,
    required double lightness,
    required Color bg,
    required double minContrast,
    required bool lighten,
  }) {
    final hue = HSLColor.fromColor(seed).hue;
    final sat = HSLColor.fromColor(seed).saturation < 0.08 ? 0.0 : saturation;
    var l = lightness;
    var color = HSLColor.fromAHSL(1, hue, sat, l).toColor();
    for (var i = 0; i < 60 && _contrast(color, bg) < minContrast; i++) {
      l = (l + (lighten ? 0.02 : -0.02)).clamp(0.0, 1.0);
      color = HSLColor.fromAHSL(1, hue, sat, l).toColor();
    }
    return color;
  }

  /// Readable text color for a given background: a soft tint of the
  /// background's own hue instead of one fixed color.
  static Color onColor(Color background) {
    final dark = _isDarkBackground(background);
    final s = HSLColor.fromColor(background).saturation;
    return _tone(
      background,
      saturation: (s * 0.6).clamp(0.15, 0.4),
      lightness: dark ? 0.92 : 0.10,
      bg: background,
      minContrast: 7,
      lighten: dark,
    );
  }

  /// Accent color (buttons, sliders, highlights): the same hue as the
  /// background but stronger, kept readable against it.
  static Color accentFor(Color background) {
    final dark = _isDarkBackground(background);
    final s = HSLColor.fromColor(background).saturation;
    return _tone(
      background,
      saturation: (s * 1.1).clamp(0.45, 0.9),
      lightness: dark ? 0.75 : 0.22,
      bg: background,
      minContrast: 4.5,
      lighten: dark,
    );
  }

  static Color _shift(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// Picks whichever of [a] or [b] reads better on top of [on].
  static Color _readableOn(Color on, Color a, Color b) =>
      _contrast(on, a) >= _contrast(on, b) ? a : b;

  /// Builds a complete theme from the colors the user picks.
  ///
  /// [seed] is the background / main color. [accent] (complementary color:
  /// buttons, sliders, highlights) and [text] (fonts and icons) are optional;
  /// when null they are derived from [seed].
  static ThemeData fromColor(Color seed, {Color? accent, Color? text}) {
    final fg = text ?? onColor(seed);
    final acc = accent ?? accentFor(seed);
    final darkBackground = _isDarkBackground(seed);
    final secondary = Color.lerp(seed, acc, 0.8)!;

    final scheme = ColorScheme(
      brightness: darkBackground ? Brightness.dark : Brightness.light,
      primary: acc,
      onPrimary: _readableOn(acc, seed, fg),
      primaryContainer: _shift(seed, darkBackground ? 0.14 : -0.14),
      onPrimaryContainer: fg,
      secondary: secondary,
      onSecondary: _readableOn(secondary, seed, fg),
      secondaryContainer: _shift(seed, darkBackground ? 0.10 : -0.04),
      onSecondaryContainer: fg,
      error: darkBackground ? const Color(0xFFE8C872) : const Color(0xFF8E2A1F),
      onError: darkBackground ? _ink : _cream,
      surface: seed,
      onSurface: fg,
      onSurfaceVariant: Color.lerp(seed, fg, 0.85)!,
      surfaceContainer: _shift(seed, darkBackground ? -0.04 : -0.03),
      surfaceContainerHighest: _shift(seed, darkBackground ? -0.09 : -0.07),
      outline: Color.lerp(seed, fg, 0.5)!,
      outlineVariant: _shift(seed, darkBackground ? 0.10 : -0.10),
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 56,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(size: 22, color: scheme.onSurface),
        ),
        labelPadding: const EdgeInsets.only(top: 2),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: scheme.surfaceContainer),
      listTileTheme: ListTileThemeData(
        selectedColor: scheme.onSurface,
        selectedTileColor: scheme.primaryContainer,
        iconColor: scheme.onSurfaceVariant,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
      ),
    );
  }
}