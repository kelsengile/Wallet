import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../themes.dart';

// ------------------------------------------------------------------
// Calculator engine (one shared instance, so the full screen and the
// floating window always show the same calculation)
// ------------------------------------------------------------------

class _CalcEngine extends ChangeNotifier {
  _CalcEngine._();
  static final _CalcEngine shared = _CalcEngine._();

  static const _ops = ['+', '−', '×', '÷', '^'];

  String expr = '';
  String result = ''; // live preview, or the final answer after "="
  bool done = false; // true right after "="
  bool degrees = true;
  bool sci = false;
  double memory = 0;
  final List<(String, String)> history = [];

  bool get _endsOp =>
      expr.isNotEmpty && _ops.contains(expr.substring(expr.length - 1));

  // ---------- Input ----------

  void digit(String d) {
    if (done) {
      expr = '';
      done = false;
    }
    if (RegExp(r'[)πe!%]$').hasMatch(expr)) expr += '×';
    final m = RegExp(r'(\d*\.?\d*)$').firstMatch(expr);
    final cur = m?.group(1) ?? '';
    if (d == '.') {
      if (cur.contains('.')) return;
      if (cur.isEmpty) expr += '0';
    } else if (cur == '0') {
      expr = expr.substring(0, expr.length - 1);
    }
    expr += d;
    _update();
  }

  void op(String o) {
    if (done) {
      if (result.isEmpty || result == 'Error') return;
      expr = result;
      done = false;
    }
    if (expr.isEmpty) {
      if (o == '−') {
        expr = '−';
        _update();
      }
      return;
    }
    if (expr == '−') return;
    if (_endsOp) {
      expr = expr.substring(0, expr.length - 1) + o;
    } else if (expr.endsWith('(')) {
      if (o != '−') return;
      expr += o;
    } else {
      expr += o;
    }
    _update();
  }

  /// Functions, constants and "(".
  void func(String f) {
    if (done) {
      expr = '';
      done = false;
    }
    if (RegExp(r'[\d)πe!%]$').hasMatch(expr)) expr += '×';
    expr += f;
    _update();
  }

  void close() {
    if (done) return;
    final open = '('.allMatches(expr).length - ')'.allMatches(expr).length;
    if (open <= 0 || _endsOp || expr.endsWith('(')) return;
    expr += ')';
    _update();
  }

  /// "!" and "%".
  void post(String p) {
    if (done) {
      if (result.isEmpty || result == 'Error') return;
      expr = result;
      done = false;
    }
    if (expr.isEmpty || _endsOp || expr.endsWith('(')) return;
    expr += p;
    _update();
  }

  /// "^2" and "^(−1)".
  void power(String t) {
    if (done) {
      if (result.isEmpty || result == 'Error') return;
      expr = result;
      done = false;
    }
    if (expr.isEmpty || _endsOp || expr.endsWith('(')) return;
    expr += t;
    _update();
  }

  void negate() {
    if (done) {
      if (result.isEmpty || result == 'Error') return;
      expr = result;
      done = false;
    }
    final neg = RegExp(
      r'\(−(\d+\.?\d*(?:E[−+]?\d+)?)$',
    ).firstMatch(expr);
    if (neg != null) {
      expr = expr.substring(0, neg.start) + neg.group(1)!;
    } else {
      final m = RegExp(r'(\d+\.?\d*(?:E[−+]?\d+)?)$').firstMatch(expr);
      if (m != null) {
        expr = '${expr.substring(0, m.start)}(−${m.group(1)}';
      } else if (expr.isEmpty || _endsOp || expr.endsWith('(')) {
        expr += '(−';
      } else {
        return;
      }
    }
    _update();
  }

  void back() {
    done = false;
    if (expr.isEmpty) return;
    final m = RegExp(r'(sin|cos|tan|ln|log|√)\($').firstMatch(expr);
    expr = m != null
        ? expr.substring(0, m.start)
        : expr.substring(0, expr.length - 1);
    _update();
  }

  void clear() {
    expr = '';
    result = '';
    done = false;
    notifyListeners();
  }

  void equals() {
    if (expr.isEmpty || done) return;
    final v = _tryEval(expr);
    if (v == null) {
      result = 'Error';
      notifyListeners();
      return;
    }
    final t = fmt(v);
    history.insert(0, (expr, t));
    if (history.length > 50) history.removeLast();
    result = t;
    done = true;
    notifyListeners();
  }

