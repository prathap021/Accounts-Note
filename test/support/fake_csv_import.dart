import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:accounts_note/core/utils/result.dart';
import 'package:accounts_note/data/repositories/csv_import_repository.dart';
import 'package:accounts_note/data/repositories/receipt_repository.dart';

/// The CSV import function, writing straight into the fake Firestore: rows
/// become entries in the matching category (by name and type), or in a new
/// one. Ids come from the row, so a second import adds nothing.
class FakeCsvImportService implements CsvImportService {
  FakeCsvImportService({required this.firestore, required this.currentUid});

  final FakeFirebaseFirestore firestore;
  final String? Function() currentUid;

  /// What the file picker returns next.
  String? nextFile;

  @override
  Future<String?> pickFile() async => nextFile;

  @override
  Future<Result<CsvImportResult>> importEntries(List<CsvEntry> entries) async {
    final uid = currentUid()!;
    final cats = await firestore.collection('users/$uid/categories').get();
    final byKey = {
      for (final d in cats.docs)
        '${d['type']}|${(d['name'] as String).toLowerCase()}': d.id,
    };
    var added = 0, already = 0, categoriesAdded = 0;
    for (final e in entries) {
      final key = '${e.type.name}|${e.category.toLowerCase()}';
      var catId = byKey[key];
      if (catId == null) {
        final ref = firestore.collection('users/$uid/categories').doc();
        await ref.set({
          'name': e.category,
          'type': e.type.name,
          'icon': 'category',
          'color': 0xFF64748B,
          'isDefault': false,
          'isArchived': false,
          'createdAt': Timestamp.now(),
        });
        catId = byKey[key] = ref.id;
        categoriesAdded++;
      }
      final id =
          'csv-${e.type.name}-${e.amount}-${e.date.millisecondsSinceEpoch}';
      final ref = firestore.doc('users/$uid/transactions/$id');
      if ((await ref.get()).exists) {
        already++;
        continue;
      }
      await ref.set({
        'type': e.type.name,
        'amount': e.amount,
        'categoryId': catId,
        'categoryName': e.category,
        'note': e.note,
        'date': Timestamp.fromDate(e.date),
        'paymentMethod': e.paymentMethod ?? 'Other',
        'isRecurring': false,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
      added++;
    }
    return Result.success(
      CsvImportResult(
        added: added,
        alreadyThere: already,
        categoriesAdded: categoriesAdded,
        remainingThisMonth: 420 - added,
      ),
    );
  }
}

/// The camera and gallery: hands back a small valid PNG, no system UI.
class FakeReceiptPicker implements ReceiptPicker {
  /// A 1×1 PNG.
  static final photo = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  int picks = 0;

  @override
  Future<Uint8List?> pick(ReceiptSource source) async {
    picks++;
    return photo;
  }
}
