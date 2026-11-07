import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../models/app_user_model.dart';

/// The signed-in user's profile document, `users/{uid}`.
class ProfileRepository {
  ProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Live profile, including the subscription the backend has verified.
  Stream<AppUserModel?> watchProfile(String uid) {
    return _firestore
        .collection(FirestoreCollections.users)
        .doc(uid)
        .snapshots()
        .map((snap) => snap.exists ? AppUserModel.fromDoc(snap) : null);
  }
}
