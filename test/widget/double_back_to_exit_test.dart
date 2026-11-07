import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:income_expense_tracker/widgets/double_back_to_exit.dart';

/// Back at the app's root is the one gesture that can throw away what the
/// user was doing, so the rules are pinned here: never leave from a tab, and
/// never leave on a single press.
void main() {
  group('shouldExitOnBack', () {
    final now = DateTime(2026, 11, 3, 10, 0, 0);

    test('a first press never exits', () {
      expect(shouldExitOnBack(lastPress: null, now: now), isFalse);
    });

    test('a second press inside the window exits', () {
      expect(
        shouldExitOnBack(
          lastPress: now.subtract(const Duration(milliseconds: 800)),
          now: now,
        ),
        isTrue,
      );
    });

    test('a second press after the window does not', () {
      expect(
        shouldExitOnBack(
          lastPress: now.subtract(const Duration(seconds: 5)),
          now: now,
        ),
        isFalse,
      );
    });

    test('the window boundary counts as inside', () {
      expect(
        shouldExitOnBack(
          lastPress: now.subtract(kDoubleBackWindow),
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldExitOnBack(
          lastPress: now.subtract(kDoubleBackWindow + const Duration(milliseconds: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('a backwards clock jump does not exit on one press', () {
      // NTP correction or a manual change: the previous press now reads as
      // being in the future, which must not be mistaken for "just now".
      expect(
        shouldExitOnBack(
          lastPress: now.add(const Duration(hours: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('honours a custom window', () {
      expect(
        shouldExitOnBack(
          lastPress: now.subtract(const Duration(seconds: 4)),
          now: now,
          window: const Duration(seconds: 5),
        ),
        isTrue,
      );
    });
  });

  group('behaviour', () {
    late int exits;
    late int returnsHome;

    setUp(() {
      exits = 0;
      returnsHome = 0;
    });

    Future<void> pump(
      WidgetTester tester, {
      required bool atHome,
      Duration window = kDoubleBackWindow,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: DoubleBackToExit(
          atHome: atHome,
          window: window,
          onReturnHome: () => returnsHome++,
          onExit: () => exits++,
          child: const Scaffold(body: Text('content')),
        ),
      ));
      await tester.pump();
    }

    /// The Android back button, as the framework delivers it.
    Future<void> pressBack(WidgetTester tester) async {
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pump();
    }

    testWidgets('back from another tab goes home instead of exiting',
        (tester) async {
      await pump(tester, atHome: false);
      await pressBack(tester);

      expect(returnsHome, 1);
      expect(exits, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the first back at home warns rather than exits',
        (tester) async {
      await pump(tester, atHome: true);
      await pressBack(tester);

      expect(exits, 0);
      expect(find.text('Press back again to exit'), findsOneWidget);
    });

    testWidgets('a second back at home exits', (tester) async {
      await pump(tester, atHome: true);
      await pressBack(tester);
      await pressBack(tester);

      expect(exits, 1);
    });

    testWidgets('a second back after the window warns again instead',
        (tester) async {
      await pump(tester, atHome: true, window: const Duration(milliseconds: 30));
      await pressBack(tester);

      // Real elapsed time: the widget reads the wall clock, which fake async
      // does not advance.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );

      await pressBack(tester);
      expect(exits, 0);
      expect(find.text('Press back again to exit'), findsOneWidget);
    });

    testWidgets('returning home resets the count, so one more press is safe',
        (tester) async {
      // Press back on Home (warned), switch to a tab, press back to come
      // home again — the next press must warn, not exit.
      await pump(tester, atHome: true);
      await pressBack(tester);
      expect(exits, 0);

      await pump(tester, atHome: false);
      await pressBack(tester);
      expect(returnsHome, 1);

      await pump(tester, atHome: true);
      await pressBack(tester);
      expect(exits, 0, reason: 'the press that returned home must not count');
    });
  });

  /// The bug this guards against cost a device debugging session.
  ///
  /// `PopScope` tells the platform "Flutter will handle back" by dispatching a
  /// NavigationNotification up the tree. Every Navigator also dispatches one
  /// on each history change, saying whether *it* can pop — and the last one to
  /// reach the app wins. Put this widget *above* a Navigator (as wrapping the
  /// shell's scaffold did) and that Navigator's "nothing to pop" overwrites
  /// it, so Android closes the app without ever calling into Dart. None of the
  /// tests above catch that: they drive `maybePop` directly and never involve
  /// the platform handshake.
  group('placement relative to a nested Navigator', () {
    /// What the app would pass to SystemNavigator.setFrameworkHandlesBack.
    ///
    /// Read through MaterialApp's own hook, because WidgetsApp consumes the
    /// NavigationNotification and stops it bubbling any further.
    Future<bool?> frameworkHandlesBack(
      WidgetTester tester,
      Widget Function(Widget tabContent) build,
    ) async {
      bool? latest;

      await tester.pumpWidget(
        MaterialApp(
          onNavigationNotification: (n) {
            latest = n.canHandlePop;
            return true;
          },
          home: build(const Scaffold(body: Text('tab'))),
        ),
      );
      await tester.pumpAndSettle();
      return latest;
    }

    Widget nestedNavigator(Widget page) => Navigator(
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => page),
        );

    Widget handler({required Widget child}) => DoubleBackToExit(
          atHome: true,
          onReturnHome: () {},
          onExit: () {},
          child: child,
        );

    testWidgets('above the Navigator, the claim is lost', (tester) async {
      // The arrangement that failed on a real device: the inner Navigator has
      // nothing to pop, says so last, and the platform is told Flutter will
      // not handle back — so Android closes the app without calling Dart.
      final handled = await frameworkHandlesBack(
        tester,
        (tab) => handler(child: nestedNavigator(tab)),
      );

      expect(handled, isFalse);
    });

    testWidgets('inside the Navigator, the claim reaches the app',
        (tester) async {
      // How the tabs are actually wired: the handler is the page content, so
      // the Navigator's own route reports that a pop will be handled.
      final handled = await frameworkHandlesBack(
        tester,
        (tab) => nestedNavigator(handler(child: tab)),
      );

      expect(handled, isTrue);
    });
  });
}
