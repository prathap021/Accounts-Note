import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:income_expense_tracker/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app wrapped in ProviderScope as required by Riverpod.
    await tester.pumpWidget(
      const ProviderScope(child: IncomeExpenseTrackerApp()),
    );

    // Verify that the app renders without throwing.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
