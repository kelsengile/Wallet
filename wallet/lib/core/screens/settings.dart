import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

import '../../database/helper.dart';
import '../constants.dart';
import '../failures.dart';
import '../font.dart';
import '../themes.dart';
import '../utils.dart';
import '../../services/exchange.dart';
import '../../services/authentication.dart';
import '../../services/notification.dart';

/// The notification switches in Settings > Notifications.
enum NotificationOption {
  push(AppConstants.prefNotifPush, false),
  reminders(AppConstants.prefNotifReminders, true),
  budget(AppConstants.prefNotifBudget, true),
  summary(AppConstants.prefNotifSummary, false),
  sound(AppConstants.prefNotifSound, true),
  vibration(AppConstants.prefNotifVibration, true);

  final String prefKey;
  final bool defaultValue;
  const NotificationOption(this.prefKey, this.defaultValue);
}

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
          final style = Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold, color: fg);
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

/// The transaction types whose color can be changed in
/// Theme > Specific Color. Each one has its own saved key and default.
/// Income points up and Expense points down (same icons everywhere).
enum TransactionColorType {
  income(
    'Income',
    Icons.arrow_upward,
    AppConstants.prefIncomeColor,
    AppConstants.incomeColor,
  ),
  expense(
    'Expense',
    Icons.arrow_downward,
    AppConstants.prefExpenseColor,
    AppConstants.expenseColor,
  ),
  transfer(
    'Transfer',
    Icons.swap_horiz,
    AppConstants.prefTransferColor,
    AppConstants.transferColor,
  ),
  reminder(
    'Reminder',
    Icons.notifications_outlined,
    AppConstants.prefReminderColor,
    AppConstants.reminderColor,
  );

  final String label;
  final IconData icon;
  final String prefKey;
  final Color defaultColor;

  const TransactionColorType(
    this.label,
    this.icon,
    this.prefKey,
    this.defaultColor,
  );
}

/// The action colors that can be changed in Theme > Specific Color >
/// Delete and Done Colors. Each one has its own saved key and default.
enum ActionColorType {
  delete(
    'Delete',
    Icons.delete_outline,
    AppConstants.prefDeleteColor,
    AppConstants.deleteColor,
  ),
  done(
    'Done',
    Icons.check_circle_outline,
    AppConstants.prefDoneColor,
    AppConstants.doneColor,
  );

  final String label;
  final IconData icon;
  final String prefKey;
  final Color defaultColor;

  const ActionColorType(this.label, this.icon, this.prefKey, this.defaultColor);
}

/// Marks every widget dirty so all text, currency signs and times redraw
/// right after a localization change (no state is lost).
void _rebuildEverything() {
  void mark(Element element) {
    element.markNeedsBuild();
    element.visitChildren(mark);
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    WidgetsBinding.instance.rootElement?.visitChildren(mark);
  });
  WidgetsBinding.instance.scheduleFrame();
}

