import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../font.dart';
import '../themes.dart';

/// App-wide user settings. The root MaterialApp listens to this, so any
/// change applies to every screen, dialog and route immediately.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kTheme = 'settings.theme';
  static const _kColor = 'settings.customColor';
  static const _kAccent = 'settings.accentColor';
  static const _kText = 'settings.textColor';
  static const _kTextSize = 'settings.textSizeIndex';
  static const _kFontStyle = 'settings.fontStyle';
  static const _kBoldText = 'settings.boldText';

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

    final colorValue = prefs.getInt(_kColor);
    if (colorValue != null) _customColor = Color(colorValue);

    final accentValue = prefs.getInt(_kAccent);
    if (accentValue != null) _accentColor = Color(accentValue);

    final textValue = prefs.getInt(_kText);
    if (textValue != null) _textColor = Color(textValue);

    _fontStyle = AppFonts.byLabel(prefs.getString(_kFontStyle));
    _boldText = prefs.getBool(_kBoldText) ?? false;
  }

  // ---- Theme ----
  /// null = follow the system (light/dark) until the user picks one.
  AppThemeOption? _themeOption;
  AppThemeOption? get themeOption => _themeOption;

  /// Background / main color picked with the color picker.
  /// Takes priority over [themeOption].
  Color? _customColor;
  Color? get customColor => _customColor;

  /// Complementary (accent) color. null = derived from [customColor].
  Color? _accentColor;
  Color? get accentColor => _accentColor;

  /// Font and icon color. null = derived from [customColor].
  Color? _textColor;
  Color? get textColor => _textColor;

  void setThemeOption(AppThemeOption option) {
    if (option == _themeOption && _customColor == null) return;
    _themeOption = option;
    _customColor = null;
    _accentColor = null;
    _textColor = null;
    _prefs?.setString(_kTheme, option.name);
    _prefs?.remove(_kColor);
    _prefs?.remove(_kAccent);
    _prefs?.remove(_kText);
    notifyListeners();
  }

  /// Saves a custom theme. Pass null for [accent] or [text] to have
  /// that color derived automatically from [background].
  void setCustomTheme({
    required Color background,
    Color? accent,
    Color? text,
  }) {
    _customColor = background;
    _accentColor = accent;
    _textColor = text;
    _themeOption = null;
    _prefs?.setInt(_kColor, background.toARGB32());
    if (accent != null) {
      _prefs?.setInt(_kAccent, accent.toARGB32());
    } else {
      _prefs?.remove(_kAccent);
    }
    if (text != null) {
      _prefs?.setInt(_kText, text.toARGB32());
    } else {
      _prefs?.remove(_kText);
    }
    _prefs?.remove(_kTheme);
    notifyListeners();
  }

  // ---- Font style ----
  AppFont _fontStyle = AppFonts.defaultFont;
  AppFont get fontStyle => _fontStyle;

  /// Font family passed to the theme. null = platform default.
  String? get fontFamily => _fontStyle.family;

  void setFontStyle(AppFont font) {
    if (font.label == _fontStyle.label) return;
    _fontStyle = font;
    _prefs?.setString(_kFontStyle, font.label);
    notifyListeners();
  }

  // ---- Bold text ----
  bool _boldText = false;
  bool get boldText => _boldText;

  void setBoldText(bool value) {
    if (value == _boldText) return;
    _boldText = value;
    _prefs?.setBool(_kBoldText, value);
    notifyListeners();
  }

  // ---- Font size ----
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
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_outlined),
            SizedBox(width: 8),
            Text('Settings'),
          ],
        ),
      ),
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
                  _buildFontTile(context, settings),
                ],
              ),
              const SizedBox(height: AppConstants.spaceSm),
              const _SectionHeader('Localization'),
              const _SettingGroup(
                children: [
                  _PlaceholderToggle(
                    icon: Icons.attach_money,
                    title: 'Currency',
                  ),
                  _PlaceholderToggle(
                    icon: Icons.location_on_outlined,
                    title: 'Location',
                  ),
                  _PlaceholderToggle(
                    icon: Icons.language,
                    title: 'Language',
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceSm),
              const _SectionHeader('Security'),
              const _SettingGroup(
                children: [
                  _PlaceholderToggle(
                    icon: Icons.pin_outlined,
                    title: 'PIN',
                  ),
                  _PlaceholderToggle(
                    icon: Icons.fingerprint,
                    title: 'Touch ID',
                  ),
                  _PlaceholderToggle(
                    icon: Icons.face_outlined,
                    title: 'Face ID',
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------- Theme ----------

  String _currentLabel(BuildContext context, AppSettings settings) {
    if (settings.customColor != null) return 'Custom';
    final chosen = settings.themeOption;
    if (chosen != null) return chosen.label;
    return Theme.of(context).brightness == Brightness.dark ? 'Dark' : 'Light';
  }

  Widget _buildThemeTile(BuildContext context, AppSettings settings) {
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('Theme'),
      subtitle: Text(_currentLabel(context, settings)),
      trailing: _ThemeSwatch(Theme.of(context).colorScheme.surface),
      onTap: () => _showColorPicker(context, settings),
    );
  }

  Future<void> _showColorPicker(BuildContext context, AppSettings settings) {
    final initial =
        settings.customColor ?? Theme.of(context).colorScheme.surface;
    return showDialog<void>(
      context: context,
      builder: (_) => _ColorPickerDialog(initial: initial, settings: settings),
    );
  }

  // ---------- Font ----------

  /// Subtitle: "Font style | Font size", plus "| Bold" when bold is on.
  String _fontSummary(AppSettings settings) {
    final parts = <String>[
      settings.fontStyle.label,
      settings.textSizeLabel,
      if (settings.boldText) 'Bold',
    ];
    return parts.join(' | ');
  }

  Widget _buildFontTile(BuildContext context, AppSettings settings) {
    return ListTile(
      leading: const Icon(Icons.text_fields),
      title: const Text('Font'),
      subtitle: Text(_fontSummary(settings)),
      onTap: () => _showFontConfig(context, settings),
    );
  }

  Future<void> _showFontConfig(BuildContext context, AppSettings settings) {
    return showDialog<void>(
      context: context,
      builder: (_) => _FontConfigDialog(settings: settings),
    );
  }
}

/// Small colored circle shown next to the current theme.
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
/// with thin dividers between them. Light/Dark use a fixed neutral
/// fill; custom colors use their own darker shade.
class _SettingGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingGroup({required this.children});

  // Neutral fills for the Light and Dark themes.
  static const _darkFill = Color(0xFF121212);
  static const _darkDivider = Color(0xFF2E2E2E);
  static const _lightFill = Color(0xFFCBCBCB);
  static const _lightDivider = Color(0xFFAFAFAF);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final option = AppSettings.instance.themeOption;
    final neutral = AppSettings.instance.customColor == null &&
        (option == null ||
            option == AppThemeOption.light ||
            option == AppThemeOption.dark);

    final Color fill;
    final Color divider;
    if (neutral) {
      fill = isDark ? _darkFill : _lightFill;
      divider = isDark ? _darkDivider : _lightDivider;
    } else {
      // Custom colors: darker shade of the theme's own color.
      fill = scheme.surfaceContainerHighest;
      divider = scheme.outlineVariant;
    }

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

/// Placeholder setting: a switch that flips visually but does nothing yet.
/// Replace with a real setting (stored in AppSettings) when it's wired up.
class _PlaceholderToggle extends StatefulWidget {
  final IconData icon;
  final String title;
  const _PlaceholderToggle({required this.icon, required this.title});

  @override
  State<_PlaceholderToggle> createState() => _PlaceholderToggleState();
}

class _PlaceholderToggleState extends State<_PlaceholderToggle> {
  bool _value = false;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(widget.icon),
      title: Text(widget.title),
      value: _value,
      onChanged: (v) => setState(() => _value = v),
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
        AppConstants.spaceMd + AppConstants.spaceXs,
        AppConstants.spaceMd,
        AppConstants.spaceMd,
        AppConstants.spaceSm + AppConstants.spaceXs, // more space underneath
      ),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          // Follows the theme's text color, so it adapts to custom colors.
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Pop-up for everything font related:
///  - Font style (opens a second pop-up with the list of fonts)
///  - Font size (short slider at the right side of the text)
///  - Bold text (switch)
/// Size and bold apply live, so there is only a Close button.
/// Font style is applied from its own pop-up with an Apply button.
class _FontConfigDialog extends StatelessWidget {
  final AppSettings settings;
  const _FontConfigDialog({required this.settings});

  @override
  Widget build(BuildContext context) {
    final maxIndex = AppSettings.textSizeLabels.length - 1;
    final theme = Theme.of(context);

    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: 24,
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Font Configuration:'),
          SizedBox(height: AppConstants.spaceSm),
          Divider(height: 1),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Font style ----
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.font_download_outlined),
                    title: const Text('Font style'),
                    subtitle: Text(settings.fontStyle.label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => _FontStyleDialog(settings: settings),
                    ),
                  ),
                  const Divider(height: 1),
                  // ---- Font size: text on the left, short slider on the right ----
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.format_size),
                        const SizedBox(width: AppConstants.spaceMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Font size',
                                style: theme.textTheme.bodyLarge,
                              ),
                              Text(
                                settings.textSizeLabel,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Fixed short width, pinned to the right side.
                        SizedBox(
                          width: 150,
                          child: Slider(
                            value: settings.textSizeIndex.toDouble(),
                            min: 0,
                            max: maxIndex.toDouble(),
                            divisions: maxIndex,
                            label: settings.textSizeLabel,
                            onChanged: (v) =>
                                settings.setTextSizeIndex(v.round()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // ---- Bold text ----
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.format_bold),
                    title: const Text('Bold text'),
                    value: settings.boldText,
                    onChanged: settings.setBoldText,
                  ),
                  // Space between the Bold switch and the Close button.
                  const SizedBox(height: AppConstants.spaceMd),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Second pop-up: list of fonts. Each name is shown in its own font.
/// Tapping a font only highlights it; nothing changes in the app until
/// Apply is pressed.
class _FontStyleDialog extends StatefulWidget {
  final AppSettings settings;
  const _FontStyleDialog({required this.settings});

  @override
  State<_FontStyleDialog> createState() => _FontStyleDialogState();
}

class _FontStyleDialogState extends State<_FontStyleDialog> {
  late AppFont _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.settings.fontStyle;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Font Style:'),
          SizedBox(height: AppConstants.spaceSm),
          Divider(height: 1),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: AppConstants.spaceSm),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: AppFonts.all.length,
          itemBuilder: (context, i) {
            final font = AppFonts.all[i];
            final selected = font.label == _selected.label;
            return ListTile(
              title: Text(
                font.label,
                style: TextStyle(fontFamily: font.family),
              ),
              trailing: selected ? const Icon(Icons.check) : null,
              selected: selected,
              onTap: () => setState(() => _selected = font),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.settings.setFontStyle(_selected);
            Navigator.of(context).pop();
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// Pop-up with three parts: Main (background), Accent (complementary)
/// and Text (fonts and icons). The popup itself is the live sample: it is
/// drawn with the colors being picked.
class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  final AppSettings settings;
  const _ColorPickerDialog({required this.initial, required this.settings});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _bg;
  late HSVColor _accent;
  late HSVColor _text;

  /// While true, that color follows the Main color automatically.
  bool _accentAuto = true;
  bool _textAuto = true;

  int _tab = 0; // 0 = Main, 1 = Accent, 2 = Text
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _bg = HSVColor.fromColor(widget.initial);
    _accentAuto = s.accentColor == null;
    _textAuto = s.textColor == null;
    _accent = HSVColor.fromColor(
      s.accentColor ?? AppTheme.accentFor(widget.initial),
    );
    _text = HSVColor.fromColor(
      s.textColor ?? AppTheme.onColor(widget.initial),
    );
    _hexController = TextEditingController(text: _hex(_bg.toColor()));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  /// Reads "#A5413A" or "A5413A". Returns null until it is a full 6-digit code.
  Color? _parseHex(String input) {
    var text = input.trim();
    if (text.startsWith('#')) text = text.substring(1);
    if (text.length != 6) return null;
    final value = int.tryParse(text, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  HSVColor get _current => _tab == 0 ? _bg : (_tab == 1 ? _accent : _text);

  /// Re-derives Accent / Text from Main for the ones still on auto.
  void _syncAuto() {
    final bg = _bg.toColor();
    if (_accentAuto) _accent = HSVColor.fromColor(AppTheme.accentFor(bg));
    if (_textAuto) _text = HSVColor.fromColor(AppTheme.onColor(bg));
  }

  /// Stores a new value for whichever part is selected.
  void _store(HSVColor hsv) {
    setState(() {
      if (_tab == 0) {
        _bg = hsv;
        _syncAuto();
      } else if (_tab == 1) {
        _accent = hsv;
        _accentAuto = false;
      } else {
        _text = hsv;
        _textAuto = false;
      }
    });
  }

  void _setHexText(Color c) {
    final text = _hex(c);
    _hexController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Called when the user types or pastes into the hex field.
  void _onHexChanged(String text) {
    final parsed = _parseHex(text);
    if (parsed == null) return;
    // The text field is left alone so typing isn't interrupted.
    _store(HSVColor.fromColor(parsed));
  }

  /// Called when a slider moves: updates the color and the hex text.
  void _setFromSlider(HSVColor hsv) {
    _store(hsv);
    _setHexText(hsv.toColor());
  }

  void _selectTab(int index) {
    setState(() => _tab = index);
    _setHexText(_current.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final hsv = _current;
    final color = hsv.toColor();
    final hexTextColor = AppTheme.onColor(color);

    // The whole popup is drawn with the colors being picked
    // (and the chosen font, so the preview matches the real app).
    final bgColor = _bg.toColor();
    final previewTheme = AppFonts.apply(
      AppTheme.fromColor(
        bgColor,
        accent: _accent.toColor(),
        text: _text.toColor(),
      ),
      widget.settings.fontFamily,
    );

    return Theme(
      data: previewTheme,
      child: AlertDialog(
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theme Configuration:'),
            SizedBox(height: AppConstants.spaceSm),
            Divider(height: 1),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Three parts: Main | Accent | Text
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Main')),
                    ButtonSegment(value: 1, label: Text('Accent')),
                    ButtonSegment(value: 2, label: Text('Glyph')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => _selectTab(s.first),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),
              // Editable hex code for the selected part
              Container(
                height: 72,
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceMd,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: previewTheme.colorScheme.outline),
                ),
                child: TextField(
                  controller: _hexController,
                  onChanged: _onHexChanged,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  cursorColor: hexTextColor,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(7),
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) => newValue.copyWith(
                        text: newValue.text.toUpperCase(),
                      ),
                    ),
                  ],
                  style: TextStyle(
                    color: hexTextColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),
              _GradientSlider(
                label: 'Hue',
                value: hsv.hue,
                max: 360,
                colors: [
                  for (var h = 0; h <= 360; h += 60)
                    HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
                ],
                onChanged: (v) => _setFromSlider(hsv.withHue(v)),
              ),
              _GradientSlider(
                label: 'Saturation',
                value: hsv.saturation,
                max: 1,
                colors: [
                  hsv.withSaturation(0).toColor(),
                  hsv.withSaturation(1).toColor(),
                ],
                onChanged: (v) => _setFromSlider(hsv.withSaturation(v)),
              ),
              _GradientSlider(
                label: 'Brightness',
                value: hsv.value,
                max: 1,
                colors: [Colors.black, hsv.withValue(1).toColor()],
                onChanged: (v) => _setFromSlider(hsv.withValue(v)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              widget.settings.setCustomTheme(
                background: _bg.toColor(),
                // Colors left on auto are saved as null so they keep
                // following the Main color.
                accent: _accentAuto ? null : _accent.toColor(),
                text: _textAuto ? null : _text.toColor(),
              );
              Navigator.of(context).pop();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

/// A slider whose track is a color gradient.
class _GradientSlider extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  const _GradientSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SizedBox(
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(colors: colors),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 12,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                ),
                child: Slider(
                  value: value.clamp(0.0, max),
                  min: 0,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}