import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../themes.dart';

/// App-wide user settings. The root MaterialApp listens to this, so any
/// change applies to every screen, dialog and route immediately.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kTheme = 'settings.theme';
  static const _kTextSize = 'settings.textSizeIndex';

  SharedPreferences? _prefs;

  /// Call once before runApp so saved settings apply from the first frame.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final themeName = prefs.getString(_kTheme);
    if (themeName != null) {
      for (final option in AppThemeOption.values) {
        if (option.name == themeName) {
          _themeOption = option;
          break;
        }
      }
    }

    final sizeIndex = prefs.getInt(_kTextSize);
    if (sizeIndex != null &&
        sizeIndex >= 0 &&
        sizeIndex < textSizeLabels.length) {
      _textSizeIndex = sizeIndex;
    }
  }

  // ---- Theme ----
  /// null = follow the system (light/dark) until the user picks one.
  AppThemeOption? _themeOption;
  AppThemeOption? get themeOption => _themeOption;

  void setThemeOption(AppThemeOption option) {
    if (option == _themeOption) return;
    _themeOption = option;
    _prefs?.setString(_kTheme, option.name);
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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.only(bottom: AppConstants.spaceLg),
            children: [
              const _SectionHeader('Appearance'),
              _SettingGroup(
                children: [
                  _buildThemeTile(context, settings),
                  _buildTextSizeTile(context, settings),
                ],
              ),
              const SizedBox(height: AppConstants.spaceSm),
              const _SectionHeader('Localization'),
              const SizedBox(height: AppConstants.spaceSm),
              const _SectionHeader('Security'),
              const SizedBox(height: AppConstants.spaceSm),
              const _SectionHeader('Storage'),
            ],
          );
        },
      ),
    );
  }

  // ---------- Theme ----------

  /// The theme currently on screen (resolves "system" to light/dark).
  AppThemeOption _effectiveOption(BuildContext context, AppSettings settings) {
    final chosen = settings.themeOption;
    if (chosen != null) return chosen;
    return Theme.of(context).brightness == Brightness.dark
        ? AppThemeOption.dark
        : AppThemeOption.light;
  }

  Widget _buildThemeTile(BuildContext context, AppSettings settings) {
    final current = _effectiveOption(context, settings);
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
        final selected = _effectiveOption(dialogContext, settings);
        return SimpleDialog(
          title: const Text('Theme'),
          children: [
            for (final option in AppThemeOption.values)
              ListTile(
                leading: _ThemeSwatch(option.swatch),
                title: Text(option.label),
                trailing:
                    option == selected ? const Icon(Icons.check) : null,
                onTap: () {
                  settings.setThemeOption(option);
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

/// Small colored circle shown next to each theme in the picker.
class _ThemeSwatch extends StatelessWidget {
  final Color color;
  const _ThemeSwatch(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
    );
  }
}

/// One big rounded rectangle holding every setting under a header,
/// with thin dividers between them. Darker than the page background's
/// usual card color so it stands out clearly.
class _SettingGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingGroup({required this.children});

  // Darker fill and matching divider colors for each theme.
  static const _darkFill = Color(0xFF121212);
  static const _darkDivider = Color(0xFF2E2E2E);
  static const _lightFill = Color(0xFFCBCBCB);
  static const _lightDivider = Color(0xFFAFAFAF);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? _darkFill : _lightFill;
    final divider = isDark ? _darkDivider : _lightDivider;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: AppConstants.spaceXs,
      ),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        clipBehavior: Clip.antiAlias, // keeps tap ripples inside the curves
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: AppConstants.spaceMd,
                  endIndent: AppConstants.spaceMd,
                  color: divider,
                ),
              children[i],
            ],
          ],
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
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceMd + AppConstants.spaceXs,
        AppConstants.spaceMd,
        AppConstants.spaceMd,
        AppConstants.spaceSm + AppConstants.spaceXs, // more space underneath
      ),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          // White on dark; black on light so it stays readable.
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
    );
  }
}