/// App-wide user settings. The root MaterialApp listens to this, so any
/// change applies to every screen, dialog and route immediately.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// Every saved setting, name -> text. Mirrors the `settings` table.
  Map<String, String> _store = {};

  void _save(String name, String value) {
    _store[name] = value;
    DatabaseHelper.instance.setSetting(name, value).catchError((_) {});
  }

  void _remove(String name) {
    _store.remove(name);
    DatabaseHelper.instance.removeSetting(name).catchError((_) {});
  }

  /// Old versions kept settings in SharedPreferences. Copies them into the
  /// database once.
  Future<void> _migrateFromPrefs() async {
    const flag = 'migratedFromPrefs';
    if (_store.containsKey(flag)) return;
    final db = DatabaseHelper.instance;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      final Object? value = prefs.get(key);
      String? text;
      if (key.startsWith('settings.') && value != null) {
        text = '$value';
      } else if (key == AppConstants.prefTypeOrder && value is List<String>) {
        text = value.join(',');
      }
      if (text == null || _store.containsKey(key)) continue;
      _store[key] = text;
      await db.setSetting(key, text);
    }
    _store[flag] = '1';
    await db.setSetting(flag, '1');
  }

  /// Category order used to live in SharedPreferences (one string list per
  // ignore: unintended_html_in_doc_comment
  /// list, key "category_order_<group>"). Moves it into the settings table
  /// once, so it is included in backups.
  Future<void> _migrateCategoryOrderFromPrefs() async {
    const flag = 'migratedCategoryOrder';
    if (_store.containsKey(flag)) return;
    final db = DatabaseHelper.instance;
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith('category_order_')) continue;
      final value = prefs.get(key);
      if (value is List<String>) {
        final name = key.replaceFirst(
          'category_order_',
          AppConstants.prefCategoryOrder,
        );
        if (!_store.containsKey(name)) {
          final text = value.join(',');
          _store[name] = text;
          await db.setSetting(name, text);
        }
      }
      await prefs.remove(
        key,
      ); // so an old value can't come back after an import
    }
    _store[flag] = '1';
    await db.setSetting(flag, '1');
  }

  /// Call before runApp (and again after an import) so saved settings
  /// apply from the first frame.
  Future<void> load() async {
    try {
      _store = await DatabaseHelper.instance.getAllSettings();
      await _migrateFromPrefs();
      await _migrateCategoryOrderFromPrefs();
    } catch (_) {
      _store = {}; // database unreadable: defaults are used
    }

    _themeOption = null;
    final themeName = _store[AppConstants.prefTheme];
    for (final option in AppThemeOption.values) {
      if (option.name == themeName) _themeOption = option;
    }

    final sizeIndex = int.tryParse(_store[AppConstants.prefTextSize] ?? '');
    _textSizeIndex =
        (sizeIndex != null &&
            sizeIndex >= 0 &&
            sizeIndex < AppConstants.textSizeLabels.length)
        ? sizeIndex
        : AppConstants.defaultTextSizeIndex;

    _animEnabled = _store[AppConstants.prefAnimEnabled] != 'false';

    final animIndex = int.tryParse(_store[AppConstants.prefAnimSpeed] ?? '');
    _animSpeedIndex =
        (animIndex != null &&
            animIndex >= 0 &&
            animIndex < AppConstants.animSpeedLabels.length)
        ? animIndex
        : AppConstants.defaultAnimSpeedIndex;
    _applyAnimSpeed();

    Color? colorOf(String key) {
      final v = int.tryParse(_store[key] ?? '');
      return v == null ? null : Color(v);
    }

    _customColor = colorOf(AppConstants.prefColor);
    _accentColor = colorOf(AppConstants.prefAccent);
    _textColor = colorOf(AppConstants.prefText);

    _transactionColors.clear();
    for (final type in TransactionColorType.values) {
      final c = colorOf(type.prefKey);
      if (c != null) _transactionColors[type] = c;
    }
    _actionColors.clear();
    for (final type in ActionColorType.values) {
      final c = colorOf(type.prefKey);
      if (c != null) _actionColors[type] = c;
    }

    await AppFonts.loadImported(_store);
    _fontStyle = AppFonts.byLabel(_store[AppConstants.prefFontStyle]);
    _boldText = _store[AppConstants.prefBoldText] == 'true';
    _currency = AppConstants.currencyByCode(_store[AppConstants.prefCurrency]);
    AppConstants.currencySymbol = _currency.symbol;
    _location = AppConstants.locationById(_store[AppConstants.prefLocation]);
    AppConstants.locationOffsetMinutes = _location.utcMinutes;
    _language = AppConstants.languageByCode(_store[AppConstants.prefLanguage]);
    AppConstants.languageCode = _language.code;
    await _loadSecurity();
    _notif.clear();
    for (final o in NotificationOption.values) {
      final v = _store[o.prefKey];
      if (v != null) _notif[o] = v == 'true';
    }
    notifyListeners();
    NotificationService.instance.scheduleSync();
    _rebuildEverything();
  }

  // ---- Localization ----
  AppCurrency _currency = AppConstants.currencies.first;
  AppCurrency get currency => _currency;

  AppLocation _location = AppConstants.locations.first;
  AppLocation get location => _location;

  AppLanguage _language = AppConstants.languages.first;
  AppLanguage get language => _language;

  // ---- Notifications ----
  final Map<NotificationOption, bool> _notif = {};

  bool notif(NotificationOption o) => _notif[o] ?? o.defaultValue;

  Future<bool> setPush(bool on) async {
    if (on && !await NotificationService.instance.requestPermission()) {
      return false;
    }
    _notif[NotificationOption.push] = on;
    _save(NotificationOption.push.prefKey, '$on');
    notifyListeners();
    NotificationService.instance.scheduleSync();
    return true;
  }

  void setNotif(NotificationOption o, bool value) {
    if (notif(o) == value) return;
    _notif[o] = value;
    _save(o.prefKey, '$value');
    notifyListeners();
    NotificationService.instance.scheduleSync();
  }

  void setCurrency(AppCurrency c) {
    if (c.code == _currency.code) return;
    _currency = c;
    AppConstants.currencySymbol = c.symbol;
    _save(AppConstants.prefCurrency, c.code);
    notifyListeners();
    NotificationService.instance.scheduleSync();
    _rebuildEverything();
  }

  void setLocation(AppLocation l) {
    if (l.id == _location.id) return;
    _location = l;
    AppConstants.locationOffsetMinutes = l.utcMinutes;
    _save(AppConstants.prefLocation, l.id);
    notifyListeners();
    NotificationService.instance.scheduleSync();
    _rebuildEverything();
  }

  void setLanguage(AppLanguage l) {
    if (l.code == _language.code) return;
    _language = l;
    AppConstants.languageCode = l.code;
    _save(AppConstants.prefLanguage, l.code);
    notifyListeners();
    _rebuildEverything();
  }

  // ---- Security (kept in SharedPreferences, not in backups) ----
  bool _securityEnabled = false;
  Set<SecurityMethod> _securityMethods = {};
  bool get securityEnabled => _securityEnabled;
  Set<SecurityMethod> get securityMethods => _securityMethods;

  Future<void> _loadSecurity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _securityEnabled = prefs.getBool(AppConstants.prefSecurityOn) ?? false;
      final names =
          prefs.getStringList(AppConstants.prefSecurityMethods) ??
          const <String>[];
      _securityMethods = {
        for (final m in SecurityMethod.values)
          if (m != SecurityMethod.pin && names.contains(m.name)) m,
      };
      // Security turned on by an older version has no app PIN yet.
      // Switch it off once so nobody is locked out.
      if (_securityEnabled &&
          !prefs.containsKey(AppConstants.prefSecurityPinHash)) {
        _securityEnabled = false;
        _securityMethods = {};
        await prefs.setBool(AppConstants.prefSecurityOn, false);
      }
    } catch (_) {
      _securityEnabled = false;
      _securityMethods = {};
    }
  }

  Future<void> setSecurity({
    required bool enabled,
    required Set<SecurityMethod> methods,
  }) async {
    _securityEnabled = enabled;
    _securityMethods = methods;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.prefSecurityOn, enabled);
      await prefs.setStringList(AppConstants.prefSecurityMethods, [
        for (final m in methods) m.name,
      ]);
    } catch (_) {}
  }

  // ---- Theme ----
  AppThemeOption? _themeOption;
  AppThemeOption? get themeOption => _themeOption;

  Color? _customColor;
  Color? get customColor => _customColor;

  Color? _accentColor;
  Color? get accentColor => _accentColor;

  Color? _textColor;
  Color? get textColor => _textColor;

  void setThemeOption(AppThemeOption option) {
    if (option == _themeOption && _customColor == null) return;
    _themeOption = option;
    _customColor = null;
    _accentColor = null;
    _textColor = null;
    _save(AppConstants.prefTheme, option.name);
    _remove(AppConstants.prefColor);
    _remove(AppConstants.prefAccent);
    _remove(AppConstants.prefText);
    notifyListeners();
  }

  void setCustomTheme({required Color background, Color? accent, Color? text}) {
    _customColor = background;
    _accentColor = accent;
    _textColor = text;
    _themeOption = null;
    _save(AppConstants.prefColor, background.toARGB32().toString());
    if (accent != null) {
      _save(AppConstants.prefAccent, accent.toARGB32().toString());
    } else {
      _remove(AppConstants.prefAccent);
    }
    if (text != null) {
      _save(AppConstants.prefText, text.toARGB32().toString());
    } else {
      _remove(AppConstants.prefText);
    }
    _remove(AppConstants.prefTheme);
    notifyListeners();
  }

  // ---- Specific colors: transaction types ----
  final Map<TransactionColorType, Color> _transactionColors = {};

  Color transactionColor(TransactionColorType type) =>
      _transactionColors[type] ?? type.defaultColor;

  Color get incomeColor => transactionColor(TransactionColorType.income);
  Color get expenseColor => transactionColor(TransactionColorType.expense);
  Color get transferColor => transactionColor(TransactionColorType.transfer);
  Color get reminderColor => transactionColor(TransactionColorType.reminder);

  void setTransactionColor(TransactionColorType type, Color color) {
    if (transactionColor(type) == color) return;
    _transactionColors[type] = color;
    _save(type.prefKey, color.toARGB32().toString());
    notifyListeners();
  }

  // ---- Specific colors: actions (Delete / Done) ----
  final Map<ActionColorType, Color> _actionColors = {};

  Color actionColor(ActionColorType type) =>
      _actionColors[type] ?? type.defaultColor;

  Color get deleteColor => actionColor(ActionColorType.delete);
  Color get doneColor => actionColor(ActionColorType.done);

  void setActionColor(ActionColorType type, Color color) {
    if (actionColor(type) == color) return;
    _actionColors[type] = color;
    _save(type.prefKey, color.toARGB32().toString());
    notifyListeners();
  }

  // ---- Font style ----
  AppFont _fontStyle = AppFonts.defaultFont;
  AppFont get fontStyle => _fontStyle;
  String? get fontFamily => _fontStyle.family;

  void setFontStyle(AppFont font) {
    if (font.label == _fontStyle.label) return;
    _fontStyle = font;
    _save(AppConstants.prefFontStyle, font.label);
    notifyListeners();
  }

  // ---- Bold text ----
  bool _boldText = false;
  bool get boldText => _boldText;

  void setBoldText(bool value) {
    if (value == _boldText) return;
    _boldText = value;
    _save(AppConstants.prefBoldText, '$value');
    notifyListeners();
  }

  // ---- Font size ----
  int _textSizeIndex = AppConstants.defaultTextSizeIndex;
  int get textSizeIndex => _textSizeIndex;
  String get textSizeLabel => AppConstants.textSizeLabels[_textSizeIndex];
  double get textScale => AppConstants.textScales[_textSizeIndex];

  void setTextSizeIndex(int index) {
    if (index == _textSizeIndex) return;
    _textSizeIndex = index;
    _save(AppConstants.prefTextSize, '$index');
    notifyListeners();
  }

  // ---- Animation ----
  bool _animEnabled = true;
  bool get animEnabled => _animEnabled;

  int _animSpeedIndex = AppConstants.defaultAnimSpeedIndex;
  int get animSpeedIndex => _animSpeedIndex;
  String get animSpeedLabel => AppConstants.animSpeedLabels[_animSpeedIndex];

  /// "Off" = animations finish almost instantly. (timeDilation must stay > 0.)
  void _applyAnimSpeed() {
    timeDilation = _animEnabled
        ? AppConstants.animTimeDilations[_animSpeedIndex]
        : 0.001;
  }

  void setAnimEnabled(bool value) {
    if (value == _animEnabled) return;
    _animEnabled = value;
    _applyAnimSpeed();
    _save(AppConstants.prefAnimEnabled, '$value');
    notifyListeners();
  }

  void setAnimSpeedIndex(int index) {
    if (index == _animSpeedIndex) return;
    _animSpeedIndex = index;
    _applyAnimSpeed();
    _save(AppConstants.prefAnimSpeed, '$index');
    notifyListeners();
  }
}

