import 'dart:convert';
import 'dart:math' show Random;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/screens/settings.dart' show AppSettings;
import '../core/themes.dart';

// ------------------------------------------------------------------
// Security methods
// ------------------------------------------------------------------

/// Touch ID / Face ID use the phone's biometrics. PIN is Momentum's own PIN.
/// PIN is last so it is listed under the biometric methods.
enum SecurityMethod {
  touch('Touch ID', Icons.fingerprint),
  face('Face ID', Icons.face_outlined),
  pin('PIN', Icons.pin_outlined);

  final String label;
  final IconData icon;
  const SecurityMethod(this.label, this.icon);
}

class AppSecurity {
  AppSecurity._();
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Biometric methods this phone really has (PIN is always available).
  static Future<List<SecurityMethod>> available() async {
    try {
      if (!await _auth.isDeviceSupported()) return const [];
      final types = await _auth.getAvailableBiometrics();
      final face = types.contains(BiometricType.face);
      final finger =
          types.contains(BiometricType.fingerprint) ||
          (!face &&
              (types.contains(BiometricType.strong) ||
                  types.contains(BiometricType.weak)));
      return [
        if (finger) SecurityMethod.touch,
        if (face) SecurityMethod.face,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// [biometricOnly] false also accepts the phone's own screen lock.
  static Future<bool> authenticate(
    String reason, {
    bool biometricOnly = true,
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  // ---- App PIN (salted hash, kept in SharedPreferences, not in backups) ----

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final random = Random.secure();
    final salt = base64Url.encode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    await prefs.setString(AppConstants.prefSecurityPinSalt, salt);
    await prefs.setString(AppConstants.prefSecurityPinHash, _hash(pin, salt));
    await prefs.setInt(AppConstants.prefSecurityPinLength, pin.length);
  }

  /// null = unknown (a PIN saved by an older version).
  static Future<int?> pinLength() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(AppConstants.prefSecurityPinLength);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> verifyPin(String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final salt = prefs.getString(AppConstants.prefSecurityPinSalt);
      final hash = prefs.getString(AppConstants.prefSecurityPinHash);
      if (salt == null || hash == null) return false;
      return _hash(pin, salt) == hash;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearPin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.prefSecurityPinSalt);
      await prefs.remove(AppConstants.prefSecurityPinHash);
      await prefs.remove(AppConstants.prefSecurityPinLength);
    } catch (_) {}
  }
}

// ------------------------------------------------------------------
// Lock gate
// ------------------------------------------------------------------

/// Wraps the whole app (see main.dart). Shows the lock screen on start and
/// when the app comes back after [AppConstants.lockAfterBackground].
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _settings = AppSettings.instance;
  bool _locked = false;
  bool _busy = false;
  bool _failed = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings.addListener(_onSettings);
    if (_settings.securityEnabled) {
      _locked = true;
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onSettings() {
    if (!_settings.securityEnabled && _locked && mounted) {
      setState(() => _locked = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_settings.securityEnabled || _busy) return;
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (!_locked &&
          left != null &&
          DateTime.now().difference(left) >= AppConstants.lockAfterBackground) {
        setState(() => _locked = true);
      }
    }
  }

  /// Biometric methods that are turned on (the PIN is always typed).
  List<SecurityMethod> get _methods {
    final on = _settings.securityMethods;
    return [
      for (final m in SecurityMethod.values)
        if (m != SecurityMethod.pin && on.contains(m)) m,
    ];
  }

  SecurityMethod get _primary {
    final on = _settings.securityMethods;
    if (on.contains(SecurityMethod.face)) return SecurityMethod.face;
    if (on.contains(SecurityMethod.touch)) return SecurityMethod.touch;
    return SecurityMethod.pin;
  }

  Future<void> _unlock([SecurityMethod? method]) async {
    if (_busy || !mounted) return;
    final m = method ?? _primary;
    if (m == SecurityMethod.pin) return; // the PIN is typed on the lock screen
    _busy = true;
    final ok = await AppSecurity.authenticate('Unlock Momentum'.tr);
    _busy = false;
    if (!mounted) return;
    setState(() {
      _failed = !ok;
      if (ok) {
        _locked = false;
        _leftAt = null;
      }
    });
  }

  Future<bool> _submitPin(String pin) async {
    final ok = await AppSecurity.verifyPin(pin);
    if (ok && mounted) {
      setState(() {
        _locked = false;
        _failed = false;
        _leftAt = null;
      });
    }
    return ok;
  }

  /// Safety net: the phone's own screen lock removes the PIN and the app
  /// lock, so a forgotten PIN never locks the person out for good.
  Future<void> _forgotPin() async {
    if (_busy || !mounted) return;
    _busy = true;
    final ok = await AppSecurity.authenticate(
      'Verify it\'s you to reset your PIN.',
      biometricOnly: false,
    );
    _busy = false;
    if (!ok || !mounted) return;
    await AppSecurity.clearPin();
    await _settings.setSecurity(enabled: false, methods: {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_locked,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_locked)
            Positioned.fill(
              child: _LockScreen(
                methods: _methods,
                failed: _failed,
                onBiometric: _unlock,
                onPin: _submitPin,
                onForgot: _forgotPin,
              ),
            ),
        ],
      ),
    );
  }
}

