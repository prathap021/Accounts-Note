import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accounts_note/core/constants/app_constants.dart';
import 'package:accounts_note/core/theme/app_theme.dart';
import 'package:accounts_note/data/repositories/credit_card_repository.dart';
import 'package:accounts_note/features/credit_cards/credit_cards_screen.dart';
import 'package:accounts_note/models/credit_card_model.dart';
import 'package:accounts_note/providers/auth_provider.dart';
import 'package:accounts_note/providers/credit_card_provider.dart';
import 'package:accounts_note/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fixtures.dart';

/// The add/edit card form: what it saves, what it hands back to the expense
/// form, and the card numbers it refuses to keep.
void main() {
  late FakeFirebaseFirestore firestore;
  late SharedPreferences prefs;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// Opens the form the way the app does and records what it hands back.
  Future<List<CreditCardModel?>> openForm(
    WidgetTester tester, {
    CreditCardModel? existing,
  }) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final results = <CreditCardModel?>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUidProvider.overrideWithValue(testUid),
        creditCardRepositoryProvider
            .overrideWithValue(CreditCardRepository(firestore: firestore)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => results
                    .add(await showCreditCardForm(context, existing: existing)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> tapSave(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  Future<List<CreditCardModel>> savedCards() async {
    final snap =
        await firestore.collection(FirestorePaths.creditCards(testUid)).get();
    return snap.docs.map(CreditCardModel.fromDoc).toList();
  }

  testWidgets('saves a new card and hands it back to whoever opened the form',
      (tester) async {
    final results = await openForm(tester);

    await tester.enterText(field('Card name'), 'HDFC Millennia');
    await tester.enterText(field('Last 4 digits (optional)'), '4321');
    await tester.enterText(field('Credit limit (optional)'), '100000');
    await tapSave(tester, 'Add card');

    final cards = await savedCards();
    expect(cards, hasLength(1));
    expect(cards.single.name, 'HDFC Millennia');
    expect(cards.single.last4, '4321');
    expect(cards.single.creditLimit, 100000);
    expect(results.single?.id, cards.single.id,
        reason: 'the expense form selects a card added from it straight away');
  });

  testWidgets('the preview shows the card as it is typed', (tester) async {
    await openForm(tester);

    await tester.enterText(field('Card name'), 'Amex');
    await tester.enterText(field('Last 4 digits (optional)'), '1005');
    await tester.pump();

    expect(find.text('AMEX'), findsOneWidget);
    expect(find.text('••••  ••••  ••••  1005'), findsOneWidget);
  });

  testWidgets('the digits field takes four digits and nothing else',
      (tester) async {
    await openForm(tester);

    await tester.enterText(field('Last 4 digits (optional)'), '41a11111');
    await tester.pump();

    final input = tester.widget<TextField>(field('Last 4 digits (optional)'));
    expect(input.controller!.text, '4111');
  });

  testWidgets('refuses fewer than four digits', (tester) async {
    await openForm(tester);

    await tester.enterText(field('Card name'), 'Visa');
    await tester.enterText(field('Last 4 digits (optional)'), '12');
    await tapSave(tester, 'Add card');

    expect(find.text('Enter exactly 4 digits'), findsOneWidget);
    expect(await savedCards(), isEmpty);
  });

  testWidgets('refuses a full card number typed into the name',
      (tester) async {
    await openForm(tester);

    await tester.enterText(field('Card name'), 'Visa 4111 1111 1111 1111');
    await tapSave(tester, 'Add card');

    expect(
      find.text('Leave the card number out — only the last 4 digits are kept'),
      findsOneWidget,
    );
    expect(await savedCards(), isEmpty,
        reason: 'a card number must never reach the database');
  });

  testWidgets('a card needs a name', (tester) async {
    await openForm(tester);

    await tapSave(tester, 'Add card');

    expect(find.text('Give this card a name'), findsOneWidget);
    expect(await savedCards(), isEmpty);
  });

  testWidgets('editing can remove the digits and the limit', (tester) async {
    final card = creditCardFixture(creditLimit: 50000);
    await firestore
        .collection(FirestorePaths.creditCards(testUid))
        .doc(card.id)
        .set(card.toMap());
    await openForm(tester, existing: card);

    expect(find.text('Edit card'), findsOneWidget);
    await tester.enterText(field('Last 4 digits (optional)'), '');
    await tester.enterText(field('Credit limit (optional)'), '');
    await tapSave(tester, 'Save changes');

    final saved = (await savedCards()).single;
    expect(saved.name, 'HDFC Millennia');
    expect(saved.last4, isNull);
    expect(saved.creditLimit, isNull);
  });
}
