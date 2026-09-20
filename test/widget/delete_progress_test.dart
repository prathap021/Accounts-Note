import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/core/theme/app_theme.dart';
import 'package:income_expense_tracker/features/settings/delete_account_progress.dart';

/// Account deletion runs for several seconds and cannot be cancelled, so the
/// dialog has to show which step is running and which are finished.
void main() {
  Future<ValueNotifier<DeleteStage>> pump(
    WidgetTester tester, {
    required bool includesBackup,
    DeleteStage initial = DeleteStage.data,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final stage = ValueNotifier<DeleteStage>(initial);
    addTearDown(stage.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: DeleteAccountProgress(
        stage: stage,
        includesBackup: includesBackup,
      ),
    ));
    await tester.pump();
    return stage;
  }

  group('steps shown', () {
    testWidgets('backup is listed only when it was chosen', (tester) async {
      await pump(tester, includesBackup: true);
      expect(find.text(DeleteStage.backup.label), findsOneWidget);
      expect(find.text(DeleteStage.data.label), findsOneWidget);
      expect(find.text(DeleteStage.account.label), findsOneWidget);
    });

    testWidgets('backup is absent when it was not chosen', (tester) async {
      await pump(tester, includesBackup: false);
      expect(find.text(DeleteStage.backup.label), findsNothing,
          reason: 'a step that never runs must not be shown as pending');
      expect(find.text(DeleteStage.data.label), findsOneWidget);
    });
  });

  group('progress', () {
    testWidgets('the running step shows a spinner', (tester) async {
      await pump(tester, includesBackup: false, initial: DeleteStage.data);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('finished steps are ticked once the stage advances',
        (tester) async {
      final stage = await pump(
        tester,
        includesBackup: true,
        initial: DeleteStage.backup,
      );

      // Nothing is complete yet.
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      stage.value = DeleteStage.account;
      await tester.pump();

      // Backup and data are behind us now.
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    });

    testWidgets('every step is ticked when the whole thing is done',
        (tester) async {
      final stage = await pump(tester, includesBackup: true);
      stage.value = DeleteStage.done;
      await tester.pump();

      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
    });
  });

  group('completion', () {
    testWidgets('the heading changes and promises the next step',
        (tester) async {
      final stage = await pump(tester, includesBackup: false);
      expect(find.text('Deleting your account'), findsOneWidget);
      // The step label stays distinct from the heading.
      expect(find.text(DeleteStage.account.label), findsOneWidget);

      stage.value = DeleteStage.done;
      await tester.pump();

      expect(find.text('Account closed'), findsOneWidget);
      expect(find.textContaining('back to sign in'), findsOneWidget);
    });
  });

  testWidgets('cannot be dismissed with the back gesture', (tester) async {
    await pump(tester, includesBackup: false);
    final popScope = tester.widget<PopScope>(find.byType(PopScope));
    expect(popScope.canPop, isFalse,
        reason: 'leaving mid-delete would strand a half-removed account');
  });
}