/// Name of the current theme: "Custom", the built-in one, or the system one.
String _themeLabel(BuildContext context, AppSettings settings) {
  if (settings.customColor != null) return 'Custom';
  final chosen = settings.themeOption;
  if (chosen != null) return chosen.label;
  return Theme.of(context).brightness == Brightness.dark ? 'Dark' : 'Light';
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.settings_outlined),
            const SizedBox(width: AppConstants.spaceSm),
            Text('Settings'.tr),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.only(bottom: AppConstants.spaceLg),
            children: [
              _SectionHeader('Appearance'),
              _SettingGroup(
                children: [
                  _buildThemeTile(context, settings),
                  _buildFontTile(context, settings),
                  _buildAnimationTile(context, settings),
                ],
              ),
              const SizedBox(height: AppConstants.spaceSm),
              _SectionHeader('Localization'),
              _SettingGroup(
                children: [
                  _buildCurrencyTile(context, settings),
                  _buildLocationTile(context, settings),
                  _buildLanguageTile(context, settings),
                ],
              ),
              const SizedBox(height: AppConstants.spaceSm),
              _SectionHeader('Security'),
              _SecuritySection(settings: settings),
              const SizedBox(height: AppConstants.spaceSm),
              _SectionHeader('Notifications'),
              _NotificationsSection(settings: settings),
            ],
          );
        },
      ),
    );
  }

  // ---------- Theme ----------

  Widget _buildThemeTile(BuildContext context, AppSettings settings) {
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: Text('Theme'.tr),
      subtitle: Text(_themeLabel(context, settings)),
      trailing: _ThemeSwatch(Theme.of(context).colorScheme.surface),
      onTap: () => _showThemeConfig(context, settings),
    );
  }

  /// Opens the Theme Configuration pop-up (General Color / Specific Color).
  Future<void> _showThemeConfig(BuildContext context, AppSettings settings) {
    return showDialog<void>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (_) => _ThemeConfigDialog(settings: settings),
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
      title: Text('Font'.tr),
      subtitle: Text(_fontSummary(settings)),
      trailing: const Icon(Icons.chevron_right),
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

  // ---------- Localization ----------

  Widget _buildCurrencyTile(BuildContext context, AppSettings settings) {
    final c = settings.currency;
    return ListTile(
      leading: const Icon(Icons.attach_money),
      title: Text('Currency'.tr),
      subtitle: Text('${c.code} (${c.symbol}) · ${c.name}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showCurrencyFlow(context, settings),
    );
  }

  Widget _buildLocationTile(BuildContext context, AppSettings settings) {
    final l = settings.location;
    return ListTile(
      leading: const Icon(Icons.location_on_outlined),
      title: Text('Location'.tr),
      subtitle: Text('${l.name} · ${_utcLabel(l.utcMinutes)}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showLocationFlow(context, settings),
    );
  }

  Widget _buildLanguageTile(BuildContext context, AppSettings settings) {
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text('Language'.tr),
      subtitle: Text(settings.language.native),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showLanguageFlow(context, settings),
    );
  }
}

// ---------- Animation ----------

Widget _buildAnimationTile(BuildContext context, AppSettings settings) {
  return ListTile(
    leading: const Icon(Icons.speed),
    title: Text('Animation'.tr),
    subtitle: Text(settings.animEnabled ? settings.animSpeedLabel : 'Off'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => showDialog<void>(
      context: context,
      barrierColor: AppConstants.popupBarrier,
      builder: (_) => _AnimationConfigDialog(settings: settings),
    ),
  );
}

// ------------------------------------------------------------------
// Security section
// ------------------------------------------------------------------

/// App Security switch first. Only after it is on do the methods appear,
/// and only the ones this phone actually has.
class _SecuritySection extends StatefulWidget {
  final AppSettings settings;
  const _SecuritySection({required this.settings});

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  List<SecurityMethod> _available = const []; // biometrics on this phone
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final found = await AppSecurity.available();
    if (!mounted) return;
    setState(() => _available = found);
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _askPin(_PinMode mode) => showDialog<String>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (_) => _PinDialog(mode: mode),
  );

  Future<void> _toggleMaster(bool on) async {
    final s = widget.settings;
    setState(() => _busy = true);
    try {
      if (on) {
        final pin = await _askPin(_PinMode.create);
        if (pin == null) return;
        await AppSecurity.setPin(pin);
        await s.setSecurity(enabled: true, methods: {});
      } else {
        final pin = await _askPin(_PinMode.verify);
        if (pin == null) return;
        await s.setSecurity(enabled: false, methods: {});
        await AppSecurity.clearPin();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMethod(SecurityMethod m, bool on) async {
    final s = widget.settings;
    setState(() => _busy = true);
    try {
      if (on) {
        final ok = await AppSecurity.authenticate(
          'Confirm ${m.label} to turn it on.',
        );
        if (!ok) {
          _say('Couldn\'t verify ${m.label}.');
          return;
        }
      }
      final next = {...s.securityMethods};
      if (on) {
        next.add(m);
      } else {
        next.remove(m);
      }
      await s.setSecurity(enabled: true, methods: next);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePin() async {
    final pin = await _askPin(_PinMode.change);
    if (pin == null) return;
    await AppSecurity.setPin(pin);
    _say('PIN changed.');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final enabled = s.securityEnabled;
        final children = <Widget>[
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: Text('App Security'.tr),
            subtitle: Text(enabled ? 'On' : 'Off'),
            value: enabled,
            onChanged: _busy ? null : _toggleMaster,
          ),
        ];
        var noDivider = const <int>{};
        if (enabled) {
          for (final m in _available) {
            children.add(
              SwitchListTile(
                secondary: Icon(m.icon),
                title: Text(m.label.tr),
                value: s.securityMethods.contains(m),
                onChanged: _busy ? null : (v) => _toggleMethod(m, v),
              ),
            );
          }
          // PIN sits under Touch ID with no divider between them.
          if (_available.isNotEmpty) noDivider = {children.length};
          children.add(
            ListTile(
              leading: Icon(SecurityMethod.pin.icon),
              title: Text(SecurityMethod.pin.label.tr),
              subtitle: const Text('Tap to change your PIN'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _changePin,
            ),
          );
        }
        return _SettingGroup(noDividerAt: noDivider, children: children);
      },
    );
  }
}

enum _PinMode { create, change, verify }

/// Create a PIN, change it (asks for the current one first), or just
/// confirm the current one. Pops the PIN that was typed (the new one for
/// create / change), or null when cancelled.
class _PinDialog extends StatefulWidget {
  final _PinMode mode;
  const _PinDialog({required this.mode});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _error;
  bool _checking = false;

  bool get _askCurrent => widget.mode != _PinMode.create;
  bool get _askNew => widget.mode != _PinMode.verify;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking) return;
    if (_askCurrent) {
      setState(() => _checking = true);
      final ok = await AppSecurity.verifyPin(_current.text);
      if (!mounted) return;
      setState(() => _checking = false);
      if (!ok) {
        setState(() => _error = 'That PIN is wrong.');
        return;
      }
    }
    if (_askNew) {
      if (_next.text.length < AppConstants.pinMinLength) {
        setState(
          () => _error =
              'Use ${AppConstants.pinMinLength} to '
              '${AppConstants.pinMaxLength} digits.',
        );
        return;
      }
      if (_next.text != _again.text) {
        setState(() => _error = 'The PINs don\'t match.');
        return;
      }
    }
    Navigator.of(context).pop(_askNew ? _next.text : _current.text);
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.mode) {
      _PinMode.create => 'Create PIN',
      _PinMode.change => 'Change PIN',
      _PinMode.verify => 'Enter PIN',
    };

    return _accentDialog(
      context,
      title: title,
      icon: Icons.pin_outlined,
      content: Builder(
        builder: (context) {
          final fg = Theme.of(context).colorScheme.onSurface;

          Widget field(
            TextEditingController c,
            String label, {
            required bool last,
          }) => Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.spaceSmMd),
            child: TextField(
              controller: c,
              obscureText: true,
              cursorColor: fg,
              style: TextStyle(color: fg),
              keyboardType: TextInputType.number,
              textInputAction: last
                  ? TextInputAction.done
                  : TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(AppConstants.pinMaxLength),
              ],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: last ? (_) => _submit() : null,
              decoration: InputDecoration(
                labelText: label,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
              ),
            ),
          );

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppConstants.spaceXs),
                if (_askCurrent)
                  field(
                    _current,
                    _askNew ? 'Current PIN' : 'PIN',
                    last: !_askNew,
                  ),
                if (_askNew) ...[
                  field(_next, 'New PIN', last: false),
                  field(_again, 'Confirm new PIN', last: true),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(fontWeight: FontWeight.w600, color: fg),
                  ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: Text(widget.mode == _PinMode.verify ? 'Confirm' : 'Save'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------
// Localization pop-ups
// ------------------------------------------------------------------

String _utcLabel(int minutes) {
  final sign = minutes < 0 ? '-' : '+';
  final a = minutes.abs();
  final h = a ~/ 60;
  final m = a % 60;
  return 'UTC$sign$h${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'}';
}

String _clockAt(int minutes) {
  final t = DateTime.now().toUtc().add(Duration(minutes: minutes));
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '${Utils.formatDate(t)} · $h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
}

Future<void> _showCurrencyFlow(BuildContext context, AppSettings s) async {
  final from = s.currency;
  final index = await showDialog<int>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (_) => _ChoiceDialog(
      title: 'Currency'.tr,
      icon: Icons.attach_money,
      initial: AppConstants.currencies.indexWhere((c) => c.code == from.code),
      items: [
        for (final c in AppConstants.currencies)
          ('${c.code} (${c.symbol})', c.name),
      ],
    ),
  );
  if (index == null || !context.mounted) return;
  final to = AppConstants.currencies[index];
  if (to.code == from.code) return;

  final choice = await showDialog<_ConvertChoice>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (_) => _ConvertDialog(from: from, to: to),
  );
  if (choice == null) return;

  if (choice.convert) {
    try {
      await DatabaseHelper.instance.convertAmounts(choice.rate);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                error is Failure ? error.message : 'Something went wrong.',
              ),
            ),
          );
      }
      return;
    }
  }
  s.setCurrency(to);
}

