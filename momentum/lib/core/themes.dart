import 'package:flutter/material.dart';

import 'constants.dart';

/// Every theme the user can pick in Settings.
enum AppThemeOption {
  light('Light', Color(0xFFF2F2F2)),
  dark('Dark', Color(0xFF000000)),
  red('Red', Color(0xFFEF5350)),
  yellow('Yellow', Color(0xFFFFD54F)),
  orange('Orange', Color(0xFFFFA726)),
  blue('Blue', Color(0xFF42A5F5)),
  green('Green', Color(0xFF66BB6A)),
  violet('Violet', Color(0xFFAB7CF0)),
  pink('Pink', Color(0xFFF06292));

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

  // Red: near-black with red accents
  static const _redScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFEF5350),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF5A1A1A),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFE57373),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF3A1616),
    onSecondaryContainer: Color(0xFFFFD9D9),
    error: Color(0xFFCF6679),
    onError: Color(0xFF000000),
    surface: Color(0xFF0D0505),
    onSurface: Color(0xFFEDEDED),
    onSurfaceVariant: Color(0xFFB39A9A),
    surfaceContainer: Color(0xFF1A0D0D),
    surfaceContainerHighest: Color(0xFF2A1515),
    outline: Color(0xFF7A5C5C),
    outlineVariant: Color(0xFF3A2323),
  );

  // Yellow: near-black with yellow accents
  static const _yellowScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFD54F),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF554500),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFFFE082),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF3A3000),
    onSecondaryContainer: Color(0xFFFFF3C4),
    error: Color(0xFFCF6679),
    onError: Color(0xFF000000),
    surface: Color(0xFF0D0B02),
    onSurface: Color(0xFFEDEDED),
    onSurfaceVariant: Color(0xFFB3AA8F),
    surfaceContainer: Color(0xFF1A1705),
    surfaceContainerHighest: Color(0xFF2A2508),
    outline: Color(0xFF7A7152),
    outlineVariant: Color(0xFF3A3418),
  );

  // Orange: near-black with orange accents
  static const _orangeScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFFA726),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF5A3300),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFFFB74D),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF3A2200),
    onSecondaryContainer: Color(0xFFFFE0B8),
    error: Color(0xFFCF6679),
    onError: Color(0xFF000000),
    surface: Color(0xFF0D0802),
    onSurface: Color(0xFFEDEDED),
    onSurfaceVariant: Color(0xFFB39F8A),
    surfaceContainer: Color(0xFF1A1205),
    surfaceContainerHighest: Color(0xFF2A1D09),
    outline: Color(0xFF7A6249),
    outlineVariant: Color(0xFF3A2B18),
  );

  // Blue: near-black with blue accents
  static const _blueScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF42A5F5),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF0F3A5F),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFF64B5F6),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF0B2640),
    onSecondaryContainer: Color(0xFFCFE8FF),
    error: Color(0xFFCF6679),
    onError: Color(0xFF000000),
    surface: Color(0xFF02070D),
    onSurface: Color(0xFFEDEDED),
    onSurfaceVariant: Color(0xFF8FA3B3),
    surfaceContainer: Color(0xFF0A121A),
    surfaceContainerHighest: Color(0xFF12202E),
    outline: Color(0xFF51697A),
    outlineVariant: Color(0xFF1E3042),
  );

  // Green: near-black with green accents
  static const _greenScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF66BB6A),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF1B4D1E),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFF81C784),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF123316),
    onSecondaryContainer: Color(0xFFD4F0D6),
    error: Color(0xFFCF6679),
    onError: Color(0xFF000000),
    surface: Color(0xFF020D04),
    onSurface: Color(0xFFEDEDED),
    onSurfaceVariant: Color(0xFF8FB394),
    surfaceContainer: Color(0xFF0A1A0C),
    surfaceContainerHighest: Color(0xFF132A16),
    outline: Color(0xFF52795A),
    outlineVariant: Color(0xFF1C3A21),
  );

  // Violet: near-black with violet accents
  static const _violetScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFAB7CF0),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF3A2468),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFBE9BF5),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF2A1A4A),
    onSecondaryContainer: Color(0xFFE8DAFF),
    error: Color(0xFFCF6679),
    onError: Color(0xFF000000),
    surface: Color(0xFF07040D),
    onSurface: Color(0xFFEDEDED),
    onSurfaceVariant: Color(0xFFA094B3),
    surfaceContainer: Color(0xFF110A1A),
    surfaceContainerHighest: Color(0xFF1D132E),
    outline: Color(0xFF66527A),
    outlineVariant: Color(0xFF2E2142),
  );

  // Pink: near-black with pink accents
  static const _pinkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF06292),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF5C1A36),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFF48FB1),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF3D1124),
    onSecondaryContainer: Color(0xFFFFD6E4),
    error: Color(0xFFCF6679),
    onError: Color(0xFF000000),
    surface: Color(0xFF0D0408),
    onSurface: Color(0xFFEDEDED),
    onSurfaceVariant: Color(0xFFB3909F),
    surfaceContainer: Color(0xFF1A0A11),
    surfaceContainerHighest: Color(0xFF2E1420),
    outline: Color(0xFF7A5265),
    outlineVariant: Color(0xFF42202F),
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