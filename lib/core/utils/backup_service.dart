import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/transaction_model.dart';
import '../constants/app_constants.dart';

class BackupService {
  static Future<String?> backupTransactionsToExcel() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    final uid = user.uid;
    final firestore = FirebaseFirestore.instance;

    // Fetch categories
    final catsSnap = await firestore
        .collection(FirestoreCollections.users)
        .doc(uid)
        .collection(FirestoreCollections.categories)
        .get();
    
    final Map<String, String> catMap = {};
    for (var doc in catsSnap.docs) {
      final data = doc.data();
      if (data['name'] != null) {
        catMap[doc.id] = data['name'] as String;
      }
    }

    // Fetch transactions
    final txSnap = await firestore
        .collection(FirestoreCollections.users)
        .doc(uid)
        .collection(FirestoreCollections.transactions)
        .orderBy('date', descending: true)
        .get();
        
    final transactions = txSnap.docs.map(TransactionModel.fromDoc).toList();

    // Create Excel
    var excel = Excel.createExcel();
    var sheet = excel['Transactions'];
    
    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Type'),
      TextCellValue('Category'),
      TextCellValue('Amount'),
      TextCellValue('Payment Method'),
      TextCellValue('Note'),
    ]);

    for (var tx in transactions) {
      sheet.appendRow([
        TextCellValue(tx.date.toIso8601String().split('T').first),
        TextCellValue(tx.type == TransactionType.income ? 'Income' : 'Expense'),
        TextCellValue(catMap[tx.categoryId] ?? tx.categoryId),
        DoubleCellValue(tx.amount),
        TextCellValue(tx.paymentMethod ?? ''),
        TextCellValue(tx.note ?? ''),
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Save File
    Directory? dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download');
      if (!dir.existsSync()) {
        dir = await getDownloadsDirectory();
      }
    } else {
      dir = await getDownloadsDirectory();
    }
    
    dir ??= await getApplicationDocumentsDirectory();

    final dateStr = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final filePath = '${dir.path}/AccountsNote_Backup_$dateStr.xlsx';
    final file = File(filePath);
    
    await file.writeAsBytes(excel.save()!);
    return filePath;
  }
}