  void useResult(String r) {
    expr = r;
    done = false;
    _update();
  }

  void toggleDeg() {
    degrees = !degrees;
    _update();
  }

  void toggleSci() {
    sci = !sci;
    notifyListeners();
  }

  // ---------- Memory ----------

  double? get _value => _tryEval(done ? result : expr);

  void memAdd(int sign) {
    final v = _value;
    if (v == null) return;
    memory += sign * v;
    notifyListeners();
  }

  void memRecall() {
    if (done) {
      expr = '';
      done = false;
    }
    if (RegExp(r'[\d)πe!%]$').hasMatch(expr)) expr += '×';
    expr += fmt(memory);
    _update();
  }

  void memClear() {
    memory = 0;
    notifyListeners();
  }

  // ---------- Maths ----------

  void _update() {
    result = '';
    if (expr.isNotEmpty && !_endsOp) {
      final v = _tryEval(expr);
      if (v != null) {
        final t = fmt(v);
        if (t != expr) result = t;
      }
    }
    notifyListeners();
  }

  double? _tryEval(String e) {
    var s = e.replaceAll('-', '−');
    while (s.isNotEmpty && _ops.contains(s.substring(s.length - 1))) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) return null;
    final open = '('.allMatches(s).length - ')'.allMatches(s).length;
    if (open > 0) s += ')' * open;
    try {
      final v = _Parser(s, degrees).parse();
      if (v.isNaN || v.isInfinite) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  static String fmt(double v) {
    final r = double.parse(v.toStringAsPrecision(12));
    if (r == 0) return '0';
    final a = r.abs();
    String s;
    if (a >= 1e15 || a < 1e-9) {
      s = r
          .toStringAsExponential(9)
          .replaceFirst(RegExp(r'\.?0+e'), 'e')
          .replaceAll('e+', 'E')
          .replaceAll('e-', 'E-');
    } else {
      final mag = (math.log(a) / math.ln10).floor();
      final dec = (11 - mag).clamp(0, 18);
      s = r.toStringAsFixed(dec);
      if (s.contains('.')) {
        s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      }
    }
    return s.replaceAll('-', '−');
  }
}

/// Small recursive-descent parser: + − × ÷ ^ ! % ( ) π e √ sin cos tan ln log.
class _Parser {
  _Parser(this.s, this.deg);
  final String s;
  final bool deg;
  int i = 0;

  double parse() {
    final v = _sum();
    if (i != s.length) throw const FormatException();
    return v;
  }

  bool _eat(String c) {
    if (i < s.length && s[i] == c) {
      i++;
      return true;
    }
    return false;
  }

  bool _isLetter(String c) => RegExp(r'[a-z]').hasMatch(c);

  double _sum() {
    var v = _prod();
    while (true) {
      if (_eat('+')) {
        v += _prod();
      } else if (_eat('−')) {
        v -= _prod();
      } else {
        return v;
      }
    }
  }

  bool _implicit() =>
      i < s.length && (s[i] == '(' || s[i] == 'π' || s[i] == '√' || _isLetter(s[i]));

  double _prod() {
    var v = _unary();
    while (true) {
      if (_eat('×')) {
        v *= _unary();
      } else if (_eat('÷')) {
        final d = _unary();
        if (d == 0) throw const FormatException();
        v /= d;
      } else if (_implicit()) {
        v *= _unary();
      } else {
        return v;
      }
    }
  }

  double _unary() {
    if (_eat('−')) return -_unary();
    if (_eat('+')) return _unary();
    return _pow();
  }

  double _pow() {
    final b = _post();
    if (_eat('^')) return math.pow(b, _unary()).toDouble();
    return b;
  }

  double _post() {
    var v = _atom();
    while (true) {
      if (_eat('!')) {
        v = _fact(v);
      } else if (_eat('%')) {
        v /= 100;
      } else {
        return v;
      }
    }
  }

  double _atom() {
    if (_eat('(')) {
      final v = _sum();
      if (!_eat(')')) throw const FormatException();
      return v;
    }
    if (_eat('π')) return math.pi;
    if (_eat('√')) {
      final v = _atom();
      if (v < 0) throw const FormatException();
      return math.sqrt(v);
    }
    final c = i < s.length ? s[i] : '';
    if (RegExp(r'[0-9.]').hasMatch(c)) return _number();
    if (_isLetter(c)) {
      final st = i;
      while (i < s.length && _isLetter(s[i])) {
        i++;
      }
      final name = s.substring(st, i);
      if (name == 'e') return math.e;
      if (!_eat('(')) throw const FormatException();
      final v = _sum();
      if (!_eat(')')) throw const FormatException();
      return _fn(name, v);
    }
    throw const FormatException();
  }

