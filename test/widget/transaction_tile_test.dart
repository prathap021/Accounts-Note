import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:income_expense_tracker/data/local/sync_status.dart';
import 'package:income_expense_tracker/widgets/transaction_tile.dart';

import '../support/fixtures.dart';

/// The Activity row is the app's densest piece of UI and the one users read
/// most, so its content rules are pinned here.
void main() {
  Future<void> pumpTile(
    WidgetTester tester,
    Widget tile, {
    double width = 400,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Column(children: [tile])),
    ));
    await tester.pump();
  }

  group('content', () {
    testWidgets('shows the category, description and payment method',
        (tester) async {
      await pumpTile(
        tester,
        TransactionTile(
          transaction: txFixture(
            categoryName: 'Education',
            note: 'Agentic Ai purchase',
            paymentMethod: 'Cash',
          ),
        ),
      );

      expect(find.text('Education'), findsOneWidget);
      expect(find.text('Agentic Ai purchase'), findsOneWidget);
      expect(find.textContaining('Cash'), findsOneWidget);
    });

    testWidgets('a long description is not truncated to a single word',
        (tester) async {
      const longNote =
          'Dinner chapathi with the team after the sprint review, split four ways';
      await pumpTile(
        tester,
        TransactionTile(transaction: txFixture(note: longNote)),
      );

      // The full string is laid out; the Text widget decides how to wrap it.
      final text = tester.widget<Text>(find.text(longNote));
      expect(text.maxLines, 2, reason: 'descriptions get two lines');
    });

    testWidgets('omits the description line when there is no note',
        (tester) async {
      await pumpTile(
        tester,
        TransactionTile(transaction: txFixture(note: null)),
      );

      expect(find.text('Food'), findsOneWidget);
      expect(find.textContaining('Cash'), findsOneWidget);
    });
  });

  group('amount', () {
    testWidgets('an expense is negative and uses the expense colour',
        (tester) async {
      await pumpTile(
        tester,
        TransactionTile(transaction: txFixture(amount: 70)),
      );

      final amount = tester.widget<Text>(find.textContaining('70.00'));
      expect(amount.data, startsWith('−'), reason: 'minus sign');
      expect(amount.style?.color, AppColors.expense);
    });

    testWidgets('income is positive and uses the income colour',
        (tester) async {
      await pumpTile(
        tester,
        TransactionTile(
          transaction: txFixture(type: TransactionType.income, amount: 5000),
        ),
      );

      final amount = tester.widget<Text>(find.textContaining('5,000.00'));
      expect(amount.data, startsWith('+'));
      expect(amount.style?.color, AppColors.income);
    });

    testWidgets('respects the selected currency', (tester) async {
      await pumpTile(
        tester,
        TransactionTile(transaction: txFixture(amount: 70), currency: 'USD'),
      );

      expect(find.textContaining('\$'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
    });
  });

  group('icon', () {
    testWidgets('uses the category icon when the category is known',
        (tester) async {
      await pumpTile(
        tester,
        TransactionTile(
          transaction: txFixture(),
          category: categoryFixture(icon: 'restaurant'),
        ),
      );

      expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
    });

    testWidgets('falls back to a direction arrow for an unknown category',
        (tester) async {
      await pumpTile(tester, TransactionTile(transaction: txFixture()));

      // Both the fallback avatar and the corner badge point the same way.
      expect(find.byIcon(Icons.north_east_rounded), findsWidgets);
    });

    testWidgets('always shows the direction badge, even with a category icon',
        (tester) async {
      await pumpTile(
        tester,
        TransactionTile(
          transaction: txFixture(type: TransactionType.income),
          category: categoryFixture(icon: 'work'),
        ),
      );

      expect(find.byIcon(Icons.work_rounded), findsOneWidget);
      expect(find.byIcon(Icons.south_west_rounded), findsOneWidget);
    });
  });

  group('sync indicator', () {
    testWidgets('shows Syncing while a record is in flight', (tester) async {
      await pumpTile(
        tester,
        TransactionTile(
          transaction:
              txFixture().copyWith(syncStatus: SyncStatus.pending),
        ),
      );

      expect(find.text('Syncing'), findsOneWidget);
    });

    testWidgets('shows nothing once the record is synced', (tester) async {
      await pumpTile(
        tester,
        TransactionTile(
          transaction: txFixture().copyWith(syncStatus: SyncStatus.synced),
        ),
      );

      expect(find.text('Syncing'), findsNothing);
    });
  });

  group('interaction', () {
    testWidgets('tapping calls onTap', (tester) async {
      var tapped = false;
      await pumpTile(
        tester,
        TransactionTile(
          transaction: txFixture(),
          onTap: () => tapped = true,
        ),
      );

      await tester.tap(find.text('Food'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('swiping asks before deleting, and honours Cancel',
        (tester) async {
      var deleted = false;
      await pumpTile(
        tester,
        TransactionTile(
          transaction: txFixture(),
          onDelete: () => deleted = true,
        ),
      );

      await tester.drag(find.text('Food'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('Delete this transaction?'), findsOneWidget,
          reason: 'an accidental swipe must not destroy data');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(deleted, isFalse);
    });

    testWidgets('confirming the swipe deletes', (tester) async {
      var deleted = false;
      await pumpTile(
        tester,
        TransactionTile(
          transaction: txFixture(),
          onDelete: () => deleted = true,
        ),
      );

      await tester.drag(find.text('Food'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });

    testWidgets('a tile with no onDelete cannot be swiped away',
        (tester) async {
      await pumpTile(tester, TransactionTile(transaction: txFixture()));

      await tester.drag(find.text('Food'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('Delete this transaction?'), findsNothing);
      expect(find.text('Food'), findsOneWidget);
    });
  });
}