Future<void> _showLocationFlow(BuildContext context, AppSettings s) async {
  final index = await showDialog<int>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (_) => _ChoiceDialog(
      title: 'Location'.tr,
      icon: Icons.location_on_outlined,
      initial: AppConstants.locations.indexWhere((l) => l.id == s.location.id),
      items: [
        for (final l in AppConstants.locations)
          (l.name, _utcLabel(l.utcMinutes)),
      ],
      note: (i) =>
          'Time there now: ${_clockAt(AppConstants.locations[i].utcMinutes)}',
    ),
  );
  if (index == null) return;
  s.setLocation(AppConstants.locations[index]);
}

Future<void> _showLanguageFlow(BuildContext context, AppSettings s) async {
  final index = await showDialog<int>(
    context: context,
    barrierColor: AppConstants.popupBarrier,
    builder: (_) => _ChoiceDialog(
      title: 'Language'.tr,
      icon: Icons.language,
      initial: AppConstants.languages.indexWhere(
        (l) => l.code == s.language.code,
      ),
      items: [for (final l in AppConstants.languages) (l.native, l.name)],
    ),
  );
  if (index == null) return;
  s.setLanguage(AppConstants.languages[index]);
}

/// Pop-up with a list to pick from. Pops the picked index on Apply.
class _ChoiceDialog extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<(String, String?)> items;
  final int initial;
  final String Function(int index)? note;
  const _ChoiceDialog({
    required this.title,
    required this.icon,
    required this.items,
    required this.initial,
    this.note,
  });

  @override
  State<_ChoiceDialog> createState() => _ChoiceDialogState();
}