  double _number() {
    final st = i;
    while (i < s.length && RegExp(r'[0-9.]').hasMatch(s[i])) {
      i++;
    }
    if (i < s.length && s[i] == 'E') {
      final save = i;
      i++;
      if (i < s.length && (s[i] == '−' || s[i] == '+')) i++;
      final ds = i;
      while (i < s.length && RegExp(r'[0-9]').hasMatch(s[i])) {
        i++;
      }
      if (ds == i) i = save;
    }
    final txt = s.substring(st, i).replaceAll('−', '-').replaceAll('E', 'e');
    final v = double.tryParse(txt);
    if (v == null) throw const FormatException();
    return v;
  }

  double _fn(String name, double v) {
    final r = deg ? v * math.pi / 180 : v;
    switch (name) {
      case 'sin':
        return math.sin(r);
      case 'cos':
        return math.cos(r);
      case 'tan':
        if (deg && ((v - 90) % 180 == 0)) throw const FormatException();
        return math.tan(r);
      case 'ln':
        if (v <= 0) throw const FormatException();
        return math.log(v);
      case 'log':
        if (v <= 0) throw const FormatException();
        return math.log(v) / math.ln10;
    }
    throw const FormatException();
  }

  double _fact(double v) {
    if (v < 0 || v != v.roundToDouble() || v > 170) {
      throw const FormatException();
    }
    var r = 1.0;
    for (var k = 2; k <= v; k++) {
      r *= k;
    }
    return r;
  }
}

// ------------------------------------------------------------------
// The calculator itself (used by the full screen and the floating window)
// ------------------------------------------------------------------

class _CalcPanel extends StatelessWidget {
  final _CalcEngine e;
  final bool compact;
  final bool showKeys;
  const _CalcPanel({
    required this.e,
    required this.compact,
    this.showKeys = true,
  });

