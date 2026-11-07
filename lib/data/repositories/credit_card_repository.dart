import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/result.dart';
import '../../models/credit_card_model.dart';

class CreditCardRepository {
  final FirebaseFirestore _firestore;

  /// How long a write waits for the server before trusting the local cache.
  final Duration ackTimeout;

  CreditCardRepository({
    FirebaseFirestore? firestore,
    this.ackTimeout = const Duration(seconds: 4),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection(FirestorePaths.creditCards(uid));

  Stream<List<CreditCardModel>> watchCards(String uid) {
    return _col(uid).snapshots().map(
          (snap) => snap.docs.map(CreditCardModel.fromDoc).toList()
            ..sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase())),
        );
  }

  /// Firestore applies a write to its local cache at once, but only completes
  /// the future when the server acknowledges it — which, offline, is never.
  /// Cards are often added halfway through logging an expense, so rather than
  /// leave that form spinning, give the server a moment and otherwise trust
  /// the queued write: it is already on screen and syncs on reconnect.
  ///
  /// A rejection that arrives in time (say, rules not deployed) still
  /// surfaces as a failure; one that arrives later is absorbed by [timeout]
  /// rather than escaping as an uncaught error.
  @visibleForTesting
  Future<void> commit(Future<void> write) async {
    try {
      await write.timeout(ackTimeout);
    } on TimeoutException {
      // Queued offline.
    }
  }

  Future<Result<CreditCardModel>> addCard(
    String uid,
    CreditCardModel card,
  ) async {
    try {
      // The id is generated on the device, so the caller can use the card
      // straight away even while the write is still queued.
      final ref = _col(uid).doc();
      final saved = card.copyWith(id: ref.id);
      await commit(ref.set(saved.toMap()));
      return Result.success(saved);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  Future<Result<void>> updateCard(String uid, CreditCardModel card) async {
    try {
      await commit(_col(uid).doc(card.id).update(card.toMap()));
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }

  /// Past transactions are left alone: they carry the card's name, so the
  /// ledger still says which card paid even once the card itself is gone.
  Future<Result<void>> deleteCard(String uid, String cardId) async {
    try {
      await commit(_col(uid).doc(cardId).delete());
      return Result.success(null);
    } catch (e) {
      return Result.failure(AppFailure.fromException(e));
    }
  }
}
