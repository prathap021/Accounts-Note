import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as cf;
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';
import '../../models/app_user_model.dart';

/// Wraps FirebaseAuth + platform-native sign-in SDKs behind one clean API.
/// The UI/state layer never touches FirebaseAuth or GoogleSignIn directly.
class AuthRepository {
  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final cf.FirebaseFunctions? _functionsOverride;
  Future<void>? _googleSignInReady;

  AuthRepository({
    fb.FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    cf.FirebaseFunctions? functions,
  })  : _auth = auth ?? fb.FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _functionsOverride = functions;

  /// Resolved lazily: creating it eagerly would make merely constructing this
  /// repository require an initialized Firebase app. Same region as the other
  /// callables in this project.
  cf.FirebaseFunctions get _functions =>
      _functionsOverride ??
      cf.FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Prefer [userChanges] so displayName / photoURL updates refresh the UI.
  Stream<fb.User?> authStateChanges() => _auth.userChanges();

  fb.User? get currentUser => _auth.currentUser;

  /// google_sign_in 7.x requires a one-time [GoogleSignIn.initialize] before
  /// [GoogleSignIn.authenticate]. On Android, a web OAuth client
  /// (`client_type: 3`) must exist in `google-services.json` so the plugin
  /// can resolve `serverClientId` automatically.
  Future<void> _ensureGoogleSignInInitialized() {
    return _googleSignInReady ??= GoogleSignIn.instance.initialize();
  }

  /// Google Sign-In (primary flow on Android/iOS).
  /// Uses the singleton GoogleSignIn.instance from google_sign_in 7.x.
  Future<Result<fb.User>> signInWithGoogle() async {
    try {
      await _ensureGoogleSignInInitialized();
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        return Result.failure(
          const AppFailure(
            'Google Sign-In did not return an ID token. Add your SHA-1/SHA-256 '
            'in Firebase, enable Google sign-in, then re-download '
            'google-services.json (oauth_client must include a web client).',
            code: 'missing-id-token',
          ),
        );
      }
      // Access token is optional for Firebase Auth; ID token is required.
      final authz = await googleUser.authorizationClient
          .authorizationForScopes(['email', 'profile']);
      final credential = fb.GoogleAuthProvider.credential(
        accessToken: authz?.accessToken,
        idToken: idToken,
      );
      final userCred = await _auth.signInWithCredential(credential);
      await _ensureUserDocument(userCred.user!);
      return Result.success(userCred.user!);
    } on GoogleSignInException catch (e) {
      return Result.failure(AppFailure(_mapGoogleSignInError(e), code: e.code.name));
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(AppFailure(_mapAuthError(e), code: e.code));
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Sign in with Apple (required on iOS by App Store guidelines whenever
  /// another third-party login, like Google, is offered).
  Future<Result<fb.User>> signInWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final oauthCredential = fb.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final userCred = await _auth.signInWithCredential(oauthCredential);

      // Apple only returns the name on first sign-in; persist it then.
      final displayName = [
        appleCredential.givenName,
        appleCredential.familyName,
      ].where((s) => s != null && s.isNotEmpty).join(' ');

      await _ensureUserDocument(
        userCred.user!,
        fallbackDisplayName: displayName.isNotEmpty ? displayName : null,
      );
      return Result.success(userCred.user!);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(AppFailure(_mapAuthError(e), code: e.code));
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Email/password fallback — sign up.
  Future<Result<fb.User>> signUpWithEmail(String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user!;

      // Send the link BEFORE any Firestore work. Creating the account signs
      // the user in immediately, so the app is already on the verification
      // screen by now — and _ensureUserDocument awaits server acknowledgement
      // of its writes, which stalls on a poor connection. Doing that first
      // would delay, or entirely skip, the one thing the user is waiting for.
      await _trySendVerification(user);

      await _ensureUserDocument(user);
      return Result.success(user);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(AppFailure(_mapAuthError(e), code: e.code));
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Email/password fallback — sign in.
  Future<Result<fb.User>> signInWithEmail(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _ensureUserDocument(cred.user!);
      return Result.success(cred.user!);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(AppFailure(_mapAuthError(e), code: e.code));
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// uid of the account the verification link was last sent to, so the
  /// verification screen can avoid sending a duplicate — or step in when the
  /// send at sign-up never happened.
  String? _verificationSentForUid;

  bool hasSentVerificationFor(String uid) => _verificationSentForUid == uid;

  /// Sends the link without failing the caller. The error is logged rather
  /// than swallowed, because a silent failure here looks exactly like a
  /// working app that sends no email.
  Future<bool> _trySendVerification(fb.User user) async {
    try {
      await user.sendEmailVerification();
      _verificationSentForUid = user.uid;
      return true;
    } catch (e) {
      debugPrint('Could not send verification email to ${user.email}: $e');
      return false;
    }
  }

  /// True when this account signed up with email/password. Google and Apple
  /// vouch for the address themselves, so they are never asked to verify.
  static bool requiresEmailVerification(fb.User? user) {
    if (user == null) return false;
    final usesPassword =
        user.providerData.any((p) => p.providerId == 'password');
    return usesPassword && !user.emailVerified;
  }

  /// Re-sends the verification link. Firebase rate-limits this, which surfaces
  /// as a user-facing message rather than a crash.
  Future<Result<void>> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return Result.failure(const AppFailure('You are not signed in.'));
      }
      if (user.emailVerified) return Result.success(null);
      await user.sendEmailVerification();
      _verificationSentForUid = user.uid;
      return Result.success(null);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(AppFailure(_mapAuthError(e), code: e.code));
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Pulls the latest state from Firebase and reports whether the address is
  /// now verified. The local `currentUser` caches `emailVerified`, so it only
  /// changes after a reload.
  Future<Result<bool>> refreshEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return Result.failure(const AppFailure('You are not signed in.'));
      }
      await user.reload();
      return Result.success(_auth.currentUser?.emailVerified ?? false);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(AppFailure(_mapAuthError(e), code: e.code));
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Wording for a failed password-reset request.
  ///
  /// Separate from [_mapAuthError] because the reset screen asks the user to
  /// correct the address, where sign-in just reports the attempt failed.
  ///
  /// Note: Firebase only reports `user-not-found` when *Email enumeration
  /// protection* is disabled in the console. With it enabled — the default —
  /// unknown addresses return success and this message never appears.
  static String passwordResetErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'Please enter a registered email address.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'missing-email':
        return 'Please enter your email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a minute and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return 'Could not send the reset link. Please try again.';
    }
  }

