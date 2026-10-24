import 'package:flutter/material.dart';

/// One selectable font. [family] == null means the platform default font.
class AppFont {
  final String label;
  final String? family;

  const AppFont(this.label, this.family);
}

class AppFonts {
  AppFonts._();

  static const defaultFont = AppFont('System default', null);

  /// Fonts shown in the Font Style list.
  /// Names like 'serif' / 'monospace' / 'casual' / 'cursive' are built into
  /// Android. To offer more fonts on every platform, add the font files to
  /// pubspec.yaml (under `flutter: fonts:`) and add an entry here using the
  /// same family name.
  static const all = <AppFont>[
    defaultFont,
    AppFont('Roboto', 'Roboto'),
    AppFont('Sans Serif', 'sans-serif'),
    AppFont('Condensed', 'sans-serif-condensed'),
    AppFont('Serif', 'serif'),
    AppFont('Monospace', 'monospace'),
    AppFont('Casual', 'casual'),
    AppFont('Cursive', 'cursive'),
  ];

  /// Finds a font by its saved label. Falls back to the default font.
  static AppFont byLabel(String? label) {
    for (final f in all) {
      if (f.label == label) return f;
    }
    return defaultFont;
  }

  /// Returns [theme] with [family] applied to all of its text styles.
  static ThemeData apply(ThemeData theme, String? family) {
    if (family == null) return theme;
    return theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: family),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: family),
    );
  }
}