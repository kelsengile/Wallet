import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import '../database/database_helper.dart';

/// Handles the app-lock feature: a toggle that protects the app behind
/// either device biometrics (fingerprint/face) or a 6-digit PIN.
///
/// Persistence piggybacks on the same generic `settings` key/value table
/// already used for things like dark mode (see [DatabaseHelper.getSetting]
/// / [DatabaseHelper.saveSetting]), so no schema changes are required.
class SecurityService {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  static const _kLockEnabledKey = 'app_lock_enabled';
  static const _kPinHashKey = 'app_lock_pin_hash';
  static const _kPinSaltKey = 'app_lock_pin_salt';
  static const _kBiometricEnabledKey = 'app_lock_biometric_enabled';

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Whether app lock is currently turned on.
  Future<bool> isLockEnabled() async {
    final v = await DatabaseHelper.instance.getSetting(_kLockEnabledKey);
    return v == 'true';
  }

  /// Whether the user opted to also allow biometrics (in addition to PIN
  /// fallback) once app lock is enabled.
  Future<bool> isBiometricEnabled() async {
    final v = await DatabaseHelper.instance.getSetting(_kBiometricEnabledKey);
    return v == 'true';
  }

  Future<bool> hasPinSet() async {
    final v = await DatabaseHelper.instance.getSetting(_kPinHashKey);
    return v != null && v.isNotEmpty;
  }

  /// Returns true if this device exposes usable biometric hardware
  /// (fingerprint, face, etc.) with at least one enrolled credential.
  Future<bool> isBiometricAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supported || !canCheck) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Sets (or replaces) the 6-digit PIN. Stores only a salted hash, never
  /// the raw PIN.
  Future<void> setPin(String pin) async {
    assert(RegExp(r'^\d{6}$').hasMatch(pin), 'PIN must be exactly 6 digits');
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);
    await DatabaseHelper.instance.saveSetting(_kPinSaltKey, salt);
    await DatabaseHelper.instance.saveSetting(_kPinHashKey, hash);
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await DatabaseHelper.instance.getSetting(_kPinSaltKey);
    final storedHash = await DatabaseHelper.instance.getSetting(_kPinHashKey);
    if (salt == null || storedHash == null) return false;
    final hash = _hashPin(pin, salt);
    return hash == storedHash;
  }

  /// Enables app lock. Requires a PIN to already be set as the fallback;
  /// biometrics are an optional add-on, never a replacement, so a forgotten
  /// or unenrolled biometric never locks the user out permanently.
  Future<void> enableLock({required bool useBiometrics}) async {
    await DatabaseHelper.instance.saveSetting(_kLockEnabledKey, 'true');
    await DatabaseHelper.instance
        .saveSetting(_kBiometricEnabledKey, useBiometrics.toString());
  }

  Future<void> disableLock() async {
    await DatabaseHelper.instance.saveSetting(_kLockEnabledKey, 'false');
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await DatabaseHelper.instance
        .saveSetting(_kBiometricEnabledKey, enabled.toString());
  }

  /// Clears any stored PIN. Call when the user turns app lock fully off so
  /// stale credentials don't linger.
  Future<void> clearPin() async {
    await DatabaseHelper.instance.saveSetting(_kPinHashKey, '');
    await DatabaseHelper.instance.saveSetting(_kPinSaltKey, '');
  }

  /// Prompts the OS biometric sheet. Returns false (rather than throwing) on
  /// any platform exception, e.g. no biometrics enrolled or hardware busy,
  /// so callers can gracefully fall back to the PIN entry UI.
  Future<bool> authenticateWithBiometrics({
    String reason = 'Authenticate to unlock Wallet',
  }) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  String _generateSalt([int length = 16]) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }
}
