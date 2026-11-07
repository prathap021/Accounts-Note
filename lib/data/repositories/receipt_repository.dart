import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';

/// Where a receipt photo comes from.
enum ReceiptSource { camera, gallery }

/// Takes or picks a receipt photo, already shrunk to a size that fits a
/// Firestore document. Behind an interface so tests need no camera.
abstract class ReceiptPicker {
  Future<Uint8List?> pick(ReceiptSource source);
}

class DeviceReceiptPicker implements ReceiptPicker {
  const DeviceReceiptPicker();

  @override
  Future<Uint8List?> pick(ReceiptSource source) async {
    final file = await ImagePicker().pickImage(
      source: source == ReceiptSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // Readable for a printed receipt, and well under the 1 MB document
      // limit (typically 100–250 KB).
      maxWidth: 1400,
      maxHeight: 1400,
      imageQuality: 60,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return bytes.length > ReceiptRepository.maxBytes ? null : bytes;
  }
}

/// Receipt photos, one document per transaction:
/// users/{uid}/receipts/{transactionId} = {image: bytes, contentType,
/// createdAt}. Kept apart from the transaction so lists never download
/// images; a photo is fetched only when it is opened, and Firestore's cache
/// keeps it for offline use.
class ReceiptRepository {
  ReceiptRepository({
    FirebaseFirestore? firestore,
    this.ackTimeout = const Duration(seconds: 4),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration ackTimeout;

  /// Mirrors the limit in firestore.rules.
  static const maxBytes = 900 * 1024;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String txId) =>
      _firestore.doc('${FirestorePaths.user(uid)}/receipts/$txId');

  Future<void> _commit(Future<void> write) async {
    try {
      await write.timeout(ackTimeout);
    } on TimeoutException {
      // Queued offline.
    }
  }

  Future<void> save(String uid, String txId, Uint8List bytes) => _commit(
    _doc(uid, txId).set({
      'image': Blob(bytes),
      'contentType': 'image/jpeg',
      'createdAt': Timestamp.now(),
    }),
  );

  Future<Uint8List?> load(String uid, String txId) async {
    final snap = await _doc(uid, txId).get();
    final blob = snap.data()?['image'];
    return blob is Blob ? blob.bytes : null;
  }

  Future<void> delete(String uid, String txId) =>
      _commit(_doc(uid, txId).delete());
}

final receiptPickerProvider = Provider<ReceiptPicker>(
  (ref) => const DeviceReceiptPicker(),
);

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => ReceiptRepository(),
);

/// A transaction's receipt photo, fetched when first shown.
final receiptImageProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, txId) async {
      final uid = ref.watch(currentUidProvider);
      if (uid == null) return null;
      return ref.watch(receiptRepositoryProvider).load(uid, txId);
    });
