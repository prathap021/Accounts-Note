import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/result.dart';
import '../data/repositories/auth_repository.dart';
import 'sync_provider.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// The single source of truth for "is anyone signed in". GoRouter's
/// redirect logic listens to this to decide Splash -> Login -> Dashboard.
final authStateProvider = StreamProvider<fb.User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).asData?.value?.uid;
});

/// Holds transient UI state (loading / error) for auth actions so screens
/// don't manage their own booleans and can just watch this notifier.
/// True while an email/password account still has an unverified address.
///
/// Google and Apple accounts are never gated: those providers verify the
/// address themselves.
final needsEmailVerificationProvider = Provider<bool>((ref) {
  final user = ref.watch(authStateProvider).asData?.value;
  return AuthRepository.requiresEmailVerification(user);
});

/// The address the verification link was sent to, for display.
final pendingVerificationEmailProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).asData?.value?.email;
});

class AuthActionsNotifier extends Notifier<AsyncValue<void>> {
  late AuthRepository _repo;

  @override
  AsyncValue<void> build() {
    _repo = ref.watch(authRepositoryProvider);
    return const AsyncData(null);
  }

  Future<void> _run(Future<Result<void>> Function() action) async {
    state = const AsyncLoading();
    final result = await action();
    result.when(
      success: (_) => state = const AsyncData(null),
      failure: (f) => state = AsyncError(f, StackTrace.current),
    );
  }

  Future<void> signInWithGoogle() => _run(() async {
        final r = await _repo.signInWithGoogle();
        return r.when(
          success: (_) => Result.success(null),
          failure: (f) => Result.failure(f),
        );
      });

  Future<void> signInWithApple() => _run(() async {
        final r = await _repo.signInWithApple();
        return r.when(
          success: (_) => Result.success(null),
          failure: (f) => Result.failure(f),
        );
      });

  Future<void> signInWithEmail(String email, String password) => _run(() async {
        final r = await _repo.signInWithEmail(email, password);
        return r.when(
          success: (_) => Result.success(null),
          failure: (f) => Result.failure(f),
        );
      });

  Future<void> signUpWithEmail(String email, String password) => _run(() async {
        final r = await _repo.signUpWithEmail(email, password);
        return r.when(
          success: (_) => Result.success(null),
          failure: (f) => Result.failure(f),
        );
      });

  /// True when a link has already gone out for this account this session, so
  /// the verification screen does not send a duplicate.
  bool hasSentVerificationFor(String uid) => _repo.hasSentVerificationFor(uid);

  Future<Result<void>> sendEmailVerification() async {
    state = const AsyncLoading();
    final result = await _repo.sendEmailVerification();
    result.when(
      success: (_) => state = const AsyncData(null),
      failure: (f) => state = AsyncError(f, StackTrace.current),
    );
    return result;
  }

  /// Returns true once Firebase reports the address as verified.
  Future<bool> refreshEmailVerification() async {
    final result = await _repo.refreshEmailVerification();
    return result.when(success: (verified) => verified, failure: (_) => false);
  }

  Future<void> sendPasswordReset(String email) =>
      _run(() => _repo.sendPasswordReset(email));

  /// Result-returning variant so the reset sheet can report back to the user
  /// instead of failing silently.
  Future<Result<void>> requestPasswordReset(String email) async {
    state = const AsyncLoading();
    final result = await _repo.sendPasswordReset(email);
    result.when(
      success: (_) => state = const AsyncData(null),
      failure: (f) => state = AsyncError(f, StackTrace.current),
    );
    return result;
  }

  Future<Result<void>> updateDisplayName(String name) async {
    state = const AsyncLoading();
    final result = await _repo.updateDisplayName(name);
    result.when(
      success: (_) => state = const AsyncData(null),
      failure: (f) => state = AsyncError(f, StackTrace.current),
    );
    return result;
  }

  Future<Result<void>> updateProfilePhoto(File imageFile) async {
    state = const AsyncLoading();
    final result = await _repo.updateProfilePhoto(imageFile);
    result.when(
      success: (_) => state = const AsyncData(null),
      failure: (f) => state = AsyncError(f, StackTrace.current),
    );
    return result;
  }

  Future<void> signOut() => _run(() async {
        // Flush anything still queued before the box closes, so a sign-out
        // does not strand the user's last few entries on the device.
        final sync = ref.read(syncManagerProvider);
        if (await sync.isOnline()) {
          await sync.syncNow();
        }
        await sync.stop();
        // Wipe the local ledger: the next account must not see this one's.
        await ref.read(transactionLocalStoreProvider).clear();
        await _repo.signOut();
        return Result.success(null);
      });

  Future<Result<void>> deleteAccount() async {
    state = const AsyncLoading();
    // Stop syncing so nothing re-uploads mid-delete, but keep the local ledger
    // until the delete actually succeeds — if it fails the user still has an
    // account, and wiping their data first would strand them with an empty one.
    await ref.read(syncManagerProvider).stop();

    final result = await _repo.deleteAccount();
    await result.when(
      success: (_) async {
        await ref.read(transactionLocalStoreProvider).clear();
        state = const AsyncData(null);
      },
      failure: (f) async {
        // Deletion did not happen: resume syncing so the account keeps working.
        await ref.read(syncManagerProvider).start();
        state = AsyncError(f, StackTrace.current);
      },
    );
    return result;
  }
}

final authActionsProvider =
    NotifierProvider<AuthActionsNotifier, AsyncValue<void>>(
  AuthActionsNotifier.new,
);
