import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../font.dart';
import '../themes.dart';

/// Colors a pop-up: [background] behind, [foreground] for text, buttons,
/// sliders and switches. Built on top of [base].
ThemeData _popupTheme(
  ThemeData base, {
  required Color background,
  required Color foreground,
}) {
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: foreground,
      onPrimary: background,
      onSurface: foreground,
      onSurfaceVariant: foreground.withValues(alpha: AppConstants.mutedAlpha),
    ),
  );
}

/// The pop-up design shared with the Categories screen: accent background,
/// glyph-colored text and buttons, same corners and same spacing.
/// The title is an icon in a rounded box followed by a bold heading.
/// [background] / [foreground] default to the accent colors, and
/// [baseTheme] defaults to the current theme.
Widget _accentDialog(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Widget content,
  required List<Widget> actions,
  Color? background,
  Color? foreground,
  ThemeData? baseTheme,
}) {
  final accent = AppTheme.accentOf(context);
  final bg = background ?? accent.background;
  final fg = foreground ?? accent.foreground;

  return Theme(
    data: _popupTheme(
      baseTheme ?? Theme.of(context),
      background: bg,
      foreground: fg,
    ),
    child: AlertDialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.popupRadius),
      ),
      insetPadding: AppConstants.popupInsetPadding,
      titlePadding: AppConstants.popupTitlePadding,
      contentPadding: AppConstants.popupContentPadding,
      actionsPadding: AppConstants.popupActionsPadding,
      // Builder so the text style comes from the pop-up's own theme
      // (chosen font), not the screen behind it.
      title: Builder(
        builder: (context) {
          final style = Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: fg,
              );
          return Row(
            children: [
              // Icon inside a rounded box, like the "New Account" header.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  // Soft tint of the text color, so it works on any theme.
                  color: fg.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                child: Icon(icon, color: fg, size: 24),
              ),
              const SizedBox(width: AppConstants.spaceMd),
              Expanded(child: Text(title, style: style)),
            ],
          );
        },
      ),
      content: SizedBox(width: double.maxFinite, child: content),
      actions: actions,
    ),
  );
}

