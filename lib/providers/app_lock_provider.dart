import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'settings_provider.dart';

/// The phone's fingerprint / face unlock, behind an interface for tests.
abstract class BiometricUnlock {
  Future<bool> isAvailable();
  Future<bool> authenticate();
}

class DeviceBiometricUnlock implements BiometricUnlock {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Accounts Note',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('Biometric unlock failed: $e');
      return false;
    }
  }
}

final biometricUnlockProvider = Provider<BiometricUnlock>((ref) {
  return DeviceBiometricUnlock();
});

@immutable
class AppLockState {
  /// A PIN has been set: the app locks on open.
  final bool enabled;
  final bool biometrics;

  /// The lock screen is up.
  final bool locked;

  /// Wrong PINs in a row; five lock the keypad for [lockoutSeconds].
  final int failures;
  final DateTime? lockedOutUntil;

  const AppLockState({
    this.enabled = false,
    this.biometrics = false,
    this.locked = false,
    this.failures = 0,
    this.lockedOutUntil,
  });

  AppLockState copyWith({
    bool? enabled,
    bool? biometrics,
    bool? locked,
    int? failures,
    DateTime? lockedOutUntil,
    bool clearLockout = false,
  }) => AppLockState(
    enabled: enabled ?? this.enabled,
    biometrics: biometrics ?? this.biometrics,
    locked: locked ?? this.locked,
    failures: failures ?? this.failures,
    lockedOutUntil: clearLockout
        ? null
        : (lockedOutUntil ?? this.lockedOutUntil),
  );
}

/// PIN and fingerprint lock.
///
/// The PIN is stored only as a salted, stretched SHA-256 hash. It locks the
/// app's screens; the data itself is protected by the account sign-in and
/// the server's rules, and "Forgot PIN" is a sign-out (signing back in
/// proves who you are).
class AppLockNotifier extends Notifier<AppLockState> {
  static const _hashKey = 'lock_pin_hash';
  static const _saltKey = 'lock_pin_salt';
  static const _bioKey = 'lock_biometrics';
  static const maxFailures = 5;
  static const lockoutSeconds = 30;

  /// Back from the background after this long, the app locks again.
  static const relockAfter = Duration(seconds: 30);

  DateTime? _backgroundedAt;

  @override
  AppLockState build() {
    final p = ref.watch(sharedPreferencesProvider);
    final enabled = p.getString(_hashKey) != null;
    return AppLockState(
      enabled: enabled,
      biometrics: enabled && (p.getBool(_bioKey) ?? false),
      // Every launch starts locked.
      locked: enabled,
    );
  }

  static String _hash(String pin, String salt) {
    var digest = utf8.encode('$salt:$pin');
    for (var i = 0; i < 10000; i++) {
      digest = Uint8List.fromList(sha256.convert(digest).bytes);
    }
    return base64Encode(digest);
  }

  static bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  Future<void> setPin(String pin) async {
    assert(isValidPin(pin));
    final random = Random.secure();
    final salt = base64Encode(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final p = ref.read(sharedPreferencesProvider);
    await p.setString(_saltKey, salt);
    await p.setString(_hashKey, _hash(pin, salt));
    state = state.copyWith(enabled: true, locked: false, failures: 0);
  }

  bool _matches(String pin) {
    final p = ref.read(sharedPreferencesProvider);
    final salt = p.getString(_saltKey);
    final hash = p.getString(_hashKey);
    return salt != null && hash != null && _hash(pin, salt) == hash;
  }

  /// Unlocks with [pin]. False, and counts a failure, when it is wrong or
  /// the keypad is in its cool-down.
  bool unlock(String pin, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final until = state.lockedOutUntil;
    if (until != null && at.isBefore(until)) return false;
    if (_matches(pin)) {
      state = state.copyWith(locked: false, failures: 0, clearLockout: true);
      return true;
    }
    final failures = state.failures + 1;
    state = state.copyWith(
      failures: failures >= maxFailures ? 0 : failures,
      lockedOutUntil: failures >= maxFailures
          ? at.add(const Duration(seconds: lockoutSeconds))
          : null,
      clearLockout: failures < maxFailures,
    );
    return false;
  }

  Future<bool> unlockWithBiometrics() async {
    if (!state.biometrics) return false;
    final ok = await ref.read(biometricUnlockProvider).authenticate();
    if (ok) {
      state = state.copyWith(locked: false, failures: 0, clearLockout: true);
    }
    return ok;
  }

  /// Turning on asks for a fingerprint first, so it is known to work.
  Future<bool> setBiometrics(bool on) async {
    if (on) {
      final bio = ref.read(biometricUnlockProvider);
      if (!await bio.isAvailable() || !await bio.authenticate()) return false;
    }
    await ref.read(sharedPreferencesProvider).setBool(_bioKey, on);
    state = state.copyWith(biometrics: on);
    return on;
  }

  /// Turns the lock off (needs the current PIN, checked by the caller).
  Future<void> disable() async {
    final p = ref.read(sharedPreferencesProvider);
    await p.remove(_hashKey);
    await p.remove(_saltKey);
    await p.remove(_bioKey);
    state = const AppLockState();
  }

  bool checkPin(String pin) => _matches(pin);

  void appBackgrounded() => _backgroundedAt = DateTime.now();

  void appResumed({DateTime? now}) {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (!state.enabled || since == null) return;
    if ((now ?? DateTime.now()).difference(since) >= relockAfter) {
      state = state.copyWith(locked: true);
    }
  }
}

final appLockProvider = NotifierProvider<AppLockNotifier, AppLockState>(
  AppLockNotifier.new,
);
