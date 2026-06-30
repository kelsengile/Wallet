import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/security_service.dart';

/// Full-screen gate shown when app lock is enabled. Tries biometrics first
/// (if the user opted in and the device supports it), then falls back to a
/// 6-digit PIN pad. Pops `true` via [onUnlocked] once the user is verified.
///
/// Strictly monochrome (black/white) regardless of the app's theme, since
/// this screen should feel like a distinct, deliberate "vault" moment.
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  final List<int> _entered = [];
  String? _error;
  bool _checking = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shake;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shake = CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometricFirst());
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _tryBiometricFirst() async {
    final biometricsOn = await SecurityService.instance.isBiometricEnabled();
    if (!biometricsOn || !mounted) return;
    final ok = await SecurityService.instance.authenticateWithBiometrics();
    if (ok && mounted) {
      widget.onUnlocked();
    }
  }

  void _onDigit(int d) {
    if (_checking || _entered.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered.add(d);
      _error = null;
    });
    if (_entered.length == 6) _submit();
  }

  void _onBackspace() {
    if (_checking || _entered.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _entered.removeLast());
  }

  Future<void> _submit() async {
    setState(() => _checking = true);
    final pin = _entered.join();
    final ok = await SecurityService.instance.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    HapticFeedback.heavyImpact();
    _shakeController.forward(from: 0);
    setState(() {
      _checking = false;
      _error = 'Incorrect PIN';
      _entered.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Strictly monochrome regardless of the app's accent colors, but the
    // polarity flips with system/app brightness: dark mode = black canvas
    // with white icons, light mode = white canvas with black icons.
    final bg = isDark ? Colors.black : Colors.white;
    final fg = isDark ? Colors.white : Colors.black;
    final muted = isDark ? const Color(0xFF8A8A8E) : const Color(0xFF6E6E73);
    final dim = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE0E0E0);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 3),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: fg, width: 1.5),
              ),
              child: Icon(Icons.lock_outline, size: 30, color: fg),
            ),
            const SizedBox(height: 28),
            Text(
              'Enter PIN',
              style: TextStyle(
                color: fg,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 28),
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) {
                final offset = (_shake.value == 0 || _shake.value == 1)
                    ? 0.0
                    : (1 - _shake.value) *
                        8 *
                        ((_shakeController.value * 30).floor().isEven ? 1 : -1);
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: _PinDots(
                  filled: _entered.length, hasError: _error != null, fg: fg),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 20,
              child: AnimatedOpacity(
                opacity: _error != null ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Text(
                  _error ?? '',
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            const Spacer(flex: 2),
            _Keypad(
              fg: fg,
              dim: dim,
              muted: muted,
              onDigit: _onDigit,
              onBackspace: _onBackspace,
              onBiometric: () async {
                final ok =
                    await SecurityService.instance.authenticateWithBiometrics();
                if (ok && mounted) widget.onUnlocked();
              },
              showBiometric: true,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// Redesigned PIN indicator: a row of hollow circles that fill solid white
/// as digits are entered, with a slightly larger ring marking the active
/// (next-to-fill) position. Stays strictly black & white.
class _PinDots extends StatelessWidget {
  final int filled;
  final bool hasError;
  final Color fg;

  const _PinDots(
      {required this.filled, required this.hasError, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final isFilled = i < filled;
        final isActive = i == filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: isActive ? 14 : 12,
          height: isActive ? 14 : 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? fg : Colors.transparent,
            border: Border.all(
              color: fg.withOpacity(isFilled ? 1 : 0.45),
              width: 1.4,
            ),
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  final Color fg;
  final Color dim;
  final Color muted;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onBiometric;
  final bool showBiometric;

  const _Keypad({
    required this.fg,
    required this.dim,
    required this.muted,
    required this.onDigit,
    required this.onBackspace,
    required this.onBiometric,
    required this.showBiometric,
  });

  Widget _key(BuildContext context,
      {String? label, Widget? icon, VoidCallback? onTap}) {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1.15,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              splashColor: fg.withOpacity(0.12),
              highlightColor: fg.withOpacity(0.06),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: dim, width: 1),
                ),
                child: Center(
                  child: icon ??
                      Text(
                        label ?? '',
                        style: TextStyle(
                          color: fg,
                          fontSize: 26,
                          fontWeight: FontWeight.w400,
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

  Widget _emptySlot() => const Expanded(child: SizedBox.shrink());

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
        showBiometric
            ? _key(
                context,
                icon: Icon(Icons.fingerprint, color: fg, size: 26),
                onTap: onBiometric,
              )
            : _emptySlot(),
        _key(context, label: '0', onTap: () => onDigit(0)),
        _key(
          context,
          icon: Icon(Icons.backspace_outlined, color: muted, size: 22),
          onTap: onBackspace,
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: rows.map((r) => Row(children: r)).toList(),
      ),
    );
  }
}
