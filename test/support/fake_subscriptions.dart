import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as cf;
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/core/utils/result.dart';
import 'package:accounts_note/data/repositories/backup_repository.dart';
import 'package:accounts_note/data/repositories/subscription_repository.dart';
import 'package:accounts_note/data/subscriptions/subscription_store.dart';
import 'package:accounts_note/models/subscription_plan.dart';

/// Shared by the widget tests (test/) and the Patrol suite (patrol_test/).

/// An app store that sells the three plans and answers purchases at once.
///
/// [nextOutcome] decides what the next [buy] reports, so a test can walk the
/// cancelled, failed and pending paths as well as the happy one.
class FakeSubscriptionStore implements SubscriptionStore {
  bool available = true;
  StorePurchaseStatus nextOutcome = StorePurchaseStatus.purchased;

  /// Product ids passed to [buy], in order.
  final List<String> bought = [];

  /// The subscription each [buy] replaced (null for a first purchase).
  final List<StorePurchase?> replaced = [];

  /// Whether each [buy] was treated as an upgrade.
  final List<bool> upgrades = [];
  final List<StorePurchase> completed = [];
  int restoreCalls = 0;

  final _updates = StreamController<List<StorePurchase>>.broadcast();
  StorePurchase? _owned;
  var _nextToken = 1;

  /// Makes the store hold a subscription already. [acknowledged] is the
  /// usual case (a reinstall, a second device); an unacknowledged one is a
  /// purchase the app was killed before confirming.
  void own(SubscriptionPlan plan, {bool acknowledged = true}) {
    final p = _purchase(plan.productId!, StorePurchaseStatus.purchased);
    _owned = StorePurchase(
      productId: p.productId,
      status: p.status,
      platform: p.platform,
      purchaseToken: p.purchaseToken,
      needsCompletion: !acknowledged,
    );
  }

  StorePurchase _purchase(String productId, StorePurchaseStatus status) =>
      StorePurchase(
        productId: productId,
        status: status,
        platform: 'android',
        purchaseToken: 'token-${_nextToken++}',
        needsCompletion: status != StorePurchaseStatus.pending,
      );

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Map<String, StoreProduct>> loadProducts(Set<String> ids) async {
    double usd(String label) => double.parse(label.substring(1));
    return {
      for (final p in SubscriptionPlan.paid) ...{
        if (ids.contains(p.productId))
          p.productId!: StoreProduct(
            id: p.productId!,
            title: p.title,
            price: '${p.priceLabel}.00',
            rawPrice: usd(p.priceLabel),
            currencyCode: 'USD',
          ),
        if (ids.contains(p.yearlyProductId))
          p.yearlyProductId!: StoreProduct(
            id: p.yearlyProductId!,
            title: '${p.title} (yearly)',
            price: '${p.yearlyPriceLabel}.00',
            rawPrice: usd(p.yearlyPriceLabel),
            currencyCode: 'USD',
          ),
      },
    };
  }

  @override
  Stream<List<StorePurchase>> get purchaseUpdates => _updates.stream;

  @override
  Future<bool> buy(
    StoreProduct product, {
    required String accountUid,
    StorePurchase? replacing,
    bool isUpgrade = true,
  }) async {
    bought.add(product.id);
    replaced.add(replacing);
    upgrades.add(isUpgrade);
    final purchase = _purchase(product.id, nextOutcome);
    if (nextOutcome == StorePurchaseStatus.purchased) _owned = purchase;
    scheduleMicrotask(() => _updates.add([purchase]));
    return true;
  }

  @override
  Future<void> restore({required String accountUid}) async {
    restoreCalls++;
    final owned = _owned;
    if (owned == null) return;
    _updates.add([
      StorePurchase(
        productId: owned.productId,
        status: StorePurchaseStatus.restored,
        platform: owned.platform,
        purchaseToken: owned.purchaseToken,
        needsCompletion: true,
      ),
    ]);
  }

  @override
  Future<void> complete(StorePurchase purchase) async {
    completed.add(purchase);
  }

  @override
  Future<StorePurchase?> ownedSubscription(Set<String> productIds) async =>
      _owned;
}

/// The backend's verifier, without Cloud Functions: a verified purchase
/// writes the plan to the profile the way `verifySubscription` does.
class FakeSubscriptionBackend extends SubscriptionRepository {
  FakeSubscriptionBackend({required this.firestore, required this.currentUid})
    : super(functions: _NoFunctions());

  final FirebaseFirestore firestore;
  final String? Function() currentUid;

  final List<StorePurchase> verified = [];
  int refreshCalls = 0;

  /// When set, the next [verify] fails with it (once).
  SubscriptionFailure? rejectNext;

  @override
  Future<Result<void>> verify(StorePurchase purchase) async {
    final reject = rejectNext;
    if (reject != null) {
      rejectNext = null;
      return Result.failure(reject);
    }
    final uid = currentUid();
    final plan = SubscriptionPlan.fromProductId(purchase.productId);
    if (uid == null || plan == null) {
      return Result.failure(const SubscriptionFailure('Not signed in.'));
    }
    await grant(uid, plan, productId: purchase.productId);
    verified.add(purchase);
    return Result.success(null);
  }

