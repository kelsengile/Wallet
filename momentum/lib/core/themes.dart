import 'package:flutter/material.dart';

import 'constants.dart';

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

  static ThemeData get light => _build(_lightScheme);
  static ThemeData get dark => _build(_darkScheme);

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