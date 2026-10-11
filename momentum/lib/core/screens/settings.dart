import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

/// App-wide user settings. The root MaterialApp listens to this, so any
/// change applies to every screen, dialog and route immediately.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kThemeMode = 'settings.themeMode';
  static const _kTextSize = 'settings.textSizeIndex';

  SharedPreferences? _prefs;

  /// Call once before runApp so saved settings apply from the first frame.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final modeIndex = prefs.getInt(_kThemeMode);
    if (modeIndex != null &&
        modeIndex >= 0 &&
        modeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[modeIndex];
    }

    final sizeIndex = prefs.getInt(_kTextSize);
    if (sizeIndex != null &&
        sizeIndex >= 0 &&
        sizeIndex < textSizeLabels.length) {
      _textSizeIndex = sizeIndex;
    }
  }

  // ---- Theme ----
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    _prefs?.setInt(_kThemeMode, mode.index);
    notifyListeners();
  }

  // ---- Text size ----
  static const textSizeLabels = [
    'Smallest',
    'Small',
    'Default (system)',
    'Big',
    'Biggest',
  ];
  static const _textScales = [0.8, 0.9, 1.0, 1.15, 1.3];
  static const defaultTextSizeIndex = 2;

  int _textSizeIndex = defaultTextSizeIndex;
  int get textSizeIndex => _textSizeIndex;
  String get textSizeLabel => textSizeLabels[_textSizeIndex];

  /// Multiplier applied on top of the system text scale.
  double get textScale => _textScales[_textSizeIndex];

  void setTextSizeIndex(int index) {
    if (index == _textSizeIndex) return;
    _textSizeIndex = index;
    _prefs?.setInt(_kTextSize, index);
    notifyListeners();
  }
}

class _ThemeOption {
  final String label;
  final IconData icon;
  final ThemeMode mode;
  const _ThemeOption(this.label, this.icon, this.mode);
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Every color theme available in the app (light and dark for now).
  static const _themeOptions = <_ThemeOption>[
    _ThemeOption('Light', Icons.light_mode_outlined, ThemeMode.light),
    _ThemeOption('Dark', Icons.dark_mode_outlined, ThemeMode.dark),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            children: [
              const _SectionHeader('Appearance'),
              _buildThemeTile(context, settings),
              _buildTextSizeTile(context, settings),
              const _SectionDivider(),
              const _SectionHeader('Localization'),
              const _SectionDivider(),
              const _SectionHeader('Security'),
              const _SectionDivider(),
              const _SectionHeader('Storage'),
            ],
          );
        },
      ),
    );
  }

  // ---------- Theme ----------

  /// The theme currently on screen (resolves "system" to light/dark).
  ThemeMode _effectiveMode(BuildContext context, AppSettings settings) {
    if (settings.themeMode != ThemeMode.system) return settings.themeMode;
    return Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  Widget _buildThemeTile(BuildContext context, AppSettings settings) {
    final current = _themeOptions.firstWhere(
      (o) => o.mode == _effectiveMode(context, settings),
    );
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('Theme'),
      subtitle: Text(current.label),
      onTap: () => _showThemeDialog(context, settings),
    );
  }

  Future<void> _showThemeDialog(
    BuildContext context,
    AppSettings settings,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final selected = _effectiveMode(dialogContext, settings);
        return SimpleDialog(
          title: const Text('Theme'),
          children: [
            for (final option in _themeOptions)
              ListTile(
                leading: Icon(option.icon),
                title: Text(option.label),
                trailing:
                    option.mode == selected ? const Icon(Icons.check) : null,
                onTap: () {
                  settings.setThemeMode(option.mode);
                  Navigator.of(dialogContext).pop();
                },
              ),
          ],
        );
      },
    );
  }

  // ---------- Text size ----------

  Widget _buildTextSizeTile(BuildContext context, AppSettings settings) {
    final maxIndex = AppSettings.textSizeLabels.length - 1;
    return ListTile(
      leading: const Icon(Icons.text_fields),
      title: const Text('Text Size'),
      subtitle: Text(settings.textSizeLabel),
      // Gauge bar sits at the side of the tile.
      trailing: SizedBox(
        width: 170,
        child: Slider(
          value: settings.textSizeIndex.toDouble(),
          min: 0,
          max: maxIndex.toDouble(),
          divisions: maxIndex,
          label: settings.textSizeLabel,
          onChanged: (v) => settings.setTextSizeIndex(v.round()),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd,
        AppConstants.spaceMd,
        AppConstants.spaceMd,
        AppConstants.spaceXs,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => const Divider(
        height: AppConstants.spaceMd,
        indent: AppConstants.spaceMd,
        endIndent: AppConstants.spaceMd,
      );
}