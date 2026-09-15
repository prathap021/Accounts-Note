import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:income_expense_tracker/models/transaction_model.dart';
import 'package:income_expense_tracker/widgets/summary_card.dart';
import 'package:income_expense_tracker/widgets/transaction_tile.dart';

TransactionModel _tx(TransactionType type) => TransactionModel(
      id: 'tx-${type.name}',
      type: type,
      amount: 1234.5,
      categoryId: 'c1',
      categoryName: 'Groceries',
      note: 'Weekly shop',
      date: DateTime(2026, 9, 15, 10, 30),
      paymentMethod: 'UPI',
      createdAt: DateTime(2026, 9, 15),
      updatedAt: DateTime(2026, 9, 15),
    );

Widget _host(Widget child, ThemeData theme) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: child,
        ),
      ),
    );

void main() {
  // AppTheme builds a google_fonts text theme, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  final gallery = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const BalanceHeroCard(
        label: 'SEPTEMBER 2026',
        amount: '₹1,20,000.00',
        subtitle: 'One Lakh Twenty Thousand rupees',
      ),
      const SizedBox(height: AppSpacing.md),
      const Row(
        children: [
          Expanded(
            child: SummaryCard(
              label: 'Income',
              value: '₹40,000.00',
              caption: 'This month',
              icon: Icons.south_west_rounded,
              color: AppColors.income,
            ),
          ),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: SummaryCard(
              label: 'Expenses',
              value: '₹12,340.00',
              caption: 'This month',
              icon: Icons.north_east_rounded,
              color: AppColors.expense,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      const SectionHeader(title: 'Recent activity', actionLabel: null),
      const SectionLabel('Preferences'),
      AppCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            TransactionTile(transaction: _tx(TransactionType.income)),
            TransactionTile(
              transaction: _tx(TransactionType.expense),
              showDate: false,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions yet',
        message: 'Log your first income or expense.',
        actionLabel: 'Add transaction',
      ),
      const AppErrorState(),
      const SizedBox(height: AppSpacing.md),
      const SkeletonBox(height: 60),
      const SizedBox(height: AppSpacing.md),
      const HeaderAction(icon: Icons.tune_rounded, tooltip: 'Filter'),
    ],
  );

  for (final brightness in Brightness.values) {
    testWidgets('shared UI primitives render in ${brightness.name} theme',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Built inside the test so google_fonts resolves within the test zone.
      final theme = brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark();
      await tester.pumpWidget(_host(gallery, theme));
      await tester.pump(const Duration(milliseconds: 700));

      expect(tester.takeException(), isNull);
    });
  }

  // Regression: the button theme once set `minimumSize: Size.fromHeight(52)`,
  // which is Size(infinity, 52). That lays out fine wherever the parent gives
  // a tight width (forms, stretch columns) but asserts "BoxConstraints forces
  // an infinite width" wherever width is unbounded — a Row measures non-flex
  // children unbounded, and so does an AlertDialog's action bar.
  group('buttons survive unbounded width', () {
    testWidgets('in a Row alongside other content', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mirrors the onboarding footer: indicator + button in a Row,
                // which is where the infinite-width assert actually fired.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Page 1 of 2'),
                    FilledButton(onPressed: () {}, child: const Text('Next')),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Not now'),
                    OutlinedButton(onPressed: () {}, child: const Text('Skip')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('as dialog actions', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete this transaction?'),
                  content: const Text('This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('Cancel')),
                    FilledButton(onPressed: () {}, child: const Text('Delete')),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('sliver page header lays out inside a CustomScrollView',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: CustomScrollView(
          slivers: [
            AppSliverHeader(
              eyebrow: 'Good morning',
              title: 'Prathap',
              actions: [
                HeaderAction(icon: Icons.tune_rounded, tooltip: 'Filter'),
              ],
            ),
            SliverToBoxAdapter(child: SizedBox(height: 400)),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Prathap'), findsOneWidget);
    expect(find.text('Good morning'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
