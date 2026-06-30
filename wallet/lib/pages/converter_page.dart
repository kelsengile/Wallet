import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_squircle_button.dart';

/// Currency converter with live exchange rates and a built-in numeric keypad
/// (instead of the system keyboard).
///
/// Requires the `http` package — add this to pubspec.yaml:
///   dependencies:
///     http: ^1.2.0
///
/// Rates are fetched from https://open.er-api.com (free, no API key,
/// updates roughly once a day). If the request fails (e.g. no internet),
/// the page falls back to the last cached rates for the session and shows
/// an error banner with a retry button.
class ConverterPage extends StatefulWidget {
  const ConverterPage({super.key});

  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

enum _ActiveField { from, to }

class _ConverterPageState extends State<ConverterPage> {
  static const Map<String, String> _symbols = {
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'PHP': '₱',
    'AUD': 'A\$',
    'CAD': 'C\$',
    'CHF': 'Fr',
    'CNY': '¥',
    'INR': '₹',
    'SGD': 'S\$',
    'KRW': '₩',
  };

  Map<String, double>? _ratesUsd;
  DateTime? _fetchedAt;
  bool _loading = true;
  String? _error;

  String _from = 'USD';
  String _to = 'PHP';

  // Which field the keypad is currently typing into.
  _ActiveField _active = _ActiveField.from;
  String _fromText = '1';
  String _toText = '';

  @override
  void initState() {
    super.initState();
    _fetchRates();
  }

  Future<void> _fetchRates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .get(Uri.parse('https://open.er-api.com/v6/latest/USD'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw Exception('Server returned ${res.statusCode}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['result'] != 'success') {
        throw Exception('API reported failure');
      }
      final rawRates = (data['rates'] as Map<String, dynamic>);
      final rates = <String, double>{};
      for (final code in _symbols.keys) {
        final v = rawRates[code];
        if (v != null) rates[code] = (v as num).toDouble();
      }
      setState(() {
        _ratesUsd = rates;
        _fetchedAt = DateTime.now();
        _loading = false;
        _recalcOtherField();
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = _ratesUsd == null
            ? 'Couldn\'t load exchange rates. Check your connection.'
            : 'Couldn\'t refresh rates — showing last known values.';
      });
    }
  }

  double get _rateFromTo {
    final rates = _ratesUsd;
    if (rates == null) return 0;
    return (rates[_to] ?? 1) / (rates[_from] ?? 1);
  }

  double get _rateToFrom {
    final rates = _ratesUsd;
    if (rates == null) return 0;
    return (rates[_from] ?? 1) / (rates[_to] ?? 1);
  }

  void _swap() {
    setState(() {
      final tmpCode = _from;
      _from = _to;
      _to = tmpCode;
      final tmpText = _fromText;
      _fromText = _toText;
      _toText = tmpText;
      _active =
          _active == _ActiveField.from ? _ActiveField.to : _ActiveField.from;
    });
  }

  /// Recomputes the *other* field whenever the active field's text or the
  /// currency pair/rates change.
  void _recalcOtherField() {
    if (_ratesUsd == null) return;
    if (_active == _ActiveField.from) {
      final amount = double.tryParse(_fromText) ?? 0;
      final result = amount * _rateFromTo;
      _toText = amount == 0 ? '' : _formatResult(result);
    } else {
      final amount = double.tryParse(_toText) ?? 0;
      final result = amount * _rateToFrom;
      _fromText = amount == 0 ? '' : _formatResult(result);
    }
  }

  String _formatResult(double v) {
    // Trim trailing zeros but keep up to 2 decimal places.
    var s = v.toStringAsFixed(2);
    return s;
  }

  // ── Keypad input handling ─────────────────────────────────────────────
  void _onKeyTap(String key) {
    setState(() {
      final current = _active == _ActiveField.from ? _fromText : _toText;
      String updated = current;

      if (key == '⌫') {
        if (updated.isNotEmpty) {
          updated = updated.substring(0, updated.length - 1);
        }
      } else if (key == '.') {
        if (!updated.contains('.')) {
          updated = updated.isEmpty ? '0.' : '$updated.';
        }
      } else {
        // Digit
        if (updated == '0') {
          updated = key;
        } else {
          final dot = updated.indexOf('.');
          final overTwoDecimals = dot != -1 && updated.length - dot > 2;
          final tooLong = updated.length > 12;
          if (!overTwoDecimals && !tooLong) {
            updated += key;
          }
        }
      }

      if (_active == _ActiveField.from) {
        _fromText = updated;
      } else {
        _toText = updated;
      }
      _recalcOtherField();
    });
  }

  void _selectField(_ActiveField field) {
    if (_active == field) return;
    setState(() => _active = field);
  }

