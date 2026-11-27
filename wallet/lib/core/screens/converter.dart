import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../features/finance.dart' show showAppDatePicker;
import '../../services/exchange.dart';
import '../constants.dart';
import '../themes.dart';
import '../utils.dart';

// ------------------------------------------------------------------
// Shared helpers
// ------------------------------------------------------------------

const List<String> _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

AppBar _appBar(String title, IconData icon) => AppBar(
  title: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon),
      const SizedBox(width: AppConstants.spaceSm),
      Text(title.tr),
    ],
  ),
);

/// Number -> short readable text (no thousands separators).
String _fmtNum(double v) {
  if (v.isNaN || v.isInfinite || v == 0) return '0';
  final a = v.abs();
  if (a >= 1e15 || a < 1e-9) {
    return v.toStringAsExponential(6).replaceFirst(RegExp(r'\.?0+e'), 'e');
  }
  final mag = (math.log(a) / math.ln10).floor();
  final dec = (9 - mag).clamp(0, 12);
  var s = v.toStringAsFixed(dec);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s == '-0' ? '0' : s;
}

String _groupInt(String s, int n, String sep) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % n == 0) out.write(sep);
    out.write(s[i]);
  }
  return out.toString();
}

/// "1234567.5" -> "1,234,567.5" (keeps a typed trailing dot).
String _groupDec(String s) {
  if (s.contains('e')) return s;
  final neg = s.startsWith('-');
  final body = neg ? s.substring(1) : s;
  final parts = body.split('.');
  final whole = _groupInt(parts[0], 3, ',');
  return '${neg ? '-' : ''}$whole${body.contains('.') ? '.${parts.length > 1 ? parts[1] : ''}' : ''}';
}

String _plural(int n, String w) => '$n $w${n == 1 ? '' : 's'}';

List<Widget> _spaced(List<Widget> items, [double gap = 12]) => [
  for (var i = 0; i < items.length; i++) ...[
    if (i > 0) SizedBox(height: gap),
    items[i],
  ],
];

