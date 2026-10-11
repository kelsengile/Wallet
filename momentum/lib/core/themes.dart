import 'package:flutter/material.dart';

import 'constants.dart';

/// Every theme the user can pick in Settings.
enum AppThemeOption {
  light('Light', Color(0xFFF2F2F2)),
  dark('Dark', Color(0xFF000000)),
  red('Red', Color(0xFFC62828)),
  yellow('Yellow', Color(0xFFFDD835)),
  orange('Orange', Color(0xFFE65100)),
  blue('Blue', Color(0xFF1565C0)),
  green('Green', Color(0xFF2E7D32)),
  violet('Violet', Color(0xFF673AB7)),
  pink('Pink', Color(0xFFD81B60));

  final String label;

  /// Color shown in the theme picker.
  final Color swatch;

  const AppThemeOption(this.label, this.swatch);
}

class AppTheme {
  AppTheme._();

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

  // Red: red background, white text
  static const _redScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFFFFF),
    onPrimary: Color(0xFFC62828),
    primaryContainer: Color(0xFF7F1818),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFFFCDD2),
    onSecondary: Color(0xFF7F1818),
    secondaryContainer: Color(0xFFD84A4A),
    onSecondaryContainer: Color(0xFFFFFFFF),
    error: Color(0xFFFFE57F),
    onError: Color(0xFF000000),
    surface: Color(0xFFC62828),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFFFD6D6),
    surfaceContainer: Color(0xFFB02323),
    surfaceContainerHighest: Color(0xFF8E1B1B),
    outline: Color(0xFFFF9E9E),
    outlineVariant: Color(0xFFE06060),
  );

  // Yellow: yellow background, dark text
  static const _yellowScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF1A1400),
    onPrimary: Color(0xFFFDD835),
    primaryContainer: Color(0xFFC9A000),
    onPrimaryContainer: Color(0xFF1A1400),
    secondary: Color(0xFF5C4A00),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEBC200),
    onSecondaryContainer: Color(0xFF1A1400),
    error: Color(0xFFB00020),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFFDD835),
    onSurface: Color(0xFF1A1400),
    onSurfaceVariant: Color(0xFF5C4A00),
    surfaceContainer: Color(0xFFF2CA1F),
    surfaceContainerHighest: Color(0xFFE0B400),
    outline: Color(0xFF8A7000),
    outlineVariant: Color(0xFFC9A000),
  );

  // Orange: orange background, white text
  static const _orangeScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFFFFF),
    onPrimary: Color(0xFFE65100),
    primaryContainer: Color(0xFF8F3200),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFFFE0B2),
    onSecondary: Color(0xFF8F3200),
    secondaryContainer: Color(0xFFF4742B),
    onSecondaryContainer: Color(0xFFFFFFFF),
    error: Color(0xFFFFF59D),
    onError: Color(0xFF000000),
    surface: Color(0xFFE65100),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFFFE0CC),
    surfaceContainer: Color(0xFFCC4700),
    surfaceContainerHighest: Color(0xFFA63A00),
    outline: Color(0xFFFFB074),
    outlineVariant: Color(0xFFF07A33),
  );

  // Blue: blue background, white text
  static const _blueScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFFFFF),
    onPrimary: Color(0xFF1565C0),
    primaryContainer: Color(0xFF0A3566),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFBBDEFB),
    onSecondary: Color(0xFF0A3566),
    secondaryContainer: Color(0xFF3D85D6),
    onSecondaryContainer: Color(0xFFFFFFFF),
    error: Color(0xFFFFCC80),
    onError: Color(0xFF000000),
    surface: Color(0xFF1565C0),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFD0E6FF),
    surfaceContainer: Color(0xFF125AAD),
    surfaceContainerHighest: Color(0xFF0D4585),
    outline: Color(0xFF90CAF9),
    outlineVariant: Color(0xFF3F7FCF),
  );

  // Green: green background, white text
  static const _greenScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFFFFF),
    onPrimary: Color(0xFF2E7D32),
    primaryContainer: Color(0xFF174A1A),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFC8E6C9),
    onSecondary: Color(0xFF174A1A),
    secondaryContainer: Color(0xFF55A05A),
    onSecondaryContainer: Color(0xFFFFFFFF),
    error: Color(0xFFFFCC80),
    onError: Color(0xFF000000),
    surface: Color(0xFF2E7D32),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFDDF2DE),
    surfaceContainer: Color(0xFF296F2D),
    surfaceContainerHighest: Color(0xFF1F5A23),
    outline: Color(0xFFA5D6A7),
    outlineVariant: Color(0xFF4F9A54),
  );

  // Violet: violet background, white text
  static const _violetScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFFFFF),
    onPrimary: Color(0xFF673AB7),
    primaryContainer: Color(0xFF35196B),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFD1C4E9),
    onSecondary: Color(0xFF35196B),
    secondaryContainer: Color(0xFF8B66D1),
    onSecondaryContainer: Color(0xFFFFFFFF),
    error: Color(0xFFFFCC80),
    onError: Color(0xFF000000),
    surface: Color(0xFF673AB7),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFE6DDF7),
    surfaceContainer: Color(0xFF5B31A3),
    surfaceContainerHighest: Color(0xFF48268A),
    outline: Color(0xFFB39DDB),
    outlineVariant: Color(0xFF8461CC),
  );

  // Pink: pink background, white text
  static const _pinkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFFFFF),
    onPrimary: Color(0xFFD81B60),
    primaryContainer: Color(0xFF7A0C38),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFF8BBD0),
    onSecondary: Color(0xFF7A0C38),
    secondaryContainer: Color(0xFFE8528A),
    onSecondaryContainer: Color(0xFFFFFFFF),
    error: Color(0xFFFFE57F),
    onError: Color(0xFF000000),
    surface: Color(0xFFD81B60),
    onSurface: Color(0xFFFFFFFF),
    onSurfaceVariant: Color(0xFFFFDCE8),
    surfaceContainer: Color(0xFFC2185B),
    surfaceContainerHighest: Color(0xFF9C1048),
    outline: Color(0xFFF48FB1),
    outlineVariant: Color(0xFFE8528A),
  );

  static ThemeData get light => _build(_lightScheme);
  static ThemeData get dark => _build(_darkScheme);

  /// The theme for a picker choice.
  static ThemeData byOption(AppThemeOption option) {
    switch (option) {
      case AppThemeOption.light:
        return _build(_lightScheme);
      case AppThemeOption.dark:
        return _build(_darkScheme);
      case AppThemeOption.red:
        return _build(_redScheme);
      case AppThemeOption.yellow:
        return _build(_yellowScheme);
      case AppThemeOption.orange:
        return _build(_orangeScheme);
      case AppThemeOption.blue:
        return _build(_blueScheme);
      case AppThemeOption.green:
        return _build(_greenScheme);
      case AppThemeOption.violet:
        return _build(_violetScheme);
      case AppThemeOption.pink:
        return _build(_pinkScheme);
    }
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