class _ChoiceDialogState extends State<_ChoiceDialog> {
  late int _sel = widget.initial < 0 ? 0 : widget.initial;
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: ((_sel - 2) * 72.0).clamp(0.0, double.infinity),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _accentDialog(
      context,
      title: widget.title,
      icon: widget.icon,
      content: Builder(
        builder: (context) {
          final soft = Theme.of(context).colorScheme.onSurfaceVariant;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppConstants.spaceSm),
                  child: Text(
                    widget.note!(_sel),
                    style: TextStyle(fontSize: 13, color: soft),
                  ),
                ),
              Flexible(
                child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  itemCount: widget.items.length,
                  itemBuilder: (context, i) {
                    final item = widget.items[i];
                    final selected = i == _sel;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spaceMd,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                      ),
                      title: Text(item.$1),
                      subtitle: item.$2 == null ? null : Text(item.$2!),
                      trailing: selected ? const Icon(Icons.check) : null,
                      selected: selected,
                      onTap: () => setState(() => _sel = i),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_sel),
          child: Text('Apply'.tr),
        ),
      ],
    );
  }
}

class _ConvertChoice {
  final bool convert;
  final double rate;
  const _ConvertChoice(this.convert, this.rate);
}

/// Asks whether the saved amounts should be converted to the new currency
/// (with an editable rate), or only the currency sign should change.
class _ConvertDialog extends StatefulWidget {
  final AppCurrency from;
  final AppCurrency to;
  const _ConvertDialog({required this.from, required this.to});

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  late final TextEditingController _rate = TextEditingController(
    text: _fmt(widget.to.perUsd / widget.from.perUsd), // offline fallback
  );
  bool _loadingRate = true;
  bool _live = false;
  bool _edited = false; // the user typed a rate: never overwrite it

