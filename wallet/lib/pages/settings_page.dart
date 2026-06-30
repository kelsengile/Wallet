import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show themeModeNotifier, setDarkMode;
import '../currency.dart';
import '../database/database_helper.dart';
import '../services/security_service.dart';
import 'trash_bin_page.dart';

/// Settings page — appearance, currency, notifications, etc.
/// Extend this file to add real preferences backed by the `settings` table
/// already present in [DatabaseHelper].
class SettingsPage extends StatefulWidget {
  /// Called after "Clear All Data" wipes the database — or after amounts are
  /// converted to a new currency — so the home page can refresh its cached
  /// state immediately.
  final VoidCallback? onDataCleared;

  /// Called after the user leaves the Trash Bin page so the home page can
  /// refresh accounts (e.g. a restored account should reappear).
  final VoidCallback? onAccountRestored;

  const SettingsPage({
    super.key,
    this.onDataCleared,
    this.onAccountRestored,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _trashCount = 0;

  // Whether changing the currency should also convert existing balances and
  // transaction amounts using a live exchange rate, instead of just
  // relabeling them.
  bool _convertOnCurrencyChange = false;
  bool _convertingCurrency = false;

  // ── App lock (Security section) ──────────────────────────────────────────
  bool _lockEnabled = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadTrashCount();
    _loadConvertPreference();
    _loadSecurityPreferences();
  }

  Future<void> _loadSecurityPreferences() async {
    final lockEnabled = await SecurityService.instance.isLockEnabled();
    final biometricEnabled =
        await SecurityService.instance.isBiometricEnabled();
    final biometricAvailable =
        await SecurityService.instance.isBiometricAvailable();
    if (mounted) {
      setState(() {
        _lockEnabled = lockEnabled;
        _biometricEnabled = biometricEnabled;
        _biometricAvailable = biometricAvailable;
      });
    }
  }

  Future<void> _loadConvertPreference() async {
    final value = await DatabaseHelper.instance.getConvertOnCurrencyChange();
    if (mounted) setState(() => _convertOnCurrencyChange = value);
  }

  Future<void> _loadTrashCount() async {
    final count = await DatabaseHelper.instance.getTrashCount();
    if (mounted) setState(() => _trashCount = count);
  }

  Future<void> _handleCurrencySelected(String newCode, String oldCode) async {
    if (newCode == oldCode || _convertingCurrency) return;

    if (!_convertOnCurrencyChange) {
      setCurrency(newCode);
      return;
    }

    setState(() => _convertingCurrency = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/$oldCode'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw Exception('Server returned ${res.statusCode}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['result'] != 'success') {
        throw Exception('API reported failure');
      }
      final rates = data['rates'] as Map<String, dynamic>;
      final rateValue = rates[newCode];
      if (rateValue == null) {
        throw Exception('No rate available for $newCode');
      }
      final rate = (rateValue as num).toDouble();

      await DatabaseHelper.instance.convertAllAmounts(rate);
      setCurrency(newCode);
      widget.onDataCleared?.call();

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Converted all balances from $oldCode to $newCode.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't fetch exchange rates — currency wasn't changed.",
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _convertingCurrency = false);
    }
  }

  /// Flips the master "App Lock" switch. Turning it on always requires a
  /// 6-digit PIN to be set first (PIN is the durable fallback so the user
  /// can never be locked out by failed/missing biometrics); biometrics are
  /// then offered as an optional, faster unlock method on top of it.
  Future<void> _handleLockToggle(bool enable) async {
    if (!enable) {
      final confirmed = await _confirmDisableLock();
      if (!confirmed) return;
      await SecurityService.instance.disableLock();
      await SecurityService.instance.clearPin();
      if (mounted) {
        setState(() {
          _lockEnabled = false;
          _biometricEnabled = false;
        });
      }
      return;
    }

    final pin = await _promptSetPin();
    if (pin == null) return; // user cancelled

    bool useBiometrics = false;
    if (_biometricAvailable) {
      useBiometrics = await _promptUseBiometrics();
    }

    await SecurityService.instance.setPin(pin);
    await SecurityService.instance.enableLock(useBiometrics: useBiometrics);
    if (mounted) {
      setState(() {
        _lockEnabled = true;
        _biometricEnabled = useBiometrics;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App Lock enabled.')),
      );
    }
  }

  Future<bool> _confirmDisableLock() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn Off App Lock?'),
        content: const Text(
          'Your PIN will be removed and the app will no longer require '
          'authentication to open.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn Off'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _promptUseBiometrics() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.fingerprint, size: 32),
        title: const Text('Use Biometrics?'),
        content: const Text(
          'You can also unlock with your fingerprint or face instead of '
          'typing your PIN every time. Your PIN will still work as a '
          'fallback.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('PIN Only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Two-step PIN entry (enter, then confirm) inside a single dialog.
  /// Returns the chosen PIN, or null if the user backed out.
  Future<String?> _promptSetPin() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _SetPinDialog(),
    );
  }

  Future<void> _handleChangePin() async {
    final pin = await _promptSetPin();
    if (pin == null) return;
    await SecurityService.instance.setPin(pin);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN updated.')),
      );
    }
  }

  Future<void> _handleBiometricToggle(bool enable) async {
    if (enable && !_biometricAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No biometrics are enrolled on this device. Add a fingerprint '
            'or face in your device settings first.',
          ),
        ),
      );
      return;
    }
    if (enable) {
      final ok = await SecurityService.instance.authenticateWithBiometrics(
        reason: 'Confirm to enable biometric unlock',
      );
      if (!ok) return;
    }
    await SecurityService.instance.setBiometricEnabled(enable);
    if (mounted) setState(() => _biometricEnabled = enable);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // In dark mode, swap the indigo "primary" accent for plain white so
    // section labels and active switches don't read as blue-on-dark.
    final accentColor = isDark ? Colors.white : theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Appearance ────────────────────────────────────────────────────
          _Section(label: 'Appearance', color: accentColor),
          Card(
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeNotifier,
              builder: (context, mode, _) {
                return SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Dark Mode'),
                  subtitle: const Text('Switch to a darker theme'),
                  value: mode == ThemeMode.dark,
                  activeColor: accentColor,
                  onChanged: (v) => setDarkMode(v),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // ── Localisation ──────────────────────────────────────────────────
          _Section(label: 'Localisation', color: accentColor),
          Card(
            child: Column(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: currencyCodeNotifier,
                  builder: (context, code, _) {
                    return ListTile(
                      leading: const Icon(Icons.attach_money_outlined),
                      title: const Text('Currency'),
                      trailing: _convertingCurrency
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : _CurrencyPickerButton(
                              currentCode: code,
                              accentColor: accentColor,
                              onSelected: (v) =>
                                  _handleCurrencySelected(v, code),
                            ),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.sync_alt_outlined),
                  title: const Text('Convert Amounts on Change'),
                  subtitle: const Text(
                    'Recalculate balances using live exchange rates when you switch currency',
                  ),
                  value: _convertOnCurrencyChange,
                  activeColor: accentColor,
                  onChanged: (v) {
                    setState(() => _convertOnCurrencyChange = v);
                    DatabaseHelper.instance.saveConvertOnCurrencyChange(v);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Security ──────────────────────────────────────────────────────
          _Section(label: 'Security', color: accentColor),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.lock_outline),
                  title: const Text('App Lock'),
                  subtitle: Text(
                    _lockEnabled
                        ? 'Require authentication to open the app'
                        : 'Protect the app with a PIN or biometrics',
                  ),
                  value: _lockEnabled,
                  activeColor: accentColor,
                  onChanged: _handleLockToggle,
                ),
                if (_lockEnabled) ...[
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('Use Biometrics'),
                    subtitle: Text(
                      _biometricAvailable
                          ? 'Unlock with fingerprint or face'
                          : 'No biometrics enrolled on this device',
                    ),
                    value: _biometricEnabled,
                    activeColor: accentColor,
                    onChanged: _handleBiometricToggle,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.pin_outlined),
                    title: const Text('Change PIN'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _handleChangePin,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Storage ───────────────────────────────────────────────────────
          _Section(label: 'Storage', color: accentColor),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('Database'),
                  subtitle: const Text('SQLite — stored on device'),
                  trailing:
                      Icon(Icons.check_circle, color: Colors.green.shade600),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.delete_outline, color: Colors.red),
                      if (_trashCount > 0)
                        Positioned(
                          top: -4,
                          right: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _trashCount > 99 ? '99+' : '$_trashCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: const Text('Trash Bin',
                      style: TextStyle(color: Colors.red)),
                  subtitle: const Text('View and restore deleted items'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.red),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TrashBinPage()),
                    ).then((_) {
                      _loadTrashCount();
                      widget.onAccountRestored?.call();
                    });
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined,
                      color: Colors.red),
                  title: const Text('Clear All Data',
                      style: TextStyle(color: Colors.red)),
                  subtitle: const Text('Permanently delete everything'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.red),
                  onTap: () => _showClearDataDialog(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'Wallet App v1.0.0',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showClearDataDialog(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    bool isDeleting = false;

    showDialog(
      context: context,
      barrierDismissible: !isDeleting,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            icon: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_rounded,
                color: Colors.red,
                size: 32,
              ),
            ),
            title: const Text(
              'Clear All Data?',
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This will permanently delete all accounts, transactions, and trash. This action cannot be undone.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  disabledBackgroundColor: Colors.red.withValues(alpha: 0.5),
                ),
                onPressed: isDeleting
                    ? null
                    : () async {
                        setDialogState(() => isDeleting = true);
                        await DatabaseHelper.instance.clearAllData();
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('All data cleared.'),
                            ),
                          );
                        }
                        _loadTrashCount();
                        widget.onDataCleared?.call();
                      },
                icon: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_forever, size: 18),
                label: Text(isDeleting ? 'Clearing…' : 'Clear Everything'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final Color color;
  const _Section({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// Button that shows the current currency code/symbol and, when tapped,
/// opens a small popup anchored just below it containing every supported
/// currency laid out in a 3-column grid. The grid's height grows with the
/// number of currencies (capped, after which it scrolls).
class _CurrencyPickerButton extends StatefulWidget {
  final String currentCode;
  final Color accentColor;
  final ValueChanged<String> onSelected;

  const _CurrencyPickerButton({
    required this.currentCode,
    required this.accentColor,
    required this.onSelected,
  });

  @override
  State<_CurrencyPickerButton> createState() => _CurrencyPickerButtonState();
}

class _CurrencyPickerButtonState extends State<_CurrencyPickerButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _open = false;

  static const int _columns = 3;
  static const double _cellWidth = 92;
  static const double _cellHeight = 64;
  static const double _maxPopupHeight = 320;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (_open && mounted) setState(() => _open = false);
  }

  void _showOverlay() {
    final renderBox = context.findRenderObject() as RenderBox;
    final buttonWidth = renderBox.size.width;
    final screenWidth = MediaQuery.of(context).size.width;

    final codes = kCurrencySymbols.keys.toList();
    final rows = (codes.length / _columns).ceil();
    final popupWidth =
        (_cellWidth * _columns).clamp(0, screenWidth - 16).toDouble();
    final contentHeight = rows * _cellHeight;
    final popupHeight = contentHeight.clamp(_cellHeight, _maxPopupHeight);

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            // Tapping outside the popup closes it.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(buttonWidth - popupWidth, 44),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: SizedBox(
                    width: popupWidth,
                    height: popupHeight,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(6),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _columns,
                        childAspectRatio: _cellWidth / _cellHeight,
                      ),
                      itemCount: codes.length,
                      itemBuilder: (context, index) {
                        final code = codes[index];
                        final isSelected = code == widget.currentCode;
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            _removeOverlay();
                            widget.onSelected(code);
                          },
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? widget.accentColor.withValues(alpha: 0.15)
                                  : null,
                              borderRadius: BorderRadius.circular(8),
                              border: isSelected
                                  ? Border.all(color: widget.accentColor)
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  kCurrencySymbols[code]!,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        isSelected ? widget.accentColor : null,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  code,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color:
                                        isSelected ? widget.accentColor : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.currentCode} (${kCurrencySymbols[widget.currentCode]})',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 4),
              Icon(
                _open ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: widget.accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-step "enter PIN, then confirm" dialog used both for initial setup
/// (when turning App Lock on) and for changing an existing PIN later.
class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog();

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  String? _firstPin;
  final List<int> _entered = [];
  String? _error;

  bool get _isConfirmStep => _firstPin != null;

  void _onDigit(int d) {
    if (_entered.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered.add(d);
      _error = null;
    });
    if (_entered.length == 6) _onComplete();
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered.removeLast());
  }

  void _onComplete() {
    final pin = _entered.join();
    if (!_isConfirmStep) {
      setState(() {
        _firstPin = pin;
        _entered.clear();
      });
      return;
    }

    if (pin == _firstPin) {
      Navigator.pop(context, pin);
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = "PINs didn't match — try again";
        _firstPin = null;
        _entered.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isConfirmStep ? 'Confirm PIN' : 'Set a 6-Digit PIN'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _entered.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            _DialogKeypad(onDigit: _onDigit, onBackspace: _onBackspace),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _DialogKeypad extends StatelessWidget {
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;

  const _DialogKeypad({required this.onDigit, required this.onBackspace});

  Widget _key(BuildContext context,
      {String? label, Widget? icon, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1.6,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(
            child: icon ?? Text(label ?? '', style: theme.textTheme.titleLarge),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <List<Widget>>[
      [
        _key(context, label: '1', onTap: () => onDigit(1)),
        _key(context, label: '2', onTap: () => onDigit(2)),
        _key(context, label: '3', onTap: () => onDigit(3)),
      ],
      [
        _key(context, label: '4', onTap: () => onDigit(4)),
        _key(context, label: '5', onTap: () => onDigit(5)),
        _key(context, label: '6', onTap: () => onDigit(6)),
      ],
      [
        _key(context, label: '7', onTap: () => onDigit(7)),
        _key(context, label: '8', onTap: () => onDigit(8)),
        _key(context, label: '9', onTap: () => onDigit(9)),
      ],
      [
        _key(context),
        _key(context, label: '0', onTap: () => onDigit(0)),
        _key(
          context,
          icon: const Icon(Icons.backspace_outlined, size: 20),
          onTap: onBackspace,
        ),
      ],
    ];
    return Column(children: rows.map((r) => Row(children: r)).toList());
  }
}