  @override
  Future<Result<void>> refresh() async {
    refreshCalls++;
    return Result.success(null);
  }

  /// Writes [plan] to the profile as the backend would after verifying.
  Future<void> grant(
    String uid,
    SubscriptionPlan plan, {
    String status = 'active',
    Duration validFor = const Duration(days: 30),
    bool autoRenewing = true,
    String? productId,
  }) {
    return firestore.collection(FirestoreCollections.users).doc(uid).set({
      'subscriptionPlan': plan.name,
      'subscriptionStatus': status,
      'subscriptionExpiresAt': Timestamp.fromDate(DateTime.now().add(validFor)),
      'subscriptionAutoRenewing': autoRenewing,
      'subscriptionPlatform': 'android',
      'subscriptionProductId': productId ?? plan.productId,
      'subscriptionLinkId': 'android_test',
    }, SetOptions(merge: true));
  }
}

class _NoFunctions implements cf.FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No Cloud Functions in tests');
}

/// Backups without Cloud Functions: built from and imported into the fake
/// Firestore, following the same rules as functions/src/backup.ts (minus
/// the signature, which the emulator tests cover). Categories are reused by
/// name and type, and transactions keep their ids.
class FakeBackupService extends BackupRepository {
  FakeBackupService({required this.firestore, required this.currentUid})
    : super(functions: _NoFunctions());

  final FirebaseFirestore firestore;
  final String? Function() currentUid;

  static Object? _encode(Object? v) => switch (v) {
    final Timestamp t => {'__ts': t.millisecondsSinceEpoch},
    final Map m => {
      for (final e in m.entries) e.key as String: _encode(e.value),
    },
    final List l => l.map(_encode).toList(),
    _ => v,
  };

  static Object? _decode(Object? v) {
    if (v is Map && v.length == 1 && v['__ts'] is int) {
      return Timestamp.fromMillisecondsSinceEpoch(v['__ts'] as int);
    }
    if (v is Map) {
      return {for (final e in v.entries) e.key as String: _decode(e.value)};
    }
    if (v is List) return v.map(_decode).toList();
    return v;
  }

  @override
  Future<Result<String>> create({required String currency}) async {
    final uid = currentUid()!;
    final cols = <String, Object>{};
    for (final name in [
      'categories',
      'creditCards',
      'budgets',
      'transactions',
    ]) {
      final snap = await firestore.collection('users/$uid/$name').get();
      cols[name] = [
        for (final d in snap.docs) {'id': d.id, 'data': _encode(d.data())},
      ];
    }
    final payload = {
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'sourceUid': uid,
      'sourceEmail': null,
      'currency': currency,
      'collections': cols,
    };
    return Result.success(
      jsonEncode({
        'format': 'accounts-note-backup',
        'version': 1,
        'data': base64Encode(utf8.encode(jsonEncode(payload))),
        'signature': 'fake',
      }),
    );
  }

  @override
  Future<Result<ImportSummary>> importContent(String content) async {
    final uid = currentUid()!;
    final file = jsonDecode(content) as Map<String, dynamic>;
    final payload =
        jsonDecode(utf8.decode(base64Decode(file['data'] as String)))
            as Map<String, dynamic>;
    final cols = payload['collections'] as Map<String, dynamic>;

    final existing = await firestore.collection('users/$uid/categories').get();
    final byKey = {
      for (final d in existing.docs) '${d['type']}|${d['name']}': d.id,
    };
    final catMap = <String, String>{};
    var categoriesAdded = 0;
    for (final c in cols['categories'] as List) {
      final data = (c as Map)['data'] as Map;
      final key = '${data['type']}|${data['name']}';
      final id = byKey[key] ?? c['id'] as String;
      if (!byKey.containsKey(key)) {
        await firestore
            .doc('users/$uid/categories/$id')
            .set(_decode(data)! as Map<String, dynamic>);
        byKey[key] = id;
        categoriesAdded++;
      }
      catMap[c['id'] as String] = id;
    }

    var added = 0, already = 0;
    for (final t in cols['transactions'] as List) {
      final id = (t as Map)['id'] as String;
      final ref = firestore.doc('users/$uid/transactions/$id');
      if ((await ref.get()).exists) {
        already++;
        continue;
      }
      final data = _decode(t['data'])! as Map<String, dynamic>;
      data['categoryId'] = catMap[data['categoryId']] ?? data['categoryId'];
      await ref.set(data);
      added++;
    }
    return Result.success(
      ImportSummary(
        transactionsAdded: added,
        transactionsAlreadyThere: already,
        categoriesAdded: categoriesAdded,
        creditCardsAdded: 0,
        budgetsImported: 0,
      ),
    );
  }
}

/// The share sheet and file picker: whatever was shared can be picked.
class FakeBackupFiles implements BackupFiles {
  String? lastShared;
  String? lastSharedName;

  @override
  Future<void> share(String fileName, String content) async {
    lastSharedName = fileName;
    lastShared = content;
  }

  @override
  Future<String?> pick() async => lastShared;
}