  @override
  void initState() {
    super.initState();
    _fetchLive();
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _fetchLive() async {
    final ok = await ExchangeRates.instance.refresh();
    if (!mounted) return;
    final live = ok
        ? ExchangeRates.instance.rate(widget.from.code, widget.to.code)
        : null;
    setState(() {
      _loadingRate = false;
      if (live != null) {
        _live = true;
        if (!_edited) _rate.text = _fmt(live);
      }
    });
  }

  /// Keeps small rates (like VND -> USD) from rounding to 0.
  String _fmt(double v) {
    var t = v >= 100 ? v.toStringAsFixed(2) : v.toStringAsPrecision(6);
    if (t.contains('.') && !t.contains('e')) {
      t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return t;
  }

  String _updatedText() {
    final t = ExchangeRates.instance.updatedAt?.toLocal();
    if (t == null) return '';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '${Utils.formatDate(t)} · $h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  double? get _value {
    final v = double.tryParse(_rate.text.trim());
    return (v != null && v.isFinite && v > 0 && v < 1e7) ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    final from = widget.from;
    final to = widget.to;
    final rate = _value;

    return _accentDialog(
      context,
      title: 'Convert your amounts?'.tr,
      icon: Icons.currency_exchange,
      content: Builder(
        builder: (context) {
          final soft = Theme.of(context).colorScheme.onSurfaceVariant;
          final fg = Theme.of(context).colorScheme.onSurface;
          final status = _loadingRate
              ? 'Getting the latest rate…'
              : _live
              ? 'Live rate · updated ${_updatedText()}'
              : 'Couldn\'t get a live rate, so this one is approximate. '
                    'Check your connection or edit it.';
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your saved amounts are in ${from.code}. Convert all '
                  'accounts, transactions, reminders and budgets to '
                  '${to.code}, or only change the sign and keep the '
                  'numbers as they are?',
                  style: TextStyle(fontSize: 14, height: 1.4, color: soft),
                ),
                const SizedBox(height: AppConstants.spaceMd),
                Row(
                  children: [
                    Text('1 ${from.code} =', style: TextStyle(color: fg)),
                    const SizedBox(width: AppConstants.spaceSm),
                    Expanded(
                      child: TextField(
                        controller: _rate,
                        cursorColor: fg,
                        style: TextStyle(color: fg),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        onChanged: (_) => setState(() => _edited = true),
                        decoration: InputDecoration(
                          isDense: true,
                          errorText: rate == null ? 'Invalid' : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusSm,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spaceSm),
                    Text(to.code, style: TextStyle(color: fg)),
                  ],
                ),
                const SizedBox(height: AppConstants.spaceSm),
                Text(
                  rate == null
                      ? ''
                      : '${Utils.formatCurrency(1000, symbol: from.symbol)} '
                            '≈ ${Utils.formatCurrency(1000 * rate, symbol: to.symbol)}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: fg),
                ),
                const SizedBox(height: AppConstants.spaceSm),
                Text(status, style: TextStyle(fontSize: 12, color: soft)),
                const SizedBox(height: 4),
                Text(
                  'Converting cannot be undone, except by converting back.',
                  style: TextStyle(fontSize: 12, color: soft),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const _ConvertChoice(false, 1)),
          child: Text('Keep amounts'.tr),
        ),
        FilledButton(
          onPressed: (rate == null || _loadingRate)
              ? null
              : () => Navigator.of(context).pop(_ConvertChoice(true, rate)),
          child: Text('Convert'.tr),
        ),
      ],
    );
  }
}

// ---------- Animation ----------

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

  /// Indexes of children that get no divider above them.
  final Set<int> noDividerAt;
  const _SettingGroup({required this.children, this.noDividerAt = const {}});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final divider = Color.lerp(
      accent.background,
      accent.foreground,
      AppConstants.dividerBlend,
    )!;

    final groupTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        onSurface: accent.foreground,
        onSurfaceVariant: accent.foreground.withValues(
          alpha: AppConstants.mutedAlpha,
        ),
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
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0 && !noDividerAt.contains(i))
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
        title.tr,
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
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.settings.fontStyle;
  }

