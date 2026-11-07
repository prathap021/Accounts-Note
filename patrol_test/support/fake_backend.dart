import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../test/support/fake_csv_import.dart';
import '../../test/support/fake_notifications.dart';
import '../../test/support/fake_subscriptions.dart';

export '../../test/support/fake_notifications.dart';
export '../../test/support/fake_subscriptions.dart';

/// In-memory stand-ins for every network dependency the app has, so the
/// end-to-end suite drives the real UI, real Hive and real platform plugins on
/// a device without ever touching the production Firebase project.
///
/// The fakes are deliberately stricter than `firebase_auth_mocks`: accounts
/// persist, wrong passwords are rejected, and verification and
/// sign-out notify the app the same way Firebase does. A flow test that a
/// lenient fake lets through proves nothing.
class FakeBackend {
  FakeBackend() : auth = FakeFirebaseAuth();

  final FakeFirebaseFirestore firestore = FakeFirebaseFirestore();
  final FakeFirebaseAuth auth;
  final FakeConnectivity connectivity = FakeConnectivity();

  /// The device's app store: sells the three plans, answers at once.
  final FakeSubscriptionStore store = FakeSubscriptionStore();

  /// What would be shown or scheduled as a notification.
  final FakeNotifications notifications = FakeNotifications();

  /// The phone's fingerprint reader; off unless a test turns it on.
  final FakeBiometrics biometrics = FakeBiometrics();

  /// The camera / gallery for receipt photos.
  final FakeReceiptPicker receiptPicker = FakeReceiptPicker();

  /// The CSV import function and its file picker.
  late final FakeCsvImportService csvImport = FakeCsvImportService(
    firestore: firestore,
    currentUid: () => auth.currentUser?.uid,
  );

  /// Backups built from and imported into the fake Firestore.
  late final FakeBackupService backups = FakeBackupService(
    firestore: firestore,
    currentUid: () => auth.currentUser?.uid,
  );

  /// The share sheet and file picker: a shared backup can be picked again,
  /// as if saved to Files and opened in another account.
  final FakeBackupFiles backupFiles = FakeBackupFiles();

  /// The backend's purchase verifier; writes the plan to the profile.
  late final FakeSubscriptionBackend subscriptions = FakeSubscriptionBackend(
    firestore: firestore,
    currentUid: () => auth.currentUser?.uid,
  );
}

/// One registered email/password account, as the auth server would hold it.
class FakeAccount {
  FakeAccount({
    required this.uid,
    required this.email,
    required this.password,
    this.displayName,
    this.emailVerified = true,
  });

  final String uid;
  final String email;
  String password;
  String? displayName;
  bool emailVerified;
  int verificationEmailsSent = 0;
}

/// Email/password auth with the semantics the app relies on.
class FakeFirebaseAuth implements FirebaseAuth {
  final _accounts = <String, FakeAccount>{};
  final _changes = StreamController<User?>.broadcast();
  _FakeUser? _current;
  var _nextUid = 1;

  /// Every address a password reset link was requested for, in order.
  final List<String> passwordResetsSentTo = [];

  static String _key(String email) => email.trim().toLowerCase();

  FakeAccount? accountFor(String email) => _accounts[_key(email)];

  /// Creates an account directly on the "server", as if it signed up earlier.
  FakeAccount register({
    required String email,
    required String password,
    String? displayName,
    bool emailVerified = true,
  }) {
    final account = FakeAccount(
      uid: 'uid-${_nextUid++}',
      email: email.trim(),
      password: password,
      displayName: displayName,
      emailVerified: emailVerified,
    );
    _accounts[_key(email)] = account;
    return account;
  }

  /// What happens when the user opens the link in their inbox: the server
  /// knows at once, but the app only finds out on its next reload.
  void confirmEmailFromInbox(String email) {
    accountFor(email)!.emailVerified = true;
  }

  void _setCurrent(FakeAccount? account) {
    _current = account == null ? null : _FakeUser(this, account);
    _changes.add(_current);
  }

  Stream<User?> _withCurrent() async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  User? get currentUser => _current;

  @override
  Stream<User?> userChanges() => _withCurrent();

  @override
  Stream<User?> authStateChanges() => _withCurrent();

  @override
  Stream<User?> idTokenChanges() => _withCurrent();

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (!email.contains('@')) {
      throw FirebaseAuthException(code: 'invalid-email');
    }
    if (password.length < 6) {
      throw FirebaseAuthException(code: 'weak-password');
    }
    if (accountFor(email) != null) {
      throw FirebaseAuthException(code: 'email-already-in-use');
    }
    // A new email/password account starts unverified, exactly like Firebase.
    final account = register(
      email: email,
      password: password,
      emailVerified: false,
    );
    _setCurrent(account);
    return _FakeCredential(_current!);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final account = accountFor(email);
    // Email-enumeration protection: an unknown address and a wrong password
    // are indistinguishable to the client.
    if (account == null || account.password != password) {
      throw FirebaseAuthException(code: 'invalid-credential');
    }
    _setCurrent(account);
    return _FakeCredential(_current!);
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    if (!email.contains('@')) {
      throw FirebaseAuthException(code: 'invalid-email');
    }
    passwordResetsSentTo.add(email.trim());
  }

  @override
  Future<void> signOut() async => _setCurrent(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'FakeFirebaseAuth does not support ${invocation.memberName}. '
    'Add it if a flow under test needs it.',
  );
}

/// A snapshot of the account, like Firebase's `User`: fields such as
/// [emailVerified] only change after [reload].
class _FakeUser implements User {
  _FakeUser(this._auth, this._account)
    : _emailVerified = _account.emailVerified,
      _displayName = _account.displayName;

  final FakeFirebaseAuth _auth;
  final FakeAccount _account;
  final bool _emailVerified;
  final String? _displayName;

  @override
  String get uid => _account.uid;

  @override
  String? get email => _account.email;

  @override
  String? get displayName => _displayName;

  @override
  String? get photoURL => null;

  @override
  bool get emailVerified => _emailVerified;

  @override
  bool get isAnonymous => false;

  @override
  List<UserInfo> get providerData => [_PasswordProviderInfo(_account)];

  @override
  Future<void> reload() async {
    // Publishes a fresh snapshot, the way `userChanges` fires after a reload.
    if (_auth._current?.uid == uid) _auth._setCurrent(_account);
  }

  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    _account.verificationEmailsSent++;
  }

  @override
  Future<void> updateDisplayName(String? displayName) async {
    _account.displayName = displayName;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'FakeUser does not support ${invocation.memberName}.',
  );
}

class _PasswordProviderInfo implements UserInfo {
  _PasswordProviderInfo(this._account);
  final FakeAccount _account;

  @override
  String get providerId => 'password';

  @override
  String? get email => _account.email;

  @override
  String? get uid => _account.uid;

  @override
  String? get displayName => _account.displayName;

  @override
  String? get photoURL => null;

  @override
  String? get phoneNumber => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeCredential implements UserCredential {
  _FakeCredential(this.user);

  @override
  final User user;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Lets a test take the device "offline" without touching the emulator's
/// radios, so offline flows are deterministic.
class FakeConnectivity implements Connectivity {
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();
  var _online = true;

  bool get isOnline => _online;

  List<ConnectivityResult> get _current => [
    _online ? ConnectivityResult.wifi : ConnectivityResult.none,
  ];

  set online(bool value) {
    _online = value;
    _changes.add(_current);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;
}

