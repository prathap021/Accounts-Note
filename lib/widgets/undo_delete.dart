import 'package:flutter/material.dart';

import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';

/// "Deleted … · Undo".
///
/// Takes the [messenger] and [actions] resolved *before* the delete, not a
/// ref: the row that was swiped away (or its whole day section, when it was
/// the day's last entry) is gone by the time this runs, and so is its ref.
void showUndoDelete(
  ScaffoldMessengerState messenger,
  TransactionActionsNotifier actions,
  TransactionModel previous,
) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        // Shorter than the sync's delete grace, so Undo never races the
        // cloud delete.
        duration: const Duration(seconds: 5),
        content: Text('Deleted ${previous.categoryName} entry'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => actions.undoDelete(previous),
        ),
      ),
    );
}
