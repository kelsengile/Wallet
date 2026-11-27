import 'package:material_ui/material_ui.dart';

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

/// The Accent color as a plain color. It is not used by buttons (those
/// follow Glyph). It is applied only where the app asks for it:
/// bottom nav bar, drawer header, version box and settings sections.
///
/// [foreground] is the Glyph color, so text and icons drawn on the accent
/// change whenever the Glyph color changes.
@immutable
class AppAccent extends ThemeExtension<AppAccent> {
  /// The accent color itself (used as a background).
  final Color background;

  /// Glyph color to draw on top of [background].
  final Color foreground;

  const AppAccent({required this.background, required this.foreground});

  @override
  AppAccent copyWith({Color? background, Color? foreground}) => AppAccent(
        background: background ?? this.background,
        foreground: foreground ?? this.foreground,
      );

  @override
  AppAccent lerp(ThemeExtension<AppAccent>? other, double t) {
    if (other is! AppAccent) return this;
    return AppAccent(
      background: Color.lerp(background, other.background, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  // Only used for the error colors on custom themes.
  static const _cream = Color(0xFFF3E7CE);
  static const _ink = Color(0xFF2B2108);

  // Accent colors for the built-in themes.
  static const _darkAccent = Color(0xFF1E1E1E);
  static const _lightAccent = Color(0xFFCBCBCB);

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

  static ThemeData get light => _build(_lightScheme, _lightAccent);
  static ThemeData get dark => _build(_darkScheme, _darkAccent);

  /// The theme for a built-in choice.
  static ThemeData byOption(AppThemeOption option) {
    switch (option) {
      case AppThemeOption.light:
        return light;
      case AppThemeOption.dark:
        return dark;
    }
  }

  /// The accent (background + glyph foreground) of the active theme.
  static AppAccent accentOf(BuildContext context) =>
      Theme.of(context).extension<AppAccent>()!;

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

  /// Readable glyph (text + icon + button) color for a given background:
  /// a soft tint of the background's own hue instead of one fixed color.
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

  /// Default accent when the user hasn't picked one: a slightly lighter
  /// (dark themes) or darker (light themes) shade of the main color, so it
  /// works as a bar / panel background.
  static Color accentFor(Color background) {
    final dark = _isDarkBackground(background);
    final hsl = HSLColor.fromColor(background);
    final l = (hsl.lightness + (dark ? 0.12 : -0.10)).clamp(0.0, 1.0);
    final s = hsl.saturation < 0.08
        ? hsl.saturation
        : (hsl.saturation * 1.1).clamp(0.0, 1.0);
    return hsl.withLightness(l).withSaturation(s).toColor();
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
  /// [seed] is the background / main color.
  /// [accent] is a plain color used only for the nav bar, drawer header,
  /// version box and settings sections.
  /// [text] (glyph) is the color of fonts, icons AND buttons. It is also
  /// the text/icon color drawn on the accent color.
  /// When [accent] or [text] is null it is derived from [seed].
  static ThemeData fromColor(Color seed, {Color? accent, Color? text}) {
    final fg = text ?? onColor(seed);
    final acc = accent ?? accentFor(seed);
    final darkBackground = _isDarkBackground(seed);
    final secondary = Color.lerp(seed, fg, 0.7)!;

    final scheme = ColorScheme(
      brightness: darkBackground ? Brightness.dark : Brightness.light,
      // Buttons, sliders and switches follow the glyph color.
      primary: fg,
      onPrimary: _readableOn(fg, seed, acc),
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
    return _build(scheme, acc);
  }

  static ThemeData _build(ColorScheme scheme, Color accent) {
    // Text/icons drawn on top of the accent color: always the Glyph color
    // (onSurface), so changing Glyph changes the nav bar, drawer header,
    // version box and settings sections.
    final onAccent = scheme.onSurface;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [AppAccent(background: accent, foreground: onAccent)],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      // Main nav bar: accent background. Label colors are set where the bar
      // is built (main.dart) so the chosen font is kept.
      navigationBarTheme: NavigationBarThemeData(
        height: 56,
        backgroundColor: accent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: onAccent.withValues(alpha: 0.18),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(size: 22, color: onAccent),
        ),
        labelPadding: const EdgeInsets.only(top: 2),
      ),
      // Side panel: main, dulled.
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