  // ── Number formatting for display (thousands separators) ─────────────
  String _formatDisplay(String raw) {
    if (raw.isEmpty) return '0';
    final parts = raw.split('.');
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';
    final formatted = intPart.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '$formatted$decPart';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          // ── Header — shared style with the calculator ───────────────
          AppPageHeader(
            title: 'Currency Converter',
            topPadding: topPad,
            leadingIcon: Icons.arrow_back_rounded,
            leadingTooltip: 'Back',
            onLeadingTap: () => Navigator.of(context).pop(),
            trailing: IconButton(
              icon: _loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  : Icon(Icons.refresh, color: cs.onSurface),
              onPressed: _loading ? null : _fetchRates,
              tooltip: 'Refresh rates',
            ),
          ),

          // ── Display area ─────────────────────────────────────────────
          Expanded(
            child: Container(
              width: double.infinity,
              color: cs.surfaceContainer,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: cs.onErrorContainer, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: cs.onErrorContainer),
                              ),
                            ),
                            TextButton(
                              onPressed: _fetchRates,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),

                    // ── From currency (editable) ───────────────────────
                    _AmountCard(
                      label: 'From',
                      amountText: _formatDisplay(_fromText),
                      currency: _from,
                      currencies: _symbols.keys.toList(),
                      active: _active == _ActiveField.from,
                      onTapField: () => _selectField(_ActiveField.from),
                      onCurrencyChanged: (v) => setState(() {
                        _from = v;
                        _recalcOtherField();
                      }),
                    ),

                    // ── Swap button ─────────────────────────────────────
                    SizedBox(
                      height: 52,
                      child: Center(
                        child: AppSquircleButton(
                          width: 44,
                          height: 44,
                          bgColor: cs.primaryContainer,
                          onTap: _swap,
                          child: Icon(Icons.swap_vert,
                              color: cs.onPrimaryContainer, size: 22),
                        ),
                      ),
                    ),

                    // ── To currency (editable) ─────────────────────────
                    _AmountCard(
                      label: 'To',
                      amountText: _formatDisplay(_toText),
                      currency: _to,
                      currencies: _symbols.keys.toList(),
                      active: _active == _ActiveField.to,
                      onTapField: () => _selectField(_ActiveField.to),
                      onCurrencyChanged: (v) => setState(() {
                        _to = v;
                        _recalcOtherField();
                      }),
                    ),

                    const SizedBox(height: 18),

                    Center(
                      child: Text(
                        _ratesUsd == null
                            ? 'Loading rate…'
                            : '1 $_from = ${_rateFromTo.toStringAsFixed(4)} $_to',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        _fetchedAt == null
                            ? ''
                            : 'Updated ${_formatTime(_fetchedAt!)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.outline),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── On-screen numeric keypad — shared squircle buttons ───────
          Container(
            color: cs.surfaceContainer,
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 16),
            child: _Keypad(scheme: cs, onKeyTap: _onKeyTap),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Keypad — same squircle button + layout language as the calculator ────

class _Keypad extends StatelessWidget {
  final ColorScheme scheme;
  final ValueChanged<String> onKeyTap;
  const _Keypad({required this.scheme, required this.onKeyTap});

  static const _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    const gap = 10.0;

    return LayoutBuilder(builder: (context, constraints) {
      final btnSize = (constraints.maxWidth - gap * 2) / 3;
      final btnHeight = btnSize * 0.62;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: _keys.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(
              children: row.map((key) {
                final isBackspace = key == '⌫';
                return Padding(
                  padding: EdgeInsets.only(right: key == row.last ? 0 : gap),
                  child: AppSquircleButton(
                    width: btnSize,
                    height: btnHeight,
                    bgColor: isBackspace
                        ? scheme.secondaryContainer
                        : scheme.surfaceContainerHigh,
                    onTap: () => onKeyTap(key),
                    child: isBackspace
                        ? Icon(
                            Icons.backspace_outlined,
                            color: scheme.onSecondaryContainer,
                            size: btnHeight * 0.34,
                          )
                        : Text(
                            key,
                            style: TextStyle(
                              fontSize: btnHeight * 0.4,
                              fontWeight: FontWeight.w400,
                              color: scheme.onSurface,
                            ),
                          ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      );
    });
  }
}

// ── Amount card — styled like the calculator's display: large light
// numerals on a flat surface, with an inline currency picker. ────────────

class _AmountCard extends StatelessWidget {
  final String label;
  final String amountText;
  final String currency;
  final List<String> currencies;
  final bool active;
  final VoidCallback onTapField;
  final ValueChanged<String> onCurrencyChanged;

  const _AmountCard({
    required this.label,
    required this.amountText,
    required this.currency,
    required this.currencies,
    required this.active,
    required this.onTapField,
    required this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: active
            ? cs.surfaceContainerHigh
            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTapField,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active
                    ? cs.primary.withValues(alpha: 0.55)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        amountText,
                        style: const TextStyle(
                          fontWeight: FontWeight.w300,
                          letterSpacing: -1,
                        ).copyWith(
                          fontSize: 38,
                          color: cs.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CurrencyDropdown(
                      value: currency,
                      currencies: currencies,
                      onChanged: onCurrencyChanged,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrencyDropdown extends StatelessWidget {
  final String value;
  final List<String> currencies;
  final ValueChanged<String> onChanged;

  const _CurrencyDropdown({
    required this.value,
    required this.currencies,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => currencies
          .map((c) => PopupMenuItem(value: c, child: Text(c)))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, color: cs.onPrimaryContainer),
          ],
        ),
      ),
    );
  }
}
