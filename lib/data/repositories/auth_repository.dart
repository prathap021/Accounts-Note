import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
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
  Future<void>? _googleSignInReady;

  AuthRepository({
    fb.FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? fb.FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

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
      await _ensureUserDocument(cred.user!);
      return Result.success(cred.user!);
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

  Future<Result<void>> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return Result.success(null);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(AppFailure(_mapAuthError(e), code: e.code));
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

  /// Deletes the Firebase Auth account AND the user's Firestore data.
  /// Re-authentication may be required by Firebase for recent-login
  /// security; callers should catch `requires-recent-login` and prompt
  /// the user to sign in again before retrying.
  Future<Result<void>> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      return Result.failure(const AppFailure('No signed-in user.', code: 'no-user'));
    }
    try {
      await _deleteUserDataRecursively(user.uid);
      await user.delete();
      return Result.success(null);
    } on fb.FirebaseAuthException catch (e) {
      return Result.failure(AppFailure(_mapAuthError(e), code: e.code));
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<void> _deleteUserDataRecursively(String uid) async {
    final userRef = _firestore.collection(FirestoreCollections.users).doc(uid);
    for (final sub in [
      FirestoreCollections.transactions,
      FirestoreCollections.categories,
      FirestoreCollections.budgets,
      FirestoreCollections.recurringTransactions,
    ]) {
      final snap = await userRef.collection(sub).get();
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await userRef.delete();
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
        return 'Please sign in again to confirm this action.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
