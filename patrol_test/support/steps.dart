import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/utils/currency_formatter.dart';
import 'package:patrol/patrol.dart';

import 'test_app.dart';

/// Money as the app renders it, so assertions never hard-code formatting.
String money(double amount, {String currency = 'INR'}) =>
    CurrencyFormatter.format(amount, currencyCode: currency);

/// The large balance on the dashboard, which uses a spaced symbol.
String balance(double amount, {String currency = 'INR'}) =>
    CurrencyFormatter.format(
      amount,
      currencyCode: currency,
      spacedSymbol: true,
    );

/// The signed amount on a transaction row ("+₹10.00" / "−₹10.00").
String signedMoney(
  double amount, {
  required TransactionType type,
  String currency = 'INR',
}) =>
    '${type == TransactionType.income ? '+' : '−'}${money(amount, currency: currency)}';

/// The steps a user takes, written once so each test reads as the flow it
/// checks rather than as a list of taps.
extension UserSteps on PatrolIntegrationTester {
  PatrolFinder get sheet => this(BottomSheet);
  PatrolFinder get dialog => this(AlertDialog);

  // ---- Device keyboard ----------------------------------------------------

  /// Typing on a device raises the real soft keyboard, which covers buttons
  /// and shrinks lazy lists. Dismissing it is what a user does before
  /// reaching for something underneath it.
  Future<void> hideKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    // The IME closes on its own schedule; layout is only final once the
    // device stops reporting a bottom inset.
    final end = DateTime.now().add(const Duration(seconds: 3));
    while (tester.view.viewInsets.bottom > 0 && DateTime.now().isBefore(end)) {
      await pump(const Duration(milliseconds: 100));
    }
    await pumpAndTrySettle();
  }

  /// Brings [target] on screen. A widget that is already built is scrolled
  /// into view by its own scrollable, in whichever direction it needs; one a
  /// lazy list has not built yet is found by dragging [scrollIn].
  Future<void> reveal(PatrolFinder target, {Finder? scrollIn}) async {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target.first);
      await pumpAndTrySettle();
    } else {
      await target.scrollTo(view: scrollIn);
    }
    if (target.hitTestable().evaluate().isEmpty) {
      throw TestFailure('$target is not tappable.\n${_whatCovers(target)}');
    }
  }

  String _whatCovers(PatrolFinder target) {
    final rect = tester.getRect(target.first);
    final view = tester.view;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, rect.center, view.viewId);
    final hits = result.path
        .take(6)
        .map((e) => e.target.runtimeType.toString())
        .join(' > ');
    return 'rect=$rect screen=${view.physicalSize / view.devicePixelRatio} '
        'insets=${view.viewInsets.bottom / view.devicePixelRatio} '
        'hit at centre: $hits\n${describeScreen(this)}';
  }

  /// Types into [field] and puts the keyboard away again. Pass [scrollIn]
  /// when the field may be off screen.
  Future<void> typeInto(
    PatrolFinder field,
    String text, {
    Finder? scrollIn,
  }) async {
    await reveal(field, scrollIn: scrollIn);
    await field.enterText(text);
    await hideKeyboard();
  }

  /// The add/edit transaction form's own list.
  ///
  /// Always scroll with an explicit view: Patrol's default drags the first
  /// `Scrollable` in the tree, which on a pushed screen can be the dashboard
  /// underneath, and that drag lands on (and mis-scrolls) the form.
  PatrolFinder get transactionFormList => this(Form).$(Scrollable).first;

  /// Taps [target] inside the open bottom sheet, scrolling the sheet (not the
  /// screen behind it) until it is on screen.
  Future<void> tapInSheet(Object target) async {
    await hideKeyboard();
    final inSheet = sheet.$(target);
    await reveal(inSheet, scrollIn: sheet.$(Scrollable).first);
    await inSheet.tap();
  }

  // ---- Auth ---------------------------------------------------------------

  Future<void> openEmailForm() => this('Continue with Email').tap();

  Future<void> fillCredentials(String email, String password) async {
    await typeInto(this(TextFormField).at(0), email);
    await typeInto(this(TextFormField).at(1), password);
  }

  /// From the login screen's first view.
  Future<void> signInWithEmail(String email, String password) async {
    await openEmailForm();
    await fillCredentials(email, password);
    await this(FilledButton).$('Sign in').tap();
  }

  /// From the login screen's first view.
  Future<void> signUpWithEmail(String email, String password) async {
    await openEmailForm();
    await this("Don't have an account? Sign up").tap();
    await fillCredentials(email, password);
    await this(FilledButton).$('Create account').tap();
  }

  /// Waits for the signed-in home screen.
  Future<void> expectDashboard() => waitForScreen(this, 'AVAILABLE BALANCE');

  // ---- Navigation ---------------------------------------------------------

  Future<void> openTab(String label) =>
      this(NavigationBar).$(NavigationDestination).$(label).tap();

  Future<void> openSettings() async {
    await this(find.byTooltip('Profile & settings')).tap();
    await this('Profile & settings').waitUntilVisible();
  }

  /// The app bar's back arrow. Settings draws its own, so this matches on
  /// the tooltip both kinds share rather than on Flutter's `BackButton`.
  Future<void> goBack() => this(find.byTooltip('Back')).first.tap();

  Future<void> leaveSettings() => goBack();

  // ---- Transactions -------------------------------------------------------

  /// Adds a transaction through the FAB on the current tab, the way a user
  /// would: choose the type, type the amount, pick a category, save.
  Future<void> addTransaction({
    required TransactionType type,
    required double amount,
    String? category,
    String? note,
    String? payWithCard,
  }) async {
    try {
      await _addTransaction(type, amount, category, note, payWithCard);
    } on TestFailure {
      rethrow;
    } on Object catch (e) {
      throw TestFailure(
        'Adding a transaction failed: $e\n${describeScreen(this)}',
      );
    }
  }

  Future<void> _addTransaction(
    TransactionType type,
    double amount,
    String? category,
    String? note,
    String? payWithCard,
  ) async {
    // A keyboard still closing from an earlier form shrinks the type sheet
    // below its content. Nobody taps that fast, so wait it out.
    await hideKeyboard();
    await this(FloatingActionButton).$('Add').tap();
    await sheet.$(type == TransactionType.income ? 'Income' : 'Expense').tap();
    await this(
      type == TransactionType.income ? 'Add income' : 'Add expense',
    ).waitUntilVisible();

    await typeInto(amountField, _plain(amount));
    if (category != null) {
      // The chip, not its label: a chip hit-tests as one box, so the text
      // inside it never registers as tappable on its own.
      final chip = this(ChoiceChip).containing(category);
      await reveal(chip, scrollIn: transactionFormList);
      await chip.tap();
    }
    if (note != null) {
      await typeInto(noteField, note, scrollIn: transactionFormList);
    }
    if (payWithCard != null) {
      await reveal(this('Payment method'), scrollIn: transactionFormList);
      await this('Payment method').tap();
      await tapInSheet(this(ListTile).$(payWithCard));
    }
    await this(FilledButton).$('Add transaction').tap();
    await this('Transaction added').waitUntilVisible();
  }

  // Never by index: the form is a lazy list, so which fields exist changes
  // as it scrolls. The amount is always first; the note is found by its hint,
  // which Material keeps in the tree even once the field has text, and which
  // `reveal` can scroll to before the field is built.
  PatrolFinder get amountField => this(TextFormField).first;
  PatrolFinder get noteField =>
      this(TextFormField).containing('What was this for? (optional)');

  /// Removes and dismisses the success toast so it cannot hide what is next.
  Future<void> dismissSnackBars() async {
    ScaffoldMessenger.of(
      tester.element(this(Scaffold).first),
    ).removeCurrentSnackBar();
    await pumpAndTrySettle();
  }

  /// Waits for something driven by a background sync or stream to happen.
  Future<void> eventually(
    Future<bool> Function() condition, {
    Duration timeout = const Duration(seconds: 10),
    String? reason,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (await condition()) return;
      await pump(const Duration(milliseconds: 200));
    }
    fail(reason ?? 'Condition not met within $timeout');
  }
}

String _plain(double amount) =>
    amount == amount.roundToDouble() ? amount.toInt().toString() : '$amount';