  Widget _tag(String text, Color fg) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: fg.withValues(alpha: AppConstants.tintAlpha),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
    ),
  );

  Widget _display(Color fg, Color bg) {
    final big = compact ? 28.0 : 46.0;
    final small = compact ? 14.0 : 22.0;
    final muted = fg.withValues(alpha: AppConstants.mutedAlpha);

    Widget line(String text, double size, Color color, FontWeight w) =>
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: size,
              color: color,
              fontWeight: w,
              height: 1.15,
            ),
          ),
        );

    final top = e.done
        ? line(e.expr, small, muted, FontWeight.w400)
        : line(e.expr.isEmpty ? '0' : e.expr, big, fg, FontWeight.w600);
    final bottom = e.done
        ? line(e.result, big, fg, FontWeight.w700)
        : line(e.result.isEmpty ? ' ' : e.result, small, muted, FontWeight.w400);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : AppConstants.spaceMd),
      decoration: BoxDecoration(
        color: compact ? fg.withValues(alpha: 0.08) : bg,
        borderRadius: BorderRadius.circular(
          compact ? 14 : AppConstants.radiusLg,
        ),
      ),
      child: Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 16,
            child: Row(
              children: [
                if (e.memory != 0) _tag('M', fg),
                _tag(e.degrees ? 'DEG' : 'RAD', fg),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [top, const SizedBox(height: 2), bottom],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;

    // kind: 0 number, 1 operator, 2 equals, 3 scientific
    Widget k(
      String label,
      VoidCallback tap, {
      int kind = 0,
      VoidCallback? hold,
      IconData? icon,
    }) {
      final Color fill = switch (kind) {
        2 => fg,
        1 => Color.alphaBlend(fg.withValues(alpha: 0.22), bg),
        3 => Color.alphaBlend(fg.withValues(alpha: 0.05), bg),
        _ => Color.alphaBlend(fg.withValues(alpha: 0.12), bg),
      };
      final Color text = kind == 2 ? bg : fg;
      final double size = kind == 3
          ? (compact ? 13 : 16)
          : (compact ? 18 : 24);
      return Expanded(
        child: Padding(
          padding: EdgeInsets.all(compact ? 2 : 3),
          child: Material(
            color: fill,
            borderRadius: BorderRadius.circular(
              compact ? 12 : AppConstants.radiusMd + 4,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                tap();
              },
              onLongPress: hold,
              child: Center(
                child: icon != null
                    ? Icon(icon, size: size + 2, color: text)
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: size,
                              fontWeight: FontWeight.w600,
                              color: text,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }

    Widget row(List<Widget> keys) {
      final r = Row(children: keys);
      return compact ? SizedBox(height: 42, child: r) : Expanded(child: r);
    }

    final rows = <Widget>[
      if (e.sci) ...[
        row([
          k(e.degrees ? 'DEG' : 'RAD', e.toggleDeg, kind: 3),
          k('(', () => e.func('('), kind: 3),
          k(')', e.close, kind: 3),
          k('π', () => e.func('π'), kind: 3),
          k('e', () => e.func('e'), kind: 3),
        ]),
        row([
          k('sin', () => e.func('sin('), kind: 3),
          k('cos', () => e.func('cos('), kind: 3),
          k('tan', () => e.func('tan('), kind: 3),
          k('ln', () => e.func('ln('), kind: 3),
          k('log', () => e.func('log('), kind: 3),
        ]),
        row([
          k('x²', () => e.power('^2'), kind: 3),
          k('√', () => e.func('√('), kind: 3),
          k('xʸ', () => e.op('^'), kind: 3),
          k('1/x', () => e.power('^(−1)'), kind: 3),
          k('n!', () => e.post('!'), kind: 3),
        ]),
        row([
          k('MC', e.memClear, kind: 3),
          k('MR', e.memRecall, kind: 3),
          k('M+', () => e.memAdd(1), kind: 3),
          k('M−', () => e.memAdd(-1), kind: 3),
        ]),
      ],
      row([
        k('AC', e.clear, kind: 1),
        k('', e.back, kind: 1, hold: e.clear, icon: Icons.backspace_outlined),
        k('%', () => e.post('%'), kind: 1),
        k('÷', () => e.op('÷'), kind: 1),
      ]),
      row([
        k('7', () => e.digit('7')),
        k('8', () => e.digit('8')),
        k('9', () => e.digit('9')),
        k('×', () => e.op('×'), kind: 1),
      ]),
      row([
        k('4', () => e.digit('4')),
        k('5', () => e.digit('5')),
        k('6', () => e.digit('6')),
        k('−', () => e.op('−'), kind: 1),
      ]),
      row([
        k('1', () => e.digit('1')),
        k('2', () => e.digit('2')),
        k('3', () => e.digit('3')),
        k('+', () => e.op('+'), kind: 1),
      ]),
      row([
        k('±', e.negate),
        k('0', () => e.digit('0')),
        k('.', () => e.digit('.')),
        k('=', e.equals, kind: 2),
      ]),
    ];

    final keypad = Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: rows,
    );

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _display(fg, bg),
          if (showKeys) ...[const SizedBox(height: 4), keypad],
        ],
      );
    }
    return Column(
      children: [
        Expanded(flex: 5, child: _display(fg, bg)),
        const SizedBox(height: AppConstants.spaceSm),
        Expanded(flex: rows.length * 2, child: keypad),
      ],
    );
  }
}

// ------------------------------------------------------------------
// History pop-up
// ------------------------------------------------------------------