Widget _chips(
  List<String> labels,
  int selected,
  ValueChanged<int> onSelect,
  Color fg,
) {
  return Wrap(
    spacing: AppConstants.spaceSm,
    runSpacing: AppConstants.spaceSm,
    children: [
      for (var i = 0; i < labels.length; i++)
        Material(
          color: fg.withValues(
            alpha: i == selected
                ? AppConstants.iconTileSelectedAlpha
                : AppConstants.tintAlpha,
          ),
          shape: StadiumBorder(
            side: i == selected
                ? BorderSide(color: fg, width: 1.5)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelect(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceMd,
                vertical: AppConstants.spaceSm + 2,
              ),
              child: Text(
                labels[i].tr,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

Widget _resultCard(
  Color fg,
  Color bg, {
  required String label,
  required String value,
  List<(String, String)> rows = const [],
  Color? valueColor,
}) {
  final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
  return Container(
    padding: const EdgeInsets.all(AppConstants.spaceMd),
    decoration: BoxDecoration(
      color: Color.alphaBlend(fg.withValues(alpha: 0.10), bg),
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      border: Border.all(color: fg.withValues(alpha: AppConstants.dividerAlpha)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.tr, style: TextStyle(fontSize: 13, color: muted)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: valueColor ?? fg,
            ),
          ),
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: AppConstants.spaceSm),
          Divider(
            height: 1,
            color: fg.withValues(alpha: AppConstants.dividerAlpha),
          ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(top: AppConstants.spaceSm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.$1.tr,
                      style: TextStyle(fontSize: 14, color: muted),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  Flexible(
                    child: Text(
                      r.$2,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

// ------------------------------------------------------------------
// Shared pieces of the form screens (Finance, Date, Discount, BMI).
// They look and behave like the Currency screen: oblong panels, tap one
// to make it active, type on the built-in keypad.
// ------------------------------------------------------------------

class _Inputs {
  _Inputs(this.active);
  String active;
  final Map<String, String> _t = {};

  String text(String k) => _t[k] ?? '';
  double n(String k) => double.tryParse(text(k)) ?? 0;

  void handle(String k, List<String> order) {
    if (order.isEmpty) return;
    if (k == 'next' || k == 'prev') {
      final i = order.indexOf(active);
      final step = k == 'next' ? 1 : -1;
      active = order[((i < 0 ? 0 : i) + step + order.length) % order.length];
      return;
    }
    var t = text(active);
    switch (k) {
      case 'del':
        t = t.isEmpty ? '' : t.substring(0, t.length - 1);
      case 'clr':
        t = '';
      case '.':
        if (t.contains('.')) return;
        t = t.isEmpty ? '0.' : '$t.';
      default:
        if (t.length >= 12) return;
        if (t.contains('.') && t.split('.')[1].length >= 6) return;
        t = t == '0' ? k : t + k;
    }
    _t[active] = t;
  }
}

/// Oblong number panel (same design as the Currency panels).
Widget _inField(
  _Inputs c,
  String key,
  String label,
  String unit,
  Color fg,
  Color bg,
  VoidCallback refresh,
) {
  final active = c.active == key;
  final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
  final t = c.text(key);
  return Material(
    color: bg,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      side: BorderSide(color: active ? fg : Colors.transparent, width: 2),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () {
        c.active = key;
        refresh();
      },
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      unit,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                  ),
                  Text(
                    label.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    _groupDec(t.isEmpty ? '0' : t),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: active ? fg : fg.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Oblong date panel. Opens the same calendar pop-up as Finance.
Widget _datePanel(
  BuildContext context,
  String label,
  DateTime d,
  ValueChanged<DateTime> onPick,
  Color fg,
  Color bg,
) {
  final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
  final text =
      '${_weekdays[d.weekday - 1].substring(0, 3)}, ${Utils.formatDate(d)}';
  return Material(
    color: bg,
    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () async {
        final p = await showAppDatePicker(context, initial: d, color: fg);
        if (p != null) onPick(DateTime(p.year, p.month, p.day));
      },
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.calendar_today_outlined, color: fg, size: 22),
                  Text(
                    label.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    text,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Page with the panels on top (scrolls) and the keypad fixed at the bottom.
class _KeyedPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final ValueChanged<String> onKey;
  final bool showKeypad;
  final bool Function(String key)? enabled;
  const _KeyedPage({
    required this.title,
    required this.icon,
    required this.children,
    required this.onKey,
    this.showKeypad = true,
    this.enabled,
  });

  static const _rows = [
    ['7', '8', '9', 'del'],
    ['4', '5', '6', 'clr'],
    ['1', '2', '3', 'prev'],
    ['0', '.', 'next'],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(title, icon),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMd),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: AppConstants.spaceSm),
                      ..._spaced(children, AppConstants.spaceSm),
                      const SizedBox(height: AppConstants.spaceSm),
                    ],
                  ),
                ),
              ),
              if (showKeypad)
                _ConvKeypad(rows: _rows, onKey: onKey, enabled: enabled),
              const SizedBox(height: AppConstants.spaceSm),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Converter home: grid of categories
// ------------------------------------------------------------------

class _Category {
  final String label;
  final IconData icon;
  final Widget Function() build;
  const _Category(this.label, this.icon, this.build);
}

List<_Category> _categories() => [
  _Category(
    'Currency',
    Icons.currency_exchange,
    () => _UnitScreen(set: _currencySet()),
  ),
  _Category('Finance', Icons.paid_outlined, () => const _FinanceScreen()),
  _Category('Data', Icons.sd_storage_outlined, () => _UnitScreen(set: _dataSet)),
  _Category('Date', Icons.event_outlined, () => const _DateScreen()),
  _Category('Discount', Icons.sell_outlined, () => const _DiscountScreen()),
  _Category(
    'Volume',
    Icons.local_drink_outlined,
    () => _UnitScreen(set: _volumeSet),
  ),
  _Category('Speed', Icons.speed, () => _UnitScreen(set: _speedSet)),
  _Category('Length', Icons.straighten, () => _UnitScreen(set: _lengthSet)),
  _Category('Mass', Icons.scale_outlined, () => _UnitScreen(set: _massSet)),
  _Category('Area', Icons.square_foot, () => _UnitScreen(set: _areaSet)),
  _Category('Time', Icons.schedule, () => _UnitScreen(set: _timeSet)),
  _Category(
    'Temperature',
    Icons.thermostat,
    () => _UnitScreen(set: _temperatureSet),
  ),
  _Category('Numeral system', Icons.numbers, () => const _NumeralScreen()),
  _Category('BMI', Icons.monitor_weight_outlined, () => const _BmiScreen()),
];

class ConverterScreen extends StatelessWidget {
  const ConverterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final cats = _categories();

    return Scaffold(
      appBar: _appBar('Converter', Icons.compare_arrows_outlined),
      body: GridView.builder(
        padding: const EdgeInsets.all(AppConstants.spaceMd),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: AppConstants.spaceSmMd,
          crossAxisSpacing: AppConstants.spaceSmMd,
          childAspectRatio: 0.92,
        ),
        itemCount: cats.length,
        itemBuilder: (context, i) {
          final c = cats[i];
          return Material(
            color: accent.background,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => c.build())),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spaceSm),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: fg.withValues(alpha: AppConstants.tintAlpha),
                      ),
                      child: Icon(c.icon, color: fg, size: 24),
                    ),
                    const SizedBox(height: AppConstants.spaceSm),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        c.label.tr,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------
// Unit data
// ------------------------------------------------------------------

class _Unit {
  final String name;
  final String symbol;
  final double Function(double) toBase;
  final double Function(double) fromBase;
  const _Unit(this.name, this.symbol, this.toBase, this.fromBase);

  /// [factor] = how many base units are in 1 of this unit.
  factory _Unit.lin(String name, String symbol, double factor) =>
      _Unit(name, symbol, (v) => v * factor, (v) => v / factor);
}

class _UnitSet {
  final String label;
  final IconData icon;
  final List<_Unit> units;
  final int from;
  final int to;
  final bool negative;
  final bool live;
  const _UnitSet(
    this.label,
    this.icon,
    this.units,
    this.from,
    this.to, {
    this.negative = false,
    this.live = false,
  });
}

_UnitSet _currencySet() {
  double perUsd(AppCurrency c) =>
      ExchangeRates.instance.rate('USD', c.code) ?? c.perUsd;
  final units = [
    for (final c in AppConstants.currencies)
      _Unit(c.name, c.code, (v) => v / perUsd(c), (v) => v * perUsd(c)),
  ];
  var from = AppConstants.currencies.indexWhere(
    (c) => c.symbol == AppConstants.currencySymbol,
  );
  if (from < 0) from = 0;
  return _UnitSet(
    'Currency',
    Icons.currency_exchange,
    units,
    from,
    from == 0 ? 4 : 0,
    live: true,
  );
}

final _dataSet = _UnitSet('Data', Icons.sd_storage_outlined, [
  _Unit.lin('Bit', 'bit', 0.125),
  _Unit.lin('Byte', 'B', 1),
  _Unit.lin('Kilobyte', 'KB', 1e3),
  _Unit.lin('Megabyte', 'MB', 1e6),
  _Unit.lin('Gigabyte', 'GB', 1e9),
  _Unit.lin('Terabyte', 'TB', 1e12),
  _Unit.lin('Petabyte', 'PB', 1e15),
  _Unit.lin('Kibibyte', 'KiB', 1024),
  _Unit.lin('Mebibyte', 'MiB', 1048576),
  _Unit.lin('Gibibyte', 'GiB', 1073741824),
  _Unit.lin('Tebibyte', 'TiB', 1099511627776),
], 4, 3);

final _volumeSet = _UnitSet('Volume', Icons.local_drink_outlined, [
  _Unit.lin('Milliliter', 'mL', 0.001),
  _Unit.lin('Liter', 'L', 1),
  _Unit.lin('Cubic centimeter', 'cm³', 0.001),
  _Unit.lin('Cubic meter', 'm³', 1000),
  _Unit.lin('Teaspoon (US)', 'tsp', 0.00492892159375),
  _Unit.lin('Tablespoon (US)', 'tbsp', 0.01478676478125),
  _Unit.lin('Fluid ounce (US)', 'fl oz', 0.0295735295625),
  _Unit.lin('Cup (US)', 'cup', 0.2365882365),
  _Unit.lin('Pint (US)', 'pt', 0.473176473),
  _Unit.lin('Quart (US)', 'qt', 0.946352946),
  _Unit.lin('Gallon (US)', 'gal', 3.785411784),
], 1, 7);

final _speedSet = _UnitSet('Speed', Icons.speed, [
  _Unit.lin('Meter per second', 'm/s', 1),
  _Unit.lin('Kilometer per hour', 'km/h', 1 / 3.6),
  _Unit.lin('Mile per hour', 'mph', 0.44704),
  _Unit.lin('Knot', 'kn', 1852 / 3600),
  _Unit.lin('Foot per second', 'ft/s', 0.3048),
  _Unit.lin('Mach', 'Ma', 340.29),
], 1, 2);

final _lengthSet = _UnitSet('Length', Icons.straighten, [
  _Unit.lin('Millimeter', 'mm', 0.001),
  _Unit.lin('Centimeter', 'cm', 0.01),
  _Unit.lin('Meter', 'm', 1),
  _Unit.lin('Kilometer', 'km', 1000),
  _Unit.lin('Inch', 'in', 0.0254),
  _Unit.lin('Foot', 'ft', 0.3048),
  _Unit.lin('Yard', 'yd', 0.9144),
  _Unit.lin('Mile', 'mi', 1609.344),
  _Unit.lin('Nautical mile', 'nmi', 1852),
], 2, 5);

final _massSet = _UnitSet('Mass', Icons.scale_outlined, [
  _Unit.lin('Milligram', 'mg', 1e-6),
  _Unit.lin('Gram', 'g', 0.001),
  _Unit.lin('Kilogram', 'kg', 1),
  _Unit.lin('Metric ton', 't', 1000),
  _Unit.lin('Ounce', 'oz', 0.028349523125),
  _Unit.lin('Pound', 'lb', 0.45359237),
  _Unit.lin('Stone', 'st', 6.35029318),
  _Unit.lin('Carat', 'ct', 0.0002),
], 2, 5);

final _areaSet = _UnitSet('Area', Icons.square_foot, [
  _Unit.lin('Square millimeter', 'mm²', 1e-6),
  _Unit.lin('Square centimeter', 'cm²', 1e-4),
  _Unit.lin('Square meter', 'm²', 1),
  _Unit.lin('Hectare', 'ha', 10000),
  _Unit.lin('Square kilometer', 'km²', 1e6),
  _Unit.lin('Square inch', 'in²', 0.00064516),
  _Unit.lin('Square foot', 'ft²', 0.09290304),
  _Unit.lin('Square yard', 'yd²', 0.83612736),
  _Unit.lin('Acre', 'ac', 4046.8564224),
  _Unit.lin('Square mile', 'mi²', 2589988.110336),
], 2, 6);

final _timeSet = _UnitSet('Time', Icons.schedule, [
  _Unit.lin('Millisecond', 'ms', 0.001),
  _Unit.lin('Second', 's', 1),
  _Unit.lin('Minute', 'min', 60),
  _Unit.lin('Hour', 'h', 3600),
  _Unit.lin('Day', 'd', 86400),
  _Unit.lin('Week', 'wk', 604800),
  _Unit.lin('Month (30.44 d)', 'mo', 2629800),
  _Unit.lin('Year (365.25 d)', 'yr', 31557600),
], 3, 2);

// Base unit = Celsius.
final _temperatureSet = _UnitSet(
  'Temperature',
  Icons.thermostat,
  [
    _Unit('Celsius', '°C', (v) => v, (v) => v),
    _Unit('Fahrenheit', '°F', (v) => (v - 32) * 5 / 9, (v) => v * 9 / 5 + 32),
    _Unit('Kelvin', 'K', (v) => v - 273.15, (v) => v + 273.15),
  ],
  0,
  1,
  negative: true,
);

// ------------------------------------------------------------------
// Keypad used by every converter screen
// ------------------------------------------------------------------

class _ConvKeypad extends StatelessWidget {
  final List<List<String>> rows;
  final ValueChanged<String> onKey;
  final bool Function(String key)? enabled;
  final double height;
  const _ConvKeypad({
    required this.rows,
    required this.onKey,
    this.enabled,
    this.height = 64,
  });

  static const _actions = {'del', 'clr', 'neg', 'swap', 'next', 'prev'};

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;

    Widget key(String k) {
      if (k.isEmpty) return const SizedBox.shrink();
      final on = enabled?.call(k) ?? true;
      final fill = Color.alphaBlend(
        fg.withValues(alpha: _actions.contains(k) ? 0.22 : 0.12),
        bg,
      );
      final Widget child = switch (k) {
        'del' => Icon(Icons.backspace_outlined, color: fg, size: 26),
        'swap' => Icon(Icons.swap_vert, color: fg, size: 28),
        'next' => Icon(Icons.keyboard_arrow_down, color: fg, size: 30),
        'prev' => Icon(Icons.keyboard_arrow_up, color: fg, size: 30),
        'clr' => Text('AC', style: _style(fg)),
        'neg' => Text('±', style: _style(fg)),
        _ => Text(k, style: _style(fg)),
      };
      return Padding(
        padding: const EdgeInsets.all(3),
        child: Opacity(
          opacity: on ? 1 : 0.3,
          child: Material(
            color: fill,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd + 4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: on
                  ? () {
                      HapticFeedback.selectionClick();
                      onKey(k);
                    }
                  : null,
              child: Center(child: child),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          SizedBox(
            height: height,
            child: Row(
              children: [
                for (final k in row)
                  Expanded(
                    flex: row.length == 2 || (row.length == 3 && k == '0')
                        ? 2
                        : 1,
                    child: key(k),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  TextStyle _style(Color fg) =>
      TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: fg);
}

// ------------------------------------------------------------------
// Unit converter (Currency, Data, Volume, Speed, Length, Mass, Area,
// Time, Temperature). Two panels: tap one to edit it, the other follows.
// ------------------------------------------------------------------

Future<_Unit?> _pickUnit(
  BuildContext context,
  List<_Unit> units,
  _Unit selected,
  String title,
) {
  final accent = AppTheme.accentOf(context);
  final fg = accent.foreground;
  return showModalBottomSheet<_Unit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: accent.background,
    barrierColor: AppConstants.popupBarrier,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceMd,
          AppConstants.spaceSmMd,
          AppConstants.spaceMd,
          AppConstants.spaceMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: AppConstants.borderAlpha),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spaceMd),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                title.tr,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spaceSm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final u in units)
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                      ),
                      selected: identical(u, selected),
                      selectedTileColor: fg.withValues(
                        alpha: AppConstants.tintAlpha,
                      ),
                      title: Text(
                        u.name,
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        u.symbol,
                        style: TextStyle(
                          color: fg.withValues(alpha: AppConstants.mutedAlpha),
                        ),
                      ),
                      trailing: identical(u, selected)
                          ? Icon(Icons.check, color: fg)
                          : null,
                      onTap: () => Navigator.of(ctx).pop(u),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _UnitScreen extends StatefulWidget {
  final _UnitSet set;
  const _UnitScreen({required this.set});

  @override
  State<_UnitScreen> createState() => _UnitScreenState();
}

class _UnitScreenState extends State<_UnitScreen> {
  late int _u0 = widget.set.from;
  late int _u1 = widget.set.to;
  final List<String> _t = ['1', ''];
  int _active = 0;
  bool _loadingRate = false;

  static const _rows = [
    ['7', '8', '9', 'del'],
    ['4', '5', '6', 'clr'],
    ['1', '2', '3', 'neg'],
    ['0', '.', 'swap'],
  ];

  @override
  void initState() {
    super.initState();
    _recalc();
    if (widget.set.live) {
      _loadingRate = true;
      ExchangeRates.instance.refresh().then((_) {
        if (!mounted) return;
        setState(() {
          _loadingRate = false;
          _recalc();
        });
      });
    }
  }

  _Unit _unit(int i) => widget.set.units[i == 0 ? _u0 : _u1];

  void _recalc() {
    final src = _active;
    final dst = 1 - src;
    final v = double.tryParse(_t[src]) ?? 0;
    _t[dst] = _fmtNum(_unit(dst).fromBase(_unit(src).toBase(v)));
  }

  void _onKey(String k) {
    if (k == 'swap') {
      setState(() {
        final u = _u0;
        _u0 = _u1;
        _u1 = u;
        final s = _t[0];
        _t[0] = _t[1];
        _t[1] = s;
      });
      return;
    }
    var t = _t[_active];
    if (t.contains('e')) t = '';
    switch (k) {
      case 'del':
        t = t.isEmpty ? '' : t.substring(0, t.length - 1);
        if (t == '-') t = '';
      case 'clr':
        t = '';
      case 'neg':
        if (!widget.set.negative) return;
        t = t.startsWith('-') ? t.substring(1) : '-$t';
      case '.':
        if (t.contains('.')) return;
        t = (t.isEmpty || t == '-') ? '${t}0.' : '$t.';
      default:
        if (t.replaceAll('-', '').length >= 15) return;
        t = t == '0' ? k : (t == '-0' ? '-$k' : t + k);
    }
    setState(() {
      _t[_active] = t;
      _recalc();
    });
  }

  Future<void> _pick(int i) async {
    final r = await _pickUnit(
      context,
      widget.set.units,
      _unit(i),
      widget.set.label,
    );
    if (r == null || !mounted) return;
    final idx = widget.set.units.indexOf(r);
    setState(() {
      if (i == 0) {
        _u0 = idx;
      } else {
        _u1 = idx;
      }
      _recalc();
    });
  }

  Widget _panel(int i, Color fg, Color bg) {
    final unit = _unit(i);
    final active = _active == i;
    final text = _t[i].isEmpty ? '0' : _t[i];
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        side: BorderSide(color: active ? fg : Colors.transparent, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (!active) setState(() => _active = i);
        },
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceMd),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                onTap: () => _pick(i),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            unit.symbol,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: fg,
                            ),
                          ),
                          Icon(Icons.expand_more, color: fg),
                        ],
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          unit.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceSm),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _groupDec(text),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: active ? fg : fg.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _caption() {
    final a = _unit(0);
    final b = _unit(1);
    final one = _fmtNum(b.fromBase(a.toBase(1)));
    var s = '1 ${a.symbol} = $one ${b.symbol}';
    if (widget.set.live) {
      final live = ExchangeRates.instance.rate('USD', 'EUR') != null;
      final t = ExchangeRates.instance.updatedAt?.toLocal();
      if (_loadingRate) {
        s += '\nGetting the latest rate…';
      } else if (live && t != null) {
        final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
        s +=
            '\nLive rate · updated ${Utils.formatDate(t)} · '
            '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
      } else {
        s += '\nOffline: this rate is approximate.';
      }
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _appBar(widget.set.label, widget.set.icon),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMd),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: AppConstants.spaceSm),
                      _panel(0, fg, bg),
                      const SizedBox(height: AppConstants.spaceSm),
                      _panel(1, fg, bg),
                      const SizedBox(height: AppConstants.spaceMd),
                      Text(
                        _caption(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _ConvKeypad(
                rows: _rows,
                onKey: _onKey,
                enabled: (k) => k != 'neg' || widget.set.negative,
              ),
              const SizedBox(height: AppConstants.spaceSm),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Numeral system
// ------------------------------------------------------------------

class _NumeralScreen extends StatefulWidget {
  const _NumeralScreen();

  @override
  State<_NumeralScreen> createState() => _NumeralScreenState();
}

class _NumeralScreenState extends State<_NumeralScreen> {
  static const _names = ['Binary', 'Octal', 'Decimal', 'Hexadecimal'];
  static const _short = ['BIN', 'OCT', 'DEC', 'HEX'];
  static const _bases = [2, 8, 10, 16];
  static const _rows = [
    ['7', '8', '9', 'A'],
    ['4', '5', '6', 'B'],
    ['1', '2', '3', 'C'],
    ['0', 'D', 'E', 'F'],
    ['del', 'clr'],
  ];

  final List<String> _t = ['', '', '10', ''];
  int _active = 2;

  @override
  void initState() {
    super.initState();
    _recalc();
  }

  void _recalc() {
    final v = BigInt.tryParse(_t[_active], radix: _bases[_active]) ?? BigInt.zero;
    for (var i = 0; i < 4; i++) {
      if (i != _active) _t[i] = v.toRadixString(_bases[i]).toUpperCase();
    }
  }

  bool _enabled(String k) {
    if (k == 'del' || k == 'clr') return true;
    final v = int.tryParse(k, radix: 16);
    return v != null && v < _bases[_active];
  }

  void _onKey(String k) {
    var t = _t[_active];
    if (k == 'del') {
      t = t.isEmpty ? '' : t.substring(0, t.length - 1);
    } else if (k == 'clr') {
      t = '';
    } else {
      if (t.length >= 64) return;
      t = t == '0' ? k : t + k;
    }
    setState(() {
      _t[_active] = t;
      _recalc();
    });
  }

  String _shown(int i) {
    final s = _t[i].isEmpty ? '0' : _t[i];
    switch (_bases[i]) {
      case 2:
      case 16:
        return _groupInt(s, 4, ' ');
      case 8:
        return _groupInt(s, 3, ' ');
      default:
        return _groupInt(s, 3, ',');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);

    Widget panel(int i) {
      final active = _active == i;
      return Padding(
        padding: const EdgeInsets.only(bottom: AppConstants.spaceSm),
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            side: BorderSide(color: active ? fg : Colors.transparent, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (!active) setState(() => _active = i);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceMd,
                vertical: AppConstants.spaceSmMd,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _short[i],
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: fg,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _names[i],
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          _shown(i),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: active ? fg : fg.withValues(alpha: 0.8),
                          ),
                        ),
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

    return Scaffold(
      appBar: _appBar('Numeral system', Icons.numbers),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceMd),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: AppConstants.spaceSm),
                      for (var i = 0; i < 4; i++) panel(i),
                    ],
                  ),
                ),
              ),
              _ConvKeypad(
                rows: _rows,
                onKey: _onKey,
                enabled: _enabled,
                height: 56,
              ),
              const SizedBox(height: AppConstants.spaceSm),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Finance
// ------------------------------------------------------------------

class _FinanceScreen extends StatefulWidget {
  const _FinanceScreen();

  @override
  State<_FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<_FinanceScreen> {
  final _in = _Inputs('amount');
  List<String> _order = const ['amount'];
  int _mode = 0;
  int _freq = 3;
  int _taxMode = 0;

  static const _modes = [
    'Loan',
    'Simple interest',
    'Compound interest',
    'Tax / VAT',
  ];
  static const _freqs = ['Yearly', 'Semi-annual', 'Quarterly', 'Monthly', 'Daily'];
  static const _freqN = [1, 2, 4, 12, 365];

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final sym = AppConstants.currencySymbol;
    String money(double v) => Utils.formatCurrency(v, symbol: sym);
    void refresh() => setState(() {});

    final p = _in.n('amount');
    final r = _in.n('rate');
    final y = _in.n('years');

    final fields = <(String, String, String)>[]; // key, label, unit
    var label = '';
    var main = '—';
    var rows = <(String, String)>[];

    switch (_mode) {
      case 0:
        label = 'Monthly payment';
        fields.addAll([
          ('amount', 'Loan amount', sym),
          ('rate', 'Interest rate per year', '%'),
          ('years', 'Term', 'yrs'),
        ]);
        if (p > 0 && y > 0) {
          final n = y * 12;
          final i = r / 1200;
          final pay = i == 0
              ? p / n
              : p * i / (1 - math.pow(1 + i, -n).toDouble());
          main = money(pay);
          rows = [
            ('Total payment', money(pay * n)),
            ('Total interest', money(pay * n - p)),
          ];
        }
      case 1:
        label = 'Interest';
        fields.addAll([
          ('amount', 'Principal', sym),
          ('rate', 'Interest rate per year', '%'),
          ('years', 'Time', 'yrs'),
        ]);
        if (p > 0 && y > 0) {
          final interest = p * r / 100 * y;
          main = money(interest);
          rows = [('Total amount', money(p + interest))];
        }
      case 2:
        label = 'Future value';
        fields.addAll([
          ('amount', 'Principal', sym),
          ('rate', 'Interest rate per year', '%'),
          ('years', 'Time', 'yrs'),
        ]);
        if (p > 0 && y > 0) {
          final n = _freqN[_freq];
          final fv = p * math.pow(1 + r / 100 / n, n * y).toDouble();
          main = money(fv);
          rows = [('Interest earned', money(fv - p))];
        }
      default:
        label = _taxMode == 0 ? 'Total with tax' : 'Price without tax';
        fields.addAll([('amount', 'Amount', sym), ('rate', 'Tax rate', '%')]);
        if (p > 0) {
          if (_taxMode == 0) {
            final tax = p * r / 100;
            main = money(p + tax);
            rows = [('Tax', money(tax)), ('Amount without tax', money(p))];
          } else {
            final net = p / (1 + r / 100);
            main = money(net);
            rows = [('Tax', money(p - net)), ('Amount with tax', money(p))];
          }
        }
    }

    _order = [for (final f in fields) f.$1];

    return _KeyedPage(
      title: 'Finance',
      icon: Icons.paid_outlined,
      onKey: (k) => setState(() => _in.handle(k, _order)),
      children: [
        _chips(_modes, _mode, (i) {
          setState(() {
            _mode = i;
            _in.active = 'amount';
          });
        }, fg),
        if (_mode == 3)
          _chips(
            const ['Add tax', 'Remove tax'],
            _taxMode,
            (i) => setState(() => _taxMode = i),
            fg,
          ),
        for (final f in fields) _inField(_in, f.$1, f.$2, f.$3, fg, bg, refresh),
        if (_mode == 2)
          _chips(_freqs, _freq, (i) => setState(() => _freq = i), fg),
        _resultCard(fg, bg, label: label, value: main, rows: rows),
      ],
    );
  }
}

// ------------------------------------------------------------------
// Date
// ------------------------------------------------------------------

class _DateScreen extends StatefulWidget {
  const _DateScreen();

  @override
  State<_DateScreen> createState() => _DateScreenState();
}

class _DateScreenState extends State<_DateScreen> {
  final _in = _Inputs('ys');
  static const _order = ['ys', 'ms', 'ds'];
  late DateTime _a = _today();
  late DateTime _b = _today();
  int _mode = 0;
  int _dir = 0; // 0 = add, 1 = subtract

  DateTime _today() {
    final n = Utils.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    void refresh() => setState(() {});

    final fields = <Widget>[];
    var label = '';
    var main = '—';
    var rows = <(String, String)>[];

    if (_mode == 0) {
      label = 'Difference';
      fields.addAll([
        _datePanel(context, 'From', _a, (d) => setState(() => _a = d), fg, bg),
        _datePanel(context, 'To', _b, (d) => setState(() => _b = d), fg, bg),
      ]);
      final lo = _b.isBefore(_a) ? _b : _a;
      final hi = _b.isBefore(_a) ? _a : _b;
      var yy = hi.year - lo.year;
      var mm = hi.month - lo.month;
      var dd = hi.day - lo.day;
      if (dd < 0) {
        mm--;
        dd += DateTime(hi.year, hi.month, 0).day;
      }
      if (mm < 0) {
        yy--;
        mm += 12;
      }
      final days = DateTime.utc(hi.year, hi.month, hi.day)
          .difference(DateTime.utc(lo.year, lo.month, lo.day))
          .inDays;
      main = [
        if (yy > 0) _plural(yy, 'year'),
        if (mm > 0) _plural(mm, 'month'),
        if (dd > 0 || (yy == 0 && mm == 0)) _plural(dd, 'day'),
      ].join(', ');
      rows = [
        ('Total days', '$days'),
        ('Weeks', '${_plural(days ~/ 7, 'week')} ${_plural(days % 7, 'day')}'),
        ('Total months', '${yy * 12 + mm}'),
      ];
    } else {
      label = 'Result date';
      fields.addAll([
        _datePanel(
          context,
          'Start date',
          _a,
          (d) => setState(() => _a = d),
          fg,
          bg,
        ),
        _chips(
          const ['Add', 'Subtract'],
          _dir,
          (i) => setState(() => _dir = i),
          fg,
        ),
        _inField(_in, 'ys', 'Years', 'yrs', fg, bg, refresh),
        _inField(_in, 'ms', 'Months', 'mo', fg, bg, refresh),
        _inField(_in, 'ds', 'Days', 'd', fg, bg, refresh),
      ]);
      final sign = _dir == 0 ? 1 : -1;
      final yrs = _in.n('ys').floor();
      final mon = _in.n('ms').floor();
      final day = _in.n('ds').floor();
      final idx = _a.month - 1 + sign * (mon + yrs * 12);
      final fl = (idx / 12).floor();
      final ny = _a.year + fl;
      final nm = idx - fl * 12 + 1;
      final nd = math.min(_a.day, DateTime(ny, nm + 1, 0).day);
      final res = DateTime(ny, nm, nd + sign * day);
      final diff = DateTime.utc(res.year, res.month, res.day)
          .difference(DateTime.utc(_a.year, _a.month, _a.day))
          .inDays;
      main = Utils.formatDate(res);
      rows = [
        ('Weekday', _weekdays[res.weekday - 1]),
        ('Days from start', '${diff.abs()}'),
      ];
    }

    return _KeyedPage(
      title: 'Date',
      icon: Icons.event_outlined,
      // Date difference has nothing to type, so no keypad there.
      showKeypad: _mode == 1,
      enabled: (k) => k != '.', // whole numbers only
      onKey: (k) => setState(() => _in.handle(k, _order)),
      children: [
        _chips(
          const ['Date difference', 'Add / subtract'],
          _mode,
          (i) => setState(() {
            _mode = i;
            _in.active = 'ys';
          }),
          fg,
        ),
        ...fields,
        _resultCard(fg, bg, label: label, value: main, rows: rows),
      ],
    );
  }
}

// ------------------------------------------------------------------
// Discount
// ------------------------------------------------------------------

class _DiscountScreen extends StatefulWidget {
  const _DiscountScreen();

  @override
  State<_DiscountScreen> createState() => _DiscountScreenState();
}

class _DiscountScreenState extends State<_DiscountScreen> {
  final _in = _Inputs('price');
  static const _order = ['price', 'd1', 'd2', 'tax'];

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    final sym = AppConstants.currencySymbol;
    String money(double v) => Utils.formatCurrency(v, symbol: sym);
    void refresh() => setState(() {});

    final price = _in.n('price');
    final d1 = _in.n('d1').clamp(0.0, 100.0).toDouble();
    final d2 = _in.n('d2').clamp(0.0, 100.0).toDouble();
    final tax = _in.n('tax');

    var main = '—';
    var rows = <(String, String)>[];
    if (price > 0) {
      final after1 = price * (1 - d1 / 100);
      final after2 = after1 * (1 - d2 / 100);
      final taxAmt = after2 * tax / 100;
      main = money(after2 + taxAmt);
      rows = [
        ('You save', money(price - after2)),
        ('Total discount', '${_fmtNum((price - after2) / price * 100)}%'),
        ('Price after discount', money(after2)),
        if (tax > 0) ('Tax', money(taxAmt)),
      ];
    }

    return _KeyedPage(
      title: 'Discount',
      icon: Icons.sell_outlined,
      onKey: (k) => setState(() => _in.handle(k, _order)),
      children: [
        _inField(_in, 'price', 'Original price', sym, fg, bg, refresh),
        _inField(_in, 'd1', 'Discount', '%', fg, bg, refresh),
        _inField(_in, 'd2', 'Extra discount (optional)', '%', fg, bg, refresh),
        _inField(_in, 'tax', 'Tax (optional)', '%', fg, bg, refresh),
        _resultCard(fg, bg, label: 'Final price', value: main, rows: rows),
      ],
    );
  }
}

// ------------------------------------------------------------------
// BMI
// ------------------------------------------------------------------

class _BmiScreen extends StatefulWidget {
  const _BmiScreen();

  @override
  State<_BmiScreen> createState() => _BmiScreenState();
}

class _BmiScreenState extends State<_BmiScreen> {
  final _in = _Inputs('cm');
  List<String> _order = const ['cm', 'kg'];
  bool _imperial = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;
    void refresh() => setState(() {});

    final double h = _imperial
        ? (_in.n('ft') * 12 + _in.n('in')) * 0.0254
        : _in.n('cm') / 100;
    final double w = _imperial ? _in.n('lb') * 0.45359237 : _in.n('kg');

    var main = '—';
    var label = 'Your BMI';
    Color? color;
    var rows = <(String, String)>[];
    Widget? gauge;
    if (h > 0 && w > 0) {
      final bmi = w / (h * h);
      final String cat;
      if (bmi < 18.5) {
        cat = 'Underweight';
        color = const Color(0xFF42A5F5);
      } else if (bmi < 25) {
        cat = 'Normal weight';
        color = AppConstants.incomeColor;
      } else if (bmi < 30) {
        cat = 'Overweight';
        color = const Color(0xFFFFA726);
      } else {
        cat = 'Obese';
        color = const Color(0xFFEF5350);
      }
      main = bmi.toStringAsFixed(1);
      label = 'Your BMI · $cat';
      final lo = 18.5 * h * h;
      final hi = 24.9 * h * h;
      String wt(double kg) => _imperial
          ? '${(kg / 0.45359237).toStringAsFixed(1)} lb'
          : '${kg.toStringAsFixed(1)} kg';
      rows = [('Healthy weight range', '${wt(lo)} – ${wt(hi)}')];
      gauge = _BmiGauge(bmi: bmi);
    }

    final List<(String, String, String)> fields = _imperial
        ? const [
            ('ft', 'Height', 'ft'),
            ('in', 'Inches', 'in'),
            ('lb', 'Weight', 'lb'),
          ]
        : const [('cm', 'Height', 'cm'), ('kg', 'Weight', 'kg')];
    _order = [for (final f in fields) f.$1];

    return _KeyedPage(
      title: 'BMI',
      icon: Icons.monitor_weight_outlined,
      onKey: (k) => setState(() => _in.handle(k, _order)),
      children: [
        _chips(
          const ['Metric', 'Imperial'],
          _imperial ? 1 : 0,
          (i) => setState(() {
            _imperial = i == 1;
            _in.active = _imperial ? 'ft' : 'cm';
          }),
          fg,
        ),
        for (final f in fields) _inField(_in, f.$1, f.$2, f.$3, fg, bg, refresh),
        _resultCard(
          fg,
          bg,
          label: label,
          value: main,
          rows: rows,
          valueColor: color,
        ),
        if (gauge != null)
          Material(
            color: bg,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spaceMd),
              child: gauge,
            ),
          ),
      ],
    );
  }
}

class _BmiGauge extends StatelessWidget {
  final double bmi;
  const _BmiGauge({required this.bmi});

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.accentOf(context).foreground;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);
    const segs = [
      (35, Color(0xFF42A5F5)),
      (65, Color(0xFF4CAF50)),
      (50, Color(0xFFFFA726)),
      (100, Color(0xFFEF5350)),
    ];
    final labelStyle = TextStyle(fontSize: 11, color: muted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final f = ((bmi - 15) / 25).clamp(0.0, 1.0);
            return SizedBox(
              height: 28,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 10,
                    height: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        children: [
                          for (final s in segs)
                            Expanded(
                              flex: s.$1,
                              child: ColoredBox(color: s.$2),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: (w * f - 7).clamp(0.0, w - 14).toDouble(),
                    top: 4,
                    child: Container(
                      width: 14,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: Colors.black54, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('15', style: labelStyle),
            Text('18.5', style: labelStyle),
            Text('25', style: labelStyle),
            Text('30', style: labelStyle),
            Text('40', style: labelStyle),
          ],
        ),
      ],
    );
  }
}