class _LockScreen extends StatefulWidget {
  final List<SecurityMethod> methods; // biometric methods that are on
  final bool failed; // kept for the gate; the screen just says "Enter PIN"
  final ValueChanged<SecurityMethod> onBiometric;
  final Future<bool> Function(String pin) onPin;
  final VoidCallback onForgot;
  const _LockScreen({
    required this.methods,
    required this.failed,
    required this.onBiometric,
    required this.onPin,
    required this.onForgot,
  });

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  static const double _key = 72;
  static const double _gap = 16;

  String _pin = '';
  int? _length; // saved PIN length (null = unknown)
  String? _error;
  int _attempts = 0;
  DateTime? _until;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    AppSecurity.pinLength().then((v) {
      if (mounted) setState(() => _length = v);
    });
  }

  int get _slots => _length ?? AppConstants.pinMaxLength;

  SecurityMethod? get _biometric {
    if (widget.methods.contains(SecurityMethod.face)) return SecurityMethod.face;
    if (widget.methods.contains(SecurityMethod.touch)) {
      return SecurityMethod.touch;
    }
    return null;
  }

  bool get _lockedOut => _until != null && _until!.isAfter(DateTime.now());

  void _digit(String d) {
    if (_checking || _pin.length >= AppConstants.pinMaxLength) return;
    if (_lockedOut) {
      final wait = _until!.difference(DateTime.now()).inSeconds + 1;
      setState(() => _error = 'Too many tries. Wait ${wait}s.');
      return;
    }
    setState(() {
      _pin += d;
      _error = null;
    });
    final len = _pin.length;
    final target = _length;
    final shouldCheck = target != null
        ? len == target
        : len >= AppConstants.pinMinLength;
    if (shouldCheck) {
      // Unknown length: only a full-length miss counts as a wrong try.
      _check(silent: target == null && len < AppConstants.pinMaxLength);
    }
  }

  Future<void> _check({required bool silent}) async {
    _checking = true;
    final ok = await widget.onPin(_pin);
    _checking = false;
    if (!mounted || ok || silent) return;
    _attempts++;
    setState(() {
      _pin = '';
      if (_attempts % 5 == 0) {
        _until = DateTime.now().add(const Duration(seconds: 30));
        _error = 'Too many tries. Wait 30s.';
      } else {
        _error = 'Wrong PIN. Try again.';
      }
    });
  }

  void _delete() {
    if (_pin.isEmpty || _checking) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  void _clear() {
    if (_checking) return;
    setState(() {
      _pin = '';
      _error = null;
    });
  }

  Widget _dots(Color fg) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _slots; i++)
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _pin.length ? fg : Colors.transparent,
              border: Border.all(
                color: fg.withValues(alpha: AppConstants.borderAlpha),
                width: 1.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _numKey(String d, Color bg, Color fg) => _round(
    bg: bg,
    onTap: () => _digit(d),
    child: Text(
      d,
      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: fg),
    ),
  );

  Widget _round({
    required Color bg,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required Widget child,
  }) {
    return SizedBox(
      width: _key,
      height: _key,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _row(List<Widget> keys) => Padding(
    padding: const EdgeInsets.only(bottom: _gap),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap + 8),
          keys[i],
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppTheme.accentOf(context);
    final fg = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    final keyBg = accent.background;
    final keyFg = accent.foreground;
    final bio = _biometric;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spaceLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: accent.background,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_outline, size: 34, color: keyFg),
                ),
                const SizedBox(height: AppConstants.spaceMd),
                Text(
                  'Momentum is locked'.tr,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppConstants.spaceXs),
                Text(
                  _error ?? 'Enter PIN',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: AppConstants.spaceMd),
                _dots(fg),
                const SizedBox(height: AppConstants.spaceLg),
                _row([for (final d in ['1', '2', '3']) _numKey(d, keyBg, keyFg)]),
                _row([for (final d in ['4', '5', '6']) _numKey(d, keyBg, keyFg)]),
                _row([for (final d in ['7', '8', '9']) _numKey(d, keyBg, keyFg)]),
                _row([
                  // Fingerprint / face key (empty when no biometric is on)
                  bio == null
                      ? const SizedBox(width: _key, height: _key)
                      : _round(
                          bg: Colors.transparent,
                          onTap: () => widget.onBiometric(bio),
                          child: Icon(bio.icon, size: 32, color: fg),
                        ),
                  _numKey('0', keyBg, keyFg),
                  // Delete: tap = one digit, hold = clear all
                  _round(
                    bg: Colors.transparent,
                    onTap: _delete,
                    onLongPress: _clear,
                    child: Icon(Icons.backspace_outlined, size: 28, color: fg),
                  ),
                ]),
                TextButton(
                  onPressed: widget.onForgot,
                  child: const Text('Forgot PIN?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}