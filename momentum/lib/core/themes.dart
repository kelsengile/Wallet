import 'package:flutter/material.dart';

import 'constants.dart';

/// Every theme the user can pick in Settings.
enum AppThemeOption {
  light('Light', Color(0xFFF2F2F2)),
  dark('Dark', Color(0xFF000000)),
  red('Red', Color(0xFFA5413A)),
  yellow('Yellow', Color(0xFFD8B24A)),
  orange('Orange', Color(0xFFA8531A)),
  brown('Brown', Color(0xFF5C4033)),
  blue('Blue', Color(0xFF3F6683)),
  green('Green', Color(0xFF56704A)),
  violet('Violet', Color(0xFF6E5078)),
  pink('Pink', Color(0xFF9E4F63));

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

  // Red (vintage): faded brick red, cream text
  static const _redScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF3E7CE),
    onPrimary: Color(0xFFA5413A),
    primaryContainer: Color(0xFF6E2823),
    onPrimaryContainer: Color(0xFFF3E7CE),
    secondary: Color(0xFFE8C4B0),
    onSecondary: Color(0xFF6E2823),
    secondaryContainer: Color(0xFFBF6A5E),
    onSecondaryContainer: Color(0xFFF3E7CE),
    error: Color(0xFFE8C872),
    onError: Color(0xFF2B2108),
    surface: Color(0xFFA5413A),
    onSurface: Color(0xFFF3E7CE),
    onSurfaceVariant: Color(0xFFE3C8B8),
    surfaceContainer: Color(0xFF93372F),
    surfaceContainerHighest: Color(0xFF7A2C26),
    outline: Color(0xFFD9A08F),
    outlineVariant: Color(0xFFBF6A5E),
  );

  // Yellow (vintage): mustard, dark brown text
  static const _yellowScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF2B2108),
    onPrimary: Color(0xFFD8B24A),
    primaryContainer: Color(0xFFA98625),
    onPrimaryContainer: Color(0xFF2B2108),
    secondary: Color(0xFF5A4614),
    onSecondary: Color(0xFFF3E7CE),
    secondaryContainer: Color(0xFFC9A23A),
    onSecondaryContainer: Color(0xFF2B2108),
    error: Color(0xFF8E2A1F),
    onError: Color(0xFFF3E7CE),
    surface: Color(0xFFD8B24A),
    onSurface: Color(0xFF2B2108),
    onSurfaceVariant: Color(0xFF5A4614),
    surfaceContainer: Color(0xFFCBA640),
    surfaceContainerHighest: Color(0xFFB8932F),
    outline: Color(0xFF7A6220),
    outlineVariant: Color(0xFFA98625),
  );

  // Orange (vintage): rust orange, cream text
  static const _orangeScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF3E7CE),
    onPrimary: Color(0xFFA8531A),
    primaryContainer: Color(0xFF6F3410),
    onPrimaryContainer: Color(0xFFF3E7CE),
    secondary: Color(0xFFEBC9A0),
    onSecondary: Color(0xFF6F3410),
    secondaryContainer: Color(0xFFC97A3E),
    onSecondaryContainer: Color(0xFFF3E7CE),
    error: Color(0xFFE8D27A),
    onError: Color(0xFF2B2108),
    surface: Color(0xFFA8531A),
    onSurface: Color(0xFFF3E7CE),
    onSurfaceVariant: Color(0xFFEDD3B5),
    surfaceContainer: Color(0xFF964A16),
    surfaceContainerHighest: Color(0xFF7C3D12),
    outline: Color(0xFFE0A877),
    outlineVariant: Color(0xFFC97A3E),
  );

    // Brown (vintage): coffee brown, cream text
  static const _brownScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF3E7CE),
    onPrimary: Color(0xFF5C4033),
    primaryContainer: Color(0xFF3B281F),
    onPrimaryContainer: Color(0xFFF3E7CE),
    secondary: Color(0xFFD8BFA8),
    onSecondary: Color(0xFF3B281F),
    secondaryContainer: Color(0xFF85644F),
    onSecondaryContainer: Color(0xFFF3E7CE),
    error: Color(0xFFE8C872),
    onError: Color(0xFF2B2108),
    surface: Color(0xFF5C4033),
    onSurface: Color(0xFFF3E7CE),
    onSurfaceVariant: Color(0xFFDCC9B6),
    surfaceContainer: Color(0xFF523829),
    surfaceContainerHighest: Color(0xFF402C20),
    outline: Color(0xFFB08F76),
    outlineVariant: Color(0xFF85644F),
  );

  // Blue (vintage): dusty denim blue, cream text
  static const _blueScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF3E7CE),
    onPrimary: Color(0xFF3F6683),
    primaryContainer: Color(0xFF27425A),
    onPrimaryContainer: Color(0xFFF3E7CE),
    secondary: Color(0xFFBCD0DC),
    onSecondary: Color(0xFF27425A),
    secondaryContainer: Color(0xFF6288A5),
    onSecondaryContainer: Color(0xFFF3E7CE),
    error: Color(0xFFE8C872),
    onError: Color(0xFF2B2108),
    surface: Color(0xFF3F6683),
    onSurface: Color(0xFFF3E7CE),
    onSurfaceVariant: Color(0xFFD2DEE3),
    surfaceContainer: Color(0xFF365B76),
    surfaceContainerHighest: Color(0xFF2B4A60),
    outline: Color(0xFF9DB8CA),
    outlineVariant: Color(0xFF5F829C),
  );

  // Green (vintage): sage / olive green, cream text
  static const _greenScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF3E7CE),
    onPrimary: Color(0xFF56704A),
    primaryContainer: Color(0xFF36482E),
    onPrimaryContainer: Color(0xFFF3E7CE),
    secondary: Color(0xFFCBD8B8),
    onSecondary: Color(0xFF36482E),
    secondaryContainer: Color(0xFF7C9670),
    onSecondaryContainer: Color(0xFFF3E7CE),
    error: Color(0xFFE8C872),
    onError: Color(0xFF2B2108),
    surface: Color(0xFF56704A),
    onSurface: Color(0xFFF3E7CE),
    onSurfaceVariant: Color(0xFFDAE3C9),
    surfaceContainer: Color(0xFF4D6642),
    surfaceContainerHighest: Color(0xFF3D5234),
    outline: Color(0xFFA9C09A),
    outlineVariant: Color(0xFF7C9670),
  );

  // Violet (vintage): dusty plum, cream text
  static const _violetScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF3E7CE),
    onPrimary: Color(0xFF6E5078),
    primaryContainer: Color(0xFF47304F),
    onPrimaryContainer: Color(0xFFF3E7CE),
    secondary: Color(0xFFD8C4DC),
    onSecondary: Color(0xFF47304F),
    secondaryContainer: Color(0xFF947299),
    onSecondaryContainer: Color(0xFFF3E7CE),
    error: Color(0xFFE8C872),
    onError: Color(0xFF2B2108),
    surface: Color(0xFF6E5078),
    onSurface: Color(0xFFF3E7CE),
    onSurfaceVariant: Color(0xFFE3D3E3),
    surfaceContainer: Color(0xFF62466B),
    surfaceContainerHighest: Color(0xFF4F3858),
    outline: Color(0xFFBC9FC3),
    outlineVariant: Color(0xFF947299),
  );

  // Pink (vintage): dusty rose, cream text
  static const _pinkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF3E7CE),
    onPrimary: Color(0xFF9E4F63),
    primaryContainer: Color(0xFF66303F),
    onPrimaryContainer: Color(0xFFF3E7CE),
    secondary: Color(0xFFEBC3CC),
    onSecondary: Color(0xFF66303F),
    secondaryContainer: Color(0xFFBA7487),
    onSecondaryContainer: Color(0xFFF3E7CE),
    error: Color(0xFFE8C872),
    onError: Color(0xFF2B2108),
    surface: Color(0xFF9E4F63),
    onSurface: Color(0xFFF3E7CE),
    onSurfaceVariant: Color(0xFFEDD0D6),
    surfaceContainer: Color(0xFF8E4558),
    surfaceContainerHighest: Color(0xFF763848),
    outline: Color(0xFFD9A0AE),
    outlineVariant: Color(0xFFBA7487),
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
      case AppThemeOption.brown:
        return _build(_brownScheme);
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