Future<void> _showHistory(BuildContext context, _CalcEngine e) {
  final accent = AppTheme.accentOf(context);
  final fg = accent.foreground;
  final muted = fg.withValues(alpha: AppConstants.mutedAlpha);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: accent.background,
    barrierColor: AppConstants.popupBarrier,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceLg,
            AppConstants.spaceSmMd,
            AppConstants.spaceLg,
            AppConstants.spaceLg,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'History'.tr,
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                  if (e.history.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: fg),
                      onPressed: () => setS(() => e.history.clear()),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceSm),
              if (e.history.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppConstants.spaceLg),
                  child: Center(
                    child: Text('No history yet', style: TextStyle(color: muted)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: e.history.length,
                    itemBuilder: (_, i) {
                      final h = e.history[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          h.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: muted),
                        ),
                        subtitle: Text(
                          '= ${h.$2}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                        onTap: () {
                          e.useResult(h.$2);
                          Navigator.of(ctx).pop();
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------------
// Full screen
// ------------------------------------------------------------------

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _e = _CalcEngine.shared;

  @override
  void initState() {
    super.initState();
    // Only one calculator at a time: the full screen replaces the floating one.
    WidgetsBinding.instance.addPostFrameCallback((_) => CalculatorFloat.hide());
  }

  void _float() {
    CalculatorFloat.show(context);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calculate_outlined),
            const SizedBox(width: AppConstants.spaceSm),
            Text('Calculator'.tr),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.functions),
            tooltip: 'Scientific',
            onPressed: _e.toggleSci,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () => _showHistory(context, _e),
          ),
          IconButton(
            icon: const Icon(Icons.picture_in_picture_alt_outlined),
            tooltip: 'Float',
            onPressed: _float,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceMd,
            AppConstants.spaceSm,
            AppConstants.spaceMd,
            AppConstants.spaceMd,
          ),
          child: ListenableBuilder(
            listenable: _e,
            builder: (_, _) => _CalcPanel(e: _e, compact: false),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Floating window (lives in the root Overlay, so it stays on top of
// every page and the pages behind it can still be used)
// ------------------------------------------------------------------

class CalculatorFloat {
  CalculatorFloat._();

  static OverlayEntry? _entry;

  /// Position of the floating window. Only the Positioned listens to it,
  /// so dragging never rebuilds the calculator itself.
  static final ValueNotifier<Offset> pos = ValueNotifier(const Offset(24, 140));

  static bool get isShown => _entry != null;

  static void show(BuildContext context) {
    if (_entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(builder: (_) => const _FloatingCalculator());
    overlay.insert(_entry!);
  }

  static void hide() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry.remove();
    entry.dispose();
  }
}

class _FloatingCalculator extends StatefulWidget {
  const _FloatingCalculator();

  @override
  State<_FloatingCalculator> createState() => _FloatingCalculatorState();
}

class _FloatingCalculatorState extends State<_FloatingCalculator> {
  static const double _width = 276;
  static const double _tapSlop = 6; // moved less than this = a tap
  final _e = _CalcEngine.shared;
  bool _mini = false;
  double _moved = 0;

  Widget _hdr(IconData icon, VoidCallback onTap, Color fg) => InkResponse(
    onTap: onTap,
    radius: 16,
    child: SizedBox(
      width: 30,
      height: 30,
      child: Icon(icon, size: 18, color: fg),
    ),
  );

  void _expand() {
    final nav = Navigator.of(context);
    CalculatorFloat.hide();
    nav.push(MaterialPageRoute(builder: (_) => const CalculatorScreen()));
  }

  Offset _clamp(Offset p) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    return Offset(
      p.dx.clamp(0.0, math.max(0.0, size.width - _width)).toDouble(),
      p.dy.clamp(pad.top, math.max(pad.top, size.height - 48)).toDouble(),
    );
  }

  // The title row: drag it to move, tap it to minimize / restore.
  void _down(PointerDownEvent _) => _moved = 0;

  void _move(PointerMoveEvent ev) {
    _moved += ev.delta.distance;
    CalculatorFloat.pos.value = _clamp(CalculatorFloat.pos.value + ev.delta);
  }

  void _up(PointerUpEvent _) {
    if (_moved < _tapSlop) setState(() => _mini = !_mini);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentOf(context);
    final fg = accent.foreground;
    final bg = accent.background;

    final card = RepaintBoundary(
      child: Material(
        elevation: 12,
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          side: BorderSide(color: fg.withValues(alpha: 0.25)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _down,
                      onPointerMove: _move,
                      onPointerUp: _up,
                      child: SizedBox(
                        height: 30,
                        child: Row(
                          children: [
                            Icon(
                              Icons.drag_indicator,
                              size: 18,
                              color: fg.withValues(
                                alpha: AppConstants.mutedAlpha,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Calculator'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: fg,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!_mini) _hdr(Icons.functions, _e.toggleSci, fg),
                  _hdr(Icons.open_in_full, _expand, fg),
                  _hdr(Icons.close, CalculatorFloat.hide, fg),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: ListenableBuilder(
                listenable: _e,
                builder: (_, _) =>
                    _CalcPanel(e: _e, compact: true, showKeys: !_mini),
              ),
            ),
          ],
        ),
      ),
    );

    return ValueListenableBuilder<Offset>(
      valueListenable: CalculatorFloat.pos,
      child: card, // built once, reused while dragging
      builder: (context, raw, child) {
        final p = _clamp(raw); // also keeps it on screen after a rotation
        return Positioned(left: p.dx, top: p.dy, width: _width, child: child!);
      },
    );
  }
}