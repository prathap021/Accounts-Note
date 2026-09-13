import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/result.dart';
import '../data/repositories/auth_repository.dart';

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

  Future<void> sendPasswordReset(String email) =>
      _run(() => _repo.sendPasswordReset(email));

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
        await _repo.signOut();
        return Result.success(null);
      });

  Future<void> deleteAccount() => _run(() => _repo.deleteAccount());
}

final authActionsProvider =
    NotifierProvider<AuthActionsNotifier, AsyncValue<void>>(
  AuthActionsNotifier.new,
);