/// App-wide user settings. The root MaterialApp listens to this, so any
/// change applies to every screen, dialog and route immediately.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  SharedPreferences? _prefs;

  /// Call once before runApp so saved settings apply from the first frame.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final themeName = prefs.getString(AppConstants.prefTheme);
    if (themeName != null) {
      for (final option in AppThemeOption.values) {
        if (option.name == themeName) {
          _themeOption = option;
          break;
        }
      }
    }

    final sizeIndex = prefs.getInt(AppConstants.prefTextSize);
    if (sizeIndex != null &&
        sizeIndex >= 0 &&
        sizeIndex < AppConstants.textSizeLabels.length) {
      _textSizeIndex = sizeIndex;
    }

    final colorValue = prefs.getInt(AppConstants.prefColor);
    if (colorValue != null) _customColor = Color(colorValue);

    final accentValue = prefs.getInt(AppConstants.prefAccent);
    if (accentValue != null) _accentColor = Color(accentValue);

    final textValue = prefs.getInt(AppConstants.prefText);
    if (textValue != null) _textColor = Color(textValue);

    _fontStyle =
        AppFonts.byLabel(prefs.getString(AppConstants.prefFontStyle));
    _boldText = prefs.getBool(AppConstants.prefBoldText) ?? false;
  }

  // ---- Theme ----
  /// null = follow the system (light/dark) until the user picks one.
  AppThemeOption? _themeOption;
  AppThemeOption? get themeOption => _themeOption;

  /// Background / main color picked with the color picker.
  /// Takes priority over [themeOption].
  Color? _customColor;
  Color? get customColor => _customColor;

  /// Accent color (nav bar, drawer header, version box, settings sections).
  /// null = derived from [customColor].
  Color? _accentColor;
  Color? get accentColor => _accentColor;

  /// Glyph color: fonts, icons and buttons. null = derived from [customColor].
  Color? _textColor;
  Color? get textColor => _textColor;

  void setThemeOption(AppThemeOption option) {
    if (option == _themeOption && _customColor == null) return;
    _themeOption = option;
    _customColor = null;
    _accentColor = null;
    _textColor = null;
    _prefs?.setString(AppConstants.prefTheme, option.name);
    _prefs?.remove(AppConstants.prefColor);
    _prefs?.remove(AppConstants.prefAccent);
    _prefs?.remove(AppConstants.prefText);
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
    _prefs?.setInt(AppConstants.prefColor, background.toARGB32());
    if (accent != null) {
      _prefs?.setInt(AppConstants.prefAccent, accent.toARGB32());
    } else {
      _prefs?.remove(AppConstants.prefAccent);
    }
    if (text != null) {
      _prefs?.setInt(AppConstants.prefText, text.toARGB32());
    } else {
      _prefs?.remove(AppConstants.prefText);
    }
    _prefs?.remove(AppConstants.prefTheme);
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
    _prefs?.setString(AppConstants.prefFontStyle, font.label);
    notifyListeners();
  }

  // ---- Bold text ----
  bool _boldText = false;
  bool get boldText => _boldText;

  void setBoldText(bool value) {
    if (value == _boldText) return;
    _boldText = value;
    _prefs?.setBool(AppConstants.prefBoldText, value);
    notifyListeners();
  }

  // ---- Font size ----
  int _textSizeIndex = AppConstants.defaultTextSizeIndex;
  int get textSizeIndex => _textSizeIndex;
  String get textSizeLabel => AppConstants.textSizeLabels[_textSizeIndex];

  /// Multiplier applied on top of the system text scale.
  double get textScale => AppConstants.textScales[_textSizeIndex];

  void setTextSizeIndex(int index) {
    if (index == _textSizeIndex) return;
    _textSizeIndex = index;
    _prefs?.setInt(AppConstants.prefTextSize, index);
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
            SizedBox(width: AppConstants.spaceSm),
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
      barrierColor: AppConstants.popupBarrier,
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
      barrierColor: AppConstants.popupBarrier,
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
/// with thin dividers between them. It is filled with the theme's
/// Accent color, and the text/icons inside use the accent's readable color.
class _SettingGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final divider = Color.lerp(
      accent.background,
      accent.foreground,
      AppConstants.dividerBlend,
    )!;

    // Tiles inside the group read their colors from the theme, so point
    // them at the accent's readable color.
    final groupTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        onSurface: accent.foreground,
        onSurfaceVariant:
            accent.foreground.withValues(alpha: AppConstants.mutedAlpha),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        iconColor: accent.foreground,
        textColor: accent.foreground,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceMd,
        vertical: AppConstants.spaceXs,
      ),
      child: Theme(
        data: groupTheme,
        child: Material(
          color: accent.background,
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
/// Uses the same pop-up design as the Categories screen.
class _FontConfigDialog extends StatelessWidget {
  final AppSettings settings;
  const _FontConfigDialog({required this.settings});

  @override
  Widget build(BuildContext context) {
    final maxIndex = AppConstants.textSizeLabels.length - 1;

    return _accentDialog(
      context,
      title: 'Font Configuration',
      icon: Icons.text_fields,
      content: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          // Read inside the pop-up, so these are the pop-up's colors.
          final theme = Theme.of(context);
          final fg = theme.colorScheme.onSurface;
          final fgSoft = theme.colorScheme.onSurfaceVariant;

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
                    barrierColor: AppConstants.popupBarrier,
                    builder: (_) => _FontStyleDialog(settings: settings),
                  ),
                ),
                Divider(
                  height: 1,
                  color: fg.withValues(alpha: AppConstants.dividerAlpha),
                ),
                // ---- Font size: text on the left, short slider on the right ----
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppConstants.spaceSm,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.format_size, color: fgSoft),
                      const SizedBox(width: AppConstants.spaceMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Font size',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: fg,
                              ),
                            ),
                            Text(
                              settings.textSizeLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: fgSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Short slider so it fits the pop-up width.
                      SizedBox(
                        width: AppConstants.fontSliderWidth,
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
                Divider(
                  height: 1,
                  color: fg.withValues(alpha: AppConstants.dividerAlpha),
                ),
                // ---- Bold text ----
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.format_bold),
                  title: const Text('Bold text'),
                  value: settings.boldText,
                  onChanged: settings.setBoldText,
                ),
              ],
            ),
          );
        },
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
    return _accentDialog(
      context,
      title: 'Font Style',
      icon: Icons.font_download_outlined,
      content: ListView.builder(
        shrinkWrap: true,
        itemCount: AppFonts.all.length,
        itemBuilder: (context, i) {
          final font = AppFonts.all[i];
          final selected = font.label == _selected.label;
          return ListTile(
            contentPadding: EdgeInsets.zero,
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

/// Pop-up with three parts:
///  - Main: background
///  - Accent: plain color for nav bar, drawer header, version box and
///    settings sections (does not affect buttons)
///  - Glyph: fonts, icons and buttons
/// Same design as the Categories pop-ups. It is drawn with the Accent color
/// being picked as its background and the Glyph color being picked as its
/// text and buttons, so those two update live. The Main color is shown in
/// the color box while the Main tab is selected.
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

  int _tab = 0; // 0 = Main, 1 = Accent, 2 = Glyph
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

  /// Re-derives Accent / Glyph from Main for the ones still on auto.
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

    final bgColor = _bg.toColor();
    final accentColor = _accent.toColor();
    final glyphColor = _text.toColor();

    // Theme being picked, with the chosen font, so the preview matches
    // the real app. The pop-up is drawn on the accent being picked, with
    // the glyph color being picked, like the Categories pop-ups.
    final baseTheme = AppFonts.apply(
      AppTheme.fromColor(
        bgColor,
        accent: accentColor,
        text: glyphColor,
      ),
      widget.settings.fontFamily,
    );

    return _accentDialog(
      context,
      title: 'Theme Configuration',
      icon: Icons.palette_outlined,
      background: accentColor,
      foreground: glyphColor,
      baseTheme: baseTheme,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Three parts: Main | Accent | Glyph
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  foregroundColor: glyphColor,
                  selectedForegroundColor: glyphColor,
                  selectedBackgroundColor: glyphColor.withValues(
                    alpha: AppConstants.segmentSelectedAlpha,
                  ),
                  side: BorderSide(
                    color: glyphColor.withValues(
                      alpha: AppConstants.borderAlpha,
                    ),
                  ),
                ),
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
              height: AppConstants.colorBoxHeight,
              width: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceMd,
              ),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: glyphColor.withValues(
                    alpha: AppConstants.borderAlpha,
                  ),
                ),
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
                  LengthLimitingTextInputFormatter(
                    AppConstants.hexInputLength,
                  ),
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) => newValue.copyWith(
                      text: newValue.text.toUpperCase(),
                    ),
                  ),
                ],
                style: TextStyle(
                  color: hexTextColor,
                  fontWeight: FontWeight.w600,
                  fontSize: AppConstants.hexFontSize,
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
                for (var h = 0.0; h <= 360; h += AppConstants.hueGradientStep)
                  HSVColor.fromAHSV(1, h, 1, 1).toColor(),
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        SizedBox(
          height: AppConstants.gradientSliderHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: AppConstants.gradientTrackHeight,
                margin: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceSmMd,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    AppConstants.gradientTrackHeight / 2,
                  ),
                  gradient: LinearGradient(colors: colors),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: AppConstants.gradientTrackHeight,
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