  /// Pick a .ttf / .otf file and add it to the list.
  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Import font',
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf'],
      );
      if (picked.isEmpty) return; // cancelled
      final file = picked.single;
      final bytes = await file.readAsBytes();
      final font = await AppFonts.importFont(file.name, bytes);
      if (!mounted) return;
      setState(() => _selected = font); // highlighted; Apply uses it
    } catch (_) {
      if (mounted) setState(() => _error = 'That isn\'t a usable font file.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AppFont font) async {
    try {
      // Switch away first so nothing is drawing with the font.
      if (widget.settings.fontStyle.label == font.label) {
        widget.settings.setFontStyle(AppFonts.defaultFont);
      }
      await AppFonts.removeImported(font);
      if (!mounted) return;
      setState(() {
        if (_selected.label == font.label) _selected = AppFonts.defaultFont;
        _error = null;
      });
      // Redraw the whole app now. The pop-up stays open.
      _rebuildEverything();
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn\'t remove that font.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fonts = AppFonts.all;
    return _accentDialog(
      context,
      title: 'Font Style',
      icon: Icons.font_download_outlined,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: fonts.length,
              itemBuilder: (context, i) {
                final font = fonts[i];
                final selected = font.label == _selected.label;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spaceMd,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                  title: Text(
                    font.label,
                    style: TextStyle(fontFamily: font.family),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected) const Icon(Icons.check),
                      if (font.isImported)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(font),
                        ),
                    ],
                  ),
                  selected: selected,
                  onTap: () => setState(() => _selected = font),
                );
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppConstants.spaceSm),
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
        ],
      ),
      actions: [
        // One row: import button pinned to the far left,
        // Cancel / Apply on the right.
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              IconButton.filled(
                tooltip: 'Import font',
                onPressed: _busy ? null : _import,
                icon: _busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_upload_outlined),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              FilledButton(
                onPressed: () {
                  widget.settings.setFontStyle(_selected);
                  Navigator.of(context).pop();
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------
// Theme configuration (General Color / Specific Color)
// ------------------------------------------------------------------

/// First pop-up of the Theme tile, built like the Font pop-up:
///  - General Color (opens the Main / Accent / Glyph picker)
///  - Specific Color (opens the list of colors for parts of the app)
/// Only a Close button; the colors are applied from the pop-ups it opens.
class _ThemeConfigDialog extends StatelessWidget {
  final AppSettings settings;
  const _ThemeConfigDialog({required this.settings});

  @override
  Widget build(BuildContext context) {
    return _accentDialog(
      context,
      title: 'Theme Configuration',
      icon: Icons.palette_outlined,
      content: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          // Read inside the pop-up, so these are the pop-up's colors.
          final theme = Theme.of(context);
          final fg = theme.colorScheme.onSurface;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- General Color ----
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('General Color'),
                  subtitle: Text(_themeLabel(context, settings)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDialog<void>(
                    context: context,
                    barrierColor: AppConstants.popupBarrier,
                    builder: (_) => _GeneralColorDialog(
                      initial:
                          settings.customColor ??
                          Theme.of(context).colorScheme.surface,
                      settings: settings,
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: fg.withValues(alpha: AppConstants.dividerAlpha),
                ),
                // ---- Specific Color ----
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune),
                  title: const Text('Specific Color'),
                  subtitle: const Text('Transaction colors'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDialog<void>(
                    context: context,
                    barrierColor: AppConstants.popupBarrier,
                    builder: (_) => _SpecificColorDialog(settings: settings),
                  ),
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

/// Pop-up with the colors of specific parts of the app.
/// For now: Transaction colors (Income, Expense, Transfer, Reminder).
/// Each one is a bar with its color in a circle on the right side.
/// Tapping a bar opens the color pop-up for that transaction type.
class _SpecificColorDialog extends StatelessWidget {
  final AppSettings settings;
  const _SpecificColorDialog({required this.settings});

  @override
  Widget build(BuildContext context) {
    return _accentDialog(
      context,
      title: 'Specific Color',
      icon: Icons.tune,
      content: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final theme = Theme.of(context);
          final fgSoft = theme.colorScheme.onSurface;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: AppConstants.spaceSm),
                  child: Text(
                    'Transaction Colors',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: fgSoft,
                    ),
                  ),
                ),
                for (final type in TransactionColorType.values)
                  _ColorBar(
                    label: type.label,
                    icon: type.icon,
                    color: settings.transactionColor(type),
                    onTap: () => showDialog<void>(
                      context: context,
                      barrierColor: AppConstants.popupBarrier,
                      builder: (_) => _TransactionColorDialog(
                        type: type,
                        settings: settings,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppConstants.spaceSm,
                    bottom: AppConstants.spaceSm,
                  ),
                  child: Text(
                    'Confirmation Colors',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: fgSoft,
                    ),
                  ),
                ),
                for (final type in ActionColorType.values)
                  _ColorBar(
                    label: type.label,
                    icon: type.icon,
                    color: settings.actionColor(type),
                    onTap: () async {
                      final picked = await showDialog<Color>(
                        context: context,
                        barrierColor: AppConstants.popupBarrier,
                        builder: (_) => ColorPickerDialog(
                          title: type.label,
                          icon: type.icon,
                          initial: settings.actionColor(type),
                        ),
                      );
                      if (picked != null) settings.setActionColor(type, picked);
                    },
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

/// One bar: icon + name on the left, the chosen color in a circle on the right.
class _ColorBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ColorBar({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceSm),
      child: Material(
        color: fg.withValues(alpha: AppConstants.tintAlpha),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spaceMd,
              vertical: AppConstants.spaceSmMd,
            ),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 22),
                const SizedBox(width: AppConstants.spaceSmMd),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: fg.withValues(alpha: AppConstants.borderAlpha),
                      width: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pop-up to change the color of one transaction type. The title is the
/// type's name. It has the same hex box and sliders as the General Color
/// picker, plus Cancel and Apply buttons.
class _TransactionColorDialog extends StatefulWidget {
  final TransactionColorType type;
  final AppSettings settings;
  const _TransactionColorDialog({required this.type, required this.settings});

  @override
  State<_TransactionColorDialog> createState() =>
      _TransactionColorDialogState();
}

class _TransactionColorDialogState extends State<_TransactionColorDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    final start = widget.settings.transactionColor(widget.type);
    _hsv = HSVColor.fromColor(start);
    _hexController = TextEditingController(text: _hex(start));
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
    setState(() => _hsv = HSVColor.fromColor(parsed));
  }

  /// Called when a slider moves: updates the color and the hex text.
  void _setFromSlider(HSVColor hsv) {
    setState(() => _hsv = hsv);
    _setHexText(hsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    final hexTextColor = AppTheme.onColor(color);
    final fg = AppTheme.accentOf(context).foreground;

    return _accentDialog(
      context,
      title: widget.type.label,
      icon: widget.type.icon,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Editable hex code
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
                  color: fg.withValues(alpha: AppConstants.borderAlpha),
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
                  LengthLimitingTextInputFormatter(AppConstants.hexInputLength),
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toUpperCase()),
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
              value: _hsv.hue,
              max: 360,
              colors: [
                for (var h = 0.0; h <= 360; h += AppConstants.hueGradientStep)
                  HSVColor.fromAHSV(1, h, 1, 1).toColor(),
              ],
              onChanged: (v) => _setFromSlider(_hsv.withHue(v)),
            ),
            _GradientSlider(
              label: 'Saturation',
              value: _hsv.saturation,
              max: 1,
              colors: [
                _hsv.withSaturation(0).toColor(),
                _hsv.withSaturation(1).toColor(),
              ],
              onChanged: (v) => _setFromSlider(_hsv.withSaturation(v)),
            ),
            _GradientSlider(
              label: 'Brightness',
              value: _hsv.value,
              max: 1,
              colors: [Colors.black, _hsv.withValue(1).toColor()],
              onChanged: (v) => _setFromSlider(_hsv.withValue(v)),
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
            widget.settings.setTransactionColor(widget.type, color);
            Navigator.of(context).pop();
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// Reusable color picker pop-up. Same hex box and Hue / Saturation /
/// Brightness sliders as the General Color picker, but for one color.
/// Pops the chosen [Color] when Apply is pressed (null when cancelled).
class ColorPickerDialog extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color initial;
  const ColorPickerDialog({
    super.key,
    required this.title,
    required this.icon,
    required this.initial,
  });

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexController = TextEditingController(text: _hex(widget.initial));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Color? _parseHex(String input) {
    var text = input.trim();
    if (text.startsWith('#')) text = text.substring(1);
    if (text.length != 6) return null;
    final value = int.tryParse(text, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  void _setHexText(Color c) {
    final text = _hex(c);
    _hexController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onHexChanged(String text) {
    final parsed = _parseHex(text);
    if (parsed == null) return;
    setState(() => _hsv = HSVColor.fromColor(parsed));
  }

  void _setFromSlider(HSVColor hsv) {
    setState(() => _hsv = hsv);
    _setHexText(hsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    final hexTextColor = AppTheme.onColor(color);
    final fg = AppTheme.accentOf(context).foreground;

    return _accentDialog(
      context,
      title: widget.title,
      icon: widget.icon,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  color: fg.withValues(alpha: AppConstants.borderAlpha),
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
                  LengthLimitingTextInputFormatter(AppConstants.hexInputLength),
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toUpperCase()),
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
              value: _hsv.hue,
              max: 360,
              colors: [
                for (var h = 0.0; h <= 360; h += AppConstants.hueGradientStep)
                  HSVColor.fromAHSV(1, h, 1, 1).toColor(),
              ],
              onChanged: (v) => _setFromSlider(_hsv.withHue(v)),
            ),
            _GradientSlider(
              label: 'Saturation',
              value: _hsv.saturation,
              max: 1,
              colors: [
                _hsv.withSaturation(0).toColor(),
                _hsv.withSaturation(1).toColor(),
              ],
              onChanged: (v) => _setFromSlider(_hsv.withSaturation(v)),
            ),
            _GradientSlider(
              label: 'Brightness',
              value: _hsv.value,
              max: 1,
              colors: [Colors.black, _hsv.withValue(1).toColor()],
              onChanged: (v) => _setFromSlider(_hsv.withValue(v)),
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
          onPressed: () => Navigator.of(context).pop(color),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// General Color pop-up (the original theme pop-up) with three parts:
///  - Main: background
///  - Accent: plain color for nav bar, drawer header, version box and
///    settings sections (does not affect buttons)
///  - Glyph: fonts, icons and buttons
/// Same design as the Categories pop-ups. It is drawn with the Accent color
/// being picked as its background and the Glyph color being picked as its
/// text and buttons, so those two update live. The Main color is shown in
/// the color box while the Main tab is selected.
class _GeneralColorDialog extends StatefulWidget {
  final Color initial;
  final AppSettings settings;
  const _GeneralColorDialog({required this.initial, required this.settings});

  @override
  State<_GeneralColorDialog> createState() => _GeneralColorDialogState();
}

class _GeneralColorDialogState extends State<_GeneralColorDialog> {
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
    _text = HSVColor.fromColor(s.textColor ?? AppTheme.onColor(widget.initial));
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
      AppTheme.fromColor(bgColor, accent: accentColor, text: glyphColor),
      widget.settings.fontFamily,
    );

    return _accentDialog(
      context,
      title: 'General Color',
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
                  color: glyphColor.withValues(alpha: AppConstants.borderAlpha),
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
                  LengthLimitingTextInputFormatter(AppConstants.hexInputLength),
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toUpperCase()),
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

/// Pop-up for animations:
///  - Animations (on/off switch)
///  - Animation speed (slider, greyed out while animations are off)
/// Changes apply live, so there is only a Close button.
class _AnimationConfigDialog extends StatelessWidget {
  final AppSettings settings;
  const _AnimationConfigDialog({required this.settings});

  @override
  Widget build(BuildContext context) {
    final maxIndex = AppConstants.animSpeedLabels.length - 1;

    return _accentDialog(
      context,
      title: 'Animation',
      icon: Icons.speed,
      content: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final theme = Theme.of(context);
          final fg = theme.colorScheme.onSurface;
          final fgSoft = theme.colorScheme.onSurfaceVariant;
          final enabled = settings.animEnabled;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Animations on / off ----
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.animation),
                  title: const Text('Animations'),
                  subtitle: Text(enabled ? 'On' : 'Off'),
                  value: enabled,
                  onChanged: settings.setAnimEnabled,
                ),
                Divider(
                  height: 1,
                  color: fg.withValues(alpha: AppConstants.dividerAlpha),
                ),
                // ---- Animation speed: text left, short slider right ----
                Opacity(
                  opacity: enabled ? 1 : 0.5,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppConstants.spaceSm,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.speed, color: fgSoft),
                        const SizedBox(width: AppConstants.spaceMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Animation speed',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: fg,
                                ),
                              ),
                              Text(
                                settings.animSpeedLabel,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: fgSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: AppConstants.fontSliderWidth,
                          child: Slider(
                            value: settings.animSpeedIndex.toDouble(),
                            min: 0,
                            max: maxIndex.toDouble(),
                            divisions: maxIndex,
                            label: settings.animSpeedLabel,
                            // null = disabled while animations are off
                            onChanged: enabled
                                ? (v) => settings.setAnimSpeedIndex(v.round())
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
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

// ------------------------------------------------------------------
// Notifications section
// ------------------------------------------------------------------

class _NotificationsSection extends StatefulWidget {
  final AppSettings settings;
  const _NotificationsSection({required this.settings});

  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection> {
  bool _busy = false;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _togglePush(bool on) async {
    setState(() => _busy = true);
    try {
      final ok = await widget.settings.setPush(on);
      if (!ok) {
        _say(
          'Notifications are blocked for Wallet. '
          'Allow them in your phone settings.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleReminders(bool on) async {
    if (on) await NotificationService.instance.requestExactAlarms();
    widget.settings.setNotif(NotificationOption.reminders, on);
  }

  Future<void> _test() async {
    if (!await NotificationService.instance.areEnabled()) {
      _say('Notifications are blocked. Allow them in your phone settings.');
      return;
    }
    await NotificationService.instance.showTest();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final master = s.notif(NotificationOption.push);

        Widget tile(
          IconData icon,
          String title,
          String subtitle,
          NotificationOption option,
          ValueChanged<bool>? onChanged,
        ) => SwitchListTile(
          secondary: Icon(icon),
          title: Text(title.tr),
          subtitle: Text(subtitle),
          value: s.notif(option),
          onChanged: onChanged,
        );

        return _SettingGroup(
          children: [
            tile(
              Icons.notifications_outlined,
              'Push notifications',
              'Allow Wallet to send alerts',
              NotificationOption.push,
              _busy ? null : _togglePush,
            ),
            tile(
              Icons.alarm,
              'Reminder alerts',
              'Notify me when a reminder is due',
              NotificationOption.reminders,
              master ? _toggleReminders : null,
            ),
            tile(
              Icons.account_balance_wallet_outlined,
              'Budget alerts',
              'Warn me at 80% and 100% of a budget',
              NotificationOption.budget,
              master ? (v) => s.setNotif(NotificationOption.budget, v) : null,
            ),
            tile(
              Icons.summarize_outlined,
              'Daily summary',
              'A short recap every evening at 8 PM',
              NotificationOption.summary,
              master ? (v) => s.setNotif(NotificationOption.summary, v) : null,
            ),
            tile(
              Icons.volume_up_outlined,
              'Sound',
              'Play a sound with alerts',
              NotificationOption.sound,
              master ? (v) => s.setNotif(NotificationOption.sound, v) : null,
            ),
            tile(
              Icons.vibration,
              'Vibration',
              'Vibrate with alerts',
              NotificationOption.vibration,
              master
                  ? (v) => s.setNotif(NotificationOption.vibration, v)
                  : null,
            ),
            if (master)
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Send a test notification'),
                onTap: _test,
              ),
          ],
        );
      },
    );
  }
}
