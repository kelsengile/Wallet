import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Entry point ───────────────────────────────────────────────────────────────
// Opens the calculator as the end-drawer (slides in from the right, full screen).
//
// Usage:
//   endDrawer: Drawer(
//     width: double.infinity,
//     child: Scaffold(body: _endDrawerContent),
//   )

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage>
    with SingleTickerProviderStateMixin {
  String _display = '0';
  String _expression = '';
  double? _firstOperand;
  String? _operator;
  bool _shouldReplace = true;
  bool _justEvaluated = false;
  String? _activeOperator;

  // Pop animation on "="
  late final AnimationController _popCtrl;
  late final Animation<double> _popScale;

  @override
  void initState() {
    super.initState();
    _popCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _popScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _popCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _popCtrl.dispose();
    super.dispose();
  }

  // ── Logic ─────────────────────────────────────────────────────────────────

  void _onDigit(String digit) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_shouldReplace || _display == '0') {
        _display = digit;
        _shouldReplace = false;
      } else {
        if (_display.replaceAll('-', '').replaceAll('.', '').length >= 12)
          return;
        _display = _display + digit;
      }
      _justEvaluated = false;
    });
  }

  void _onDecimal() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_shouldReplace) {
        _display = '0.';
        _shouldReplace = false;
      } else if (!_display.contains('.')) {
        _display = '$_display.';
      }
      _justEvaluated = false;
    });
  }

  void _onOperator(String op) {
    HapticFeedback.mediumImpact();
    setState(() {
      final current = double.tryParse(_display) ?? 0;
      if (_firstOperand != null && !_shouldReplace && !_justEvaluated) {
        final result = _calculate(_firstOperand!, current, _operator!);
        _display = _fmt(result);
        _firstOperand = result;
      } else {
        _firstOperand = current;
      }
      _operator = op;
      _activeOperator = op;
      _expression = '${_fmt(_firstOperand!)} $op';
      _shouldReplace = true;
      _justEvaluated = false;
    });
  }

  void _onEquals() {
    HapticFeedback.mediumImpact();
    if (_firstOperand == null || _operator == null) return;
    final current = double.tryParse(_display) ?? 0;
    final result = _calculate(_firstOperand!, current, _operator!);
    _popCtrl.forward(from: 0);
    setState(() {
      _expression = '${_fmt(_firstOperand!)} $_operator ${_fmt(current)} =';
      _display = _fmt(result);
      _firstOperand = null;
      _operator = null;
      _activeOperator = null;
      _shouldReplace = true;
      _justEvaluated = true;
    });
  }

  void _onClear() {
    HapticFeedback.mediumImpact();
    setState(() {
      _display = '0';
      _expression = '';
      _firstOperand = null;
      _operator = null;
      _activeOperator = null;
      _shouldReplace = true;
      _justEvaluated = false;
    });
  }

  void _onToggleSign() {
    HapticFeedback.lightImpact();
    setState(() {
      final v = double.tryParse(_display) ?? 0;
      _display = _fmt(-v);
    });
  }

  void _onPercent() {
    HapticFeedback.lightImpact();
    setState(() {
      final v = double.tryParse(_display) ?? 0;
      _display = _fmt(v / 100);
    });
  }

  void _onBackspace() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_shouldReplace || _display == '0') return;
      if (_display.length <= 1 ||
          (_display.startsWith('-') && _display.length <= 2)) {
        _display = '0';
        _shouldReplace = true;
      } else {
        _display = _display.substring(0, _display.length - 1);
        if (_display == '-') _display = '0';
      }
    });
  }

  double _calculate(double a, double b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b != 0 ? a / b : double.nan;
      default:
        return b;
    }
  }

  String _fmt(double value) {
    if (value.isNaN) return 'Error';
    if (value.isInfinite) return value > 0 ? '∞' : '-∞';
    if (value == value.truncateToDouble()) return value.toInt().toString();
    String s = value.toStringAsPrecision(10);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  String get _formattedDisplay {
    if (_display == 'Error' || _display == '∞' || _display == '-∞') {
      return _display;
    }
    final parts = _display.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';
    final isNeg = intPart.startsWith('-');
    final digits = isNeg ? intPart.substring(1) : intPart;
    final formatted = digits.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '${isNeg ? '-' : ''}$formatted$decPart';
  }

  double get _displayFontSize {
    final len = _formattedDisplay.length;
    if (len <= 7) return 64;
    if (len <= 10) return 52;
    if (len <= 13) return 42;
    return 32;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Column(
      children: [
        // ── Header ────────────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(4, topPad + 12, 16, 12),
          color: cs.surfaceContainer,
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.close_rounded, color: cs.onSurface),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
              Expanded(
                child: Text(
                  'Calculator',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Display ───────────────────────────────────────────────────────
        Expanded(
          child: Container(
            width: double.infinity,
            color: cs.surfaceContainer,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Expression line
                AnimatedOpacity(
                  opacity: _expression.isEmpty ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _expression,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                // Main number
                ScaleTransition(
                  scale: _popScale,
                  alignment: Alignment.centerRight,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    style: TextStyle(
                      fontSize: _displayFontSize,
                      fontWeight: FontWeight.w300,
                      color: cs.onSurface,
                      letterSpacing: -1.5,
                    ),
                    child: Text(
                      _formattedDisplay,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // ── Button grid ────────────────────────────────────────────────────
        Container(
          color: cs.surfaceContainer,
          padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPad + 24),
          child: _ButtonGrid(
            scheme: cs,
            activeOperator: _activeOperator,
            hasInput: _display != '0' || _expression.isNotEmpty,
            justEvaluated: _justEvaluated,
            onDigit: _onDigit,
            onDecimal: _onDecimal,
            onOperator: _onOperator,
            onEquals: _onEquals,
            onClear: _onClear,
            onToggleSign: _onToggleSign,
            onPercent: _onPercent,
            onBackspace: _onBackspace,
          ),
        ),
      ],
    );
  }
}

// ── Button grid ───────────────────────────────────────────────────────────────

class _ButtonGrid extends StatelessWidget {
  final ColorScheme scheme;
  final String? activeOperator;
  final bool hasInput;
  final bool justEvaluated;
  final void Function(String) onDigit;
  final VoidCallback onDecimal;
  final void Function(String) onOperator;
  final VoidCallback onEquals;
  final VoidCallback onClear;
  final VoidCallback onToggleSign;
  final VoidCallback onPercent;
  final VoidCallback onBackspace;

  const _ButtonGrid({
    required this.scheme,
    required this.activeOperator,
    required this.hasInput,
    required this.justEvaluated,
    required this.onDigit,
    required this.onDecimal,
    required this.onOperator,
    required this.onEquals,
    required this.onClear,
    required this.onToggleSign,
    required this.onPercent,
    required this.onBackspace,
  });

  Color get _funcBg => scheme.secondaryContainer;
  Color get _funcFg => scheme.onSecondaryContainer;

  Color get _opBg => scheme.primaryContainer;
  Color get _opFg => scheme.onPrimaryContainer;
  Color get _opActiveBg => scheme.primary;
  Color get _opActiveFg => scheme.onPrimary;

  Color get _numBg => scheme.surfaceContainerHigh;
  Color get _numFg => scheme.onSurface;

  Color get _equalsBg => scheme.primary;
  Color get _equalsFg => scheme.onPrimary;

  @override
  Widget build(BuildContext context) {
    const gap = 13.0;

    final rows = [
      [
        _Btn(hasInput && !justEvaluated ? '⌫' : 'AC', _BK.func),
        _Btn('+/−', _BK.func),
        _Btn('%', _BK.func),
        _Btn('÷', _BK.op),
      ],
      [
        _Btn('7', _BK.num),
        _Btn('8', _BK.num),
        _Btn('9', _BK.num),
        _Btn('×', _BK.op),
      ],
      [
        _Btn('4', _BK.num),
        _Btn('5', _BK.num),
        _Btn('6', _BK.num),
        _Btn('−', _BK.op),
      ],
      [
        _Btn('1', _BK.num),
        _Btn('2', _BK.num),
        _Btn('3', _BK.num),
        _Btn('+', _BK.op),
      ],
      [
        _Btn('0', _BK.numWide),
        _Btn('.', _BK.num),
        _Btn('=', _BK.eq),
      ],
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final btnSize = (constraints.maxWidth - gap * 3) / 4;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(
              children: row.map((btn) {
                final isWide = btn.kind == _BK.numWide;
                final w = isWide ? btnSize * 2 + gap : btnSize;
                final isActiveOp =
                    btn.kind == _BK.op && activeOperator == btn.label;

                Color bg;
                Color fg;
                switch (btn.kind) {
                  case _BK.func:
                    bg = _funcBg;
                    fg = _funcFg;
                    break;
                  case _BK.op:
                    bg = isActiveOp ? _opActiveBg : _opBg;
                    fg = isActiveOp ? _opActiveFg : _opFg;
                    break;
                  case _BK.eq:
                    bg = _equalsBg;
                    fg = _equalsFg;
                    break;
                  case _BK.num:
                  case _BK.numWide:
                    bg = _numBg;
                    fg = _numFg;
                    break;
                }

                return Padding(
                  padding: EdgeInsets.only(right: btn == row.last ? 0 : gap),
                  child: _CalcButton(
                    label: btn.label,
                    width: w,
                    height: btnSize,
                    bgColor: bg,
                    fgColor: fg,
                    isWide: isWide,
                    onTap: () => _handle(btn.label),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      );
    });
  }

  void _handle(String label) {
    switch (label) {
      case 'AC':
        onClear();
        break;
      case '⌫':
        onBackspace();
        break;
      case '+/−':
        onToggleSign();
        break;
      case '%':
        onPercent();
        break;
      case '.':
        onDecimal();
        break;
      case '=':
        onEquals();
        break;
      case '+':
      case '−':
      case '×':
      case '÷':
        onOperator(label);
        break;
      default:
        onDigit(label);
    }
  }
}

enum _BK { func, op, eq, num, numWide }

class _Btn {
  final String label;
  final _BK kind;
  const _Btn(this.label, this.kind);
}

// ── Individual button ─────────────────────────────────────────────────────────

/// Squircle border — Flutter's [ContinuousRectangleBorder] uses a
/// superellipse with a curviness factor.  A factor of ~2.5–3 gives the
/// classic "squircle" look (iOS-style, tighter corners than a rounded rect).
// ignore: unused_element
class _SquircleBorder extends ContinuousRectangleBorder {
  // ignore: unused_element_parameter
  const _SquircleBorder({super.borderRadius});
}

class _CalcButton extends StatefulWidget {
  final String label;
  final double width;
  final double height;
  final Color bgColor;
  final Color fgColor;
  final bool isWide;
  final VoidCallback onTap;

  const _CalcButton({
    required this.label,
    required this.width,
    required this.height,
    required this.bgColor,
    required this.fgColor,
    required this.isWide,
    required this.onTap,
  });

  @override
  State<_CalcButton> createState() => _CalcButtonState();
}

class _CalcButtonState extends State<_CalcButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  // Darken on press
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 70),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.91).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(_) {
    setState(() => _pressed = true);
    _ctrl.forward();
  }

  void _up(_) {
    setState(() => _pressed = false);
    _ctrl.reverse();
    widget.onTap();
  }

  void _cancel() {
    setState(() => _pressed = false);
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isBackspace = widget.label == '⌫';
    final isSymbol =
        !RegExp(r'^\d$').hasMatch(widget.label) && widget.label != '.';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Squircle radius — roughly 36% of the shorter dimension
    final radius = widget.height * 0.36;

    // Shadow intensity mirrors the accounts_page pattern:
    // stronger in dark mode to lift buttons off the dark surface,
    // lighter in light mode where surface contrast already separates them.
    final shadowAlpha1 = isDark ? 0.32 : 0.10;
    final shadowAlpha2 = isDark ? 0.16 : 0.04;

    // Slightly darken bg when pressed for tactile feel
    final effectiveBg = _pressed
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.06), widget.bgColor)
        : widget.bgColor;

    return GestureDetector(
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: widget.width,
          height: widget.height,
          decoration: ShapeDecoration(
            color: effectiveBg,
            shape: ContinuousRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            // Subtle shadow for depth — scales with dark/light mode
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: shadowAlpha1),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: shadowAlpha2),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          alignment: widget.isWide ? Alignment.centerLeft : Alignment.center,
          padding: widget.isWide
              ? EdgeInsets.only(left: widget.height * 0.38)
              : EdgeInsets.zero,
          child: isBackspace
              ? Icon(
                  Icons.backspace_outlined,
                  color: widget.fgColor,
                  size: widget.height * 0.36,
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    fontSize:
                        isSymbol ? widget.height * 0.38 : widget.height * 0.42,
                    fontWeight: isSymbol ? FontWeight.w500 : FontWeight.w400,
                    color: widget.fgColor,
                    height: 1,
                  ),
                ),
        ),
      ),
    );
  }
}