  Future<Result<void>> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return Result.success(null);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(
        AppFailure(passwordResetErrorMessage(e.code), code: e.code),
      );
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Updates display name in Firebase Auth + Firestore user profile.
  Future<Result<void>> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) {
      return Result.failure(const AppFailure('No signed-in user.', code: 'no-user'));
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return Result.failure(
        const AppFailure('Name cannot be empty.', code: 'empty-name'),
      );
    }
    if (trimmed.length > 60) {
      return Result.failure(
        const AppFailure('Name is too long (max 60 characters).', code: 'name-too-long'),
      );
    }
    try {
      await user.updateDisplayName(trimmed);
      await _firestore.collection(FirestoreCollections.users).doc(user.uid).set(
        {'displayName': trimmed},
        SetOptions(merge: true),
      );
      await user.reload();
      return Result.success(null);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(AppFailure(_mapAuthError(e), code: e.code));
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Uploads a profile photo as Base64 and updates Auth + Firestore.
  Future<Result<void>> updateProfilePhoto(File imageFile) async {
    final user = _auth.currentUser;
    if (user == null) {
      return Result.failure(const AppFailure('No signed-in user.', code: 'no-user'));
    }
    try {
      final bytes = await imageFile.readAsBytes();
      final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      // We only save Base64 to Firestore. Firebase Auth photoURL may reject large data URIs.
      await _firestore.collection(FirestoreCollections.users).doc(user.uid).set(
        {'photoUrl': base64String},
        SetOptions(merge: true),
      );
      await user.reload();
      return Result.success(null);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(AppFailure(_mapAuthError(e), code: e.code));
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      GoogleSignIn.instance.signOut().catchError((_) => null),
    ]);
  }

  /// Deletes the account in this order:
  /// 1. Re-authenticate (Firebase requires a recent login for Auth delete)
  /// 2. Delete all Firestore cloud data for the user
  /// 3. Delete the Firebase Auth user account
  /// Signs out of Google only when the account actually used it. Calling the
  /// plugin for an email-only account is pointless and can throw on platforms
  /// where it is unavailable.
  Future<void> _signOutOfGoogleIfUsed(Set<String> providers) async {
    if (!providers.contains('google.com')) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Already signed out, or unavailable — the account is gone either way.
    }
  }

  /// Closes the account: cloud data first, then the Auth user.
  ///
  /// Prefers a server-side delete. Removing a user from the client requires a
  /// recent sign-in, which means re-authenticating in the middle of leaving —
  /// and for email/password accounts that meant asking for the password again.
  /// The callable proves identity with the existing ID token instead, so both
  /// Google and email accounts delete without a second prompt.
  Future<Result<void>> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      return Result.failure(const AppFailure('No signed-in user.', code: 'no-user'));
    }
    final uid = user.uid;
    final providers = user.providerData.map((p) => p.providerId).toSet();

    // Preferred path: one server-side call does data then account.
    final viaServer = await _deleteAccountOnServer(providers);
    if (viaServer != null) return viaServer;

    // Fallback for when the function is not deployed or unreachable.
    try {
      // Cloud data first: once the Auth account is gone the client loses the
      // credentials needed to clean up anything left behind.
      await _deleteUserDataRecursively(uid);

      final latest = _auth.currentUser;
      if (latest == null) {
        return Result.failure(
          const AppFailure(
            'Signed out during deletion. Cloud data was removed; sign in again if the account still appears.',
            code: 'no-user',
          ),
        );
      }

      // Try without prompting first — a recent sign-in is usually still valid.
      try {
        await latest.delete();
      } on fb.FirebaseAuthException catch (e) {
        if (e.code != 'requires-recent-login') rethrow;
        // Only now is a fresh credential unavoidable. Google and Apple can do
        // it silently; email/password cannot without the password.
        await _reauthenticateForSensitiveAction(latest);
        await _auth.currentUser?.delete();
      }

      await _signOutOfGoogleIfUsed(providers);
      return Result.success(null);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(AppFailure(_mapAuthError(e), code: e.code));
    } on GoogleSignInException catch (e) {
      return Result.failure(
        AppFailure(_mapGoogleSignInError(e), code: e.code.name),
      );
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Runs the server-side delete.
  ///
  /// Returns null when the function is unavailable, so the caller can fall
  /// back to deleting from the client. A real failure is returned as-is —
  /// retrying on the client would only repeat it.
  Future<Result<void>?> _deleteAccountOnServer(Set<String> providers) async {
    try {
      await _functions.httpsCallable('deleteAccountAndData').call<void>();
      await _auth.signOut().catchError((_) {});
      await _signOutOfGoogleIfUsed(providers);
      return Result.success(null);
    } on cf.FirebaseFunctionsException catch (e) {
      // Not deployed / no network: let the client path try.
      if (e.code == 'not-found' ||
          e.code == 'unavailable' ||
          e.code == 'internal' && e.message == null) {
        debugPrint('Server delete unavailable (${e.code}); falling back.');
        return null;
      }
      return Result.failure(
        AppFailure(e.message ?? 'Could not delete your account.', code: e.code),
      );
    } catch (e) {
      debugPrint('Server delete failed, falling back: $e');
      return null;
    }
  }

  Future<void> _reauthenticateForSensitiveAction(fb.User user) async {
    final providers = user.providerData.map((p) => p.providerId).toSet();

    if (providers.contains('google.com')) {
      await _ensureGoogleSignInInitialized();
      final googleUser = await GoogleSignIn.instance.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        throw fb.FirebaseAuthException(
          code: 'missing-id-token',
          message: 'Google re-authentication did not return an ID token.',
        );
      }
      final authz = await googleUser.authorizationClient
          .authorizationForScopes(['email', 'profile']);
      final credential = fb.GoogleAuthProvider.credential(
        accessToken: authz?.accessToken,
        idToken: idToken,
      );
      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (providers.contains('apple.com')) {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final credential = fb.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );
      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (providers.contains('password')) {
      // Email/password needs the password interactively; ask user to re-login.
      throw fb.FirebaseAuthException(
        code: 'requires-recent-login',
        message: 'Please sign out and sign in again, then retry delete.',
      );
    }

    // Unknown provider — still attempt; Auth may accept a fresh session.
  }

  /// Firestore batch writes are capped at 500 ops; delete in pages of 400.
  /// Order: every user subcollection, then the parent users/{uid} document.
  Future<void> _deleteUserDataRecursively(String uid) async {
    final userRef = _firestore.collection(FirestoreCollections.users).doc(uid);
    for (final sub in [
      FirestoreCollections.transactions,
      FirestoreCollections.categories,
      FirestoreCollections.budgets,
      FirestoreCollections.recurringTransactions,
      FirestoreCollections.settings,
      FirestoreCollections.notifications,
    ]) {
      await _deleteCollectionInChunks(userRef.collection(sub));
    }
    // Parent user profile document last (after all nested cloud data).
    await userRef.delete();
  }

  Future<void> _deleteCollectionInChunks(CollectionReference<Map<String, dynamic>> ref) async {
    const chunkSize = 400;
    while (true) {
      final snap = await ref.limit(chunkSize).get();
      if (snap.docs.isEmpty) break;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _ensureUserDocument(
    fb.User user, {
    String? fallbackDisplayName,
  }) async {
    final ref = _firestore.collection(FirestoreCollections.users).doc(user.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      final profile = AppUserModel(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName ?? fallbackDisplayName,
        photoUrl: user.photoURL,
        createdAt: DateTime.now(),
      );
      await ref.set(profile.toMap());
      await _seedDefaultCategories(user.uid);
    }
  }

  Future<void> _seedDefaultCategories(String uid) async {
    final batch = _firestore.batch();
    final catRef = _firestore.collection(FirestorePaths.categories(uid));
    for (final c in kDefaultExpenseCategories) {
      final doc = catRef.doc();
      batch.set(doc, {
        'name': c['name'],
        'icon': c['icon'],
        'color': c['color'],
        'type': TransactionType.expense.name,
        'isDefault': true,
        'isArchived': false,
        'createdAt': Timestamp.now(),
      });
    }
    for (final c in kDefaultIncomeCategories) {
      final doc = catRef.doc();
      batch.set(doc, {
        'name': c['name'],
        'icon': c['icon'],
        'color': c['color'],
        'type': TransactionType.income.name,
        'isDefault': true,
        'isArchived': false,
        'createdAt': Timestamp.now(),
      });
    }
    await batch.commit();
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _mapGoogleSignInError(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Google sign-in was canceled. If you did not cancel, add the '
            'debug SHA-1 in Firebase Project settings and re-download '
            'google-services.json.';
      case GoogleSignInExceptionCode.clientConfigurationError:
        return 'Google Sign-In is misconfigured. Add SHA fingerprints in '
            'Firebase, enable the Google provider, and ensure '
            'google-services.json has a web OAuth client (client_type: 3).';
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google Sign-In provider is not set up correctly in Firebase / '
            'Google Cloud. Enable Google under Authentication → Sign-in method.';
      case GoogleSignInExceptionCode.interrupted:
        return 'Google sign-in was interrupted. Please try again.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google sign-in UI is unavailable right now. Try again later.';
      default:
        return e.description ?? 'Google sign-in failed. Please try again.';
    }
  }

  String _mapAuthError(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Please choose a stronger password (min. 6 characters).';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'requires-recent-login':
        return 'Please confirm your identity, then try deleting again.';
      case 'missing-id-token':
        return 'Google confirmation failed. Check SHA fingerprints in Firebase and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a minute and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'canceled':
        return 'Account deletion was canceled.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
