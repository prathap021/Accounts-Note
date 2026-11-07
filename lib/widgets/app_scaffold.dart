import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../core/services/app_update_service.dart';
import '../core/services/notifications.dart';
import '../providers/automation_provider.dart';
import '../core/sync/background_sync.dart';
import '../providers/subscription_provider.dart';
import '../providers/sync_provider.dart';

/// Persistent bottom navigation for top-level tabs (ShellRoute).
/// Also starts the subscription controller, which must be listening to the
/// store from the moment the signed-in app opens.
class AppScaffold extends ConsumerStatefulWidget {
  final Widget child;
  const AppScaffold({super.key, required this.child});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold>
    with WidgetsBindingObserver {
  static const _tabs = [
    ('/dashboard', Icons.home_outlined, Icons.home_rounded, 'Home'),
    (
      '/transactions',
      Icons.receipt_long_outlined,
      Icons.receipt_long_rounded,
      'Activity'
    ),
    ('/budgets', Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded,
        'Budgets'),
    ('/reports', Icons.insights_outlined, Icons.insights_rounded, 'Reports'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BackgroundSync.setAppInForeground(true);
    // After the first frame, so none of this delays the dashboard.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ref.read(appUpdateControllerProvider.notifier).checkOnLaunch();
      final notifications = ref.read(appNotificationsProvider);
      await notifications.init();
      _taps = notifications.taps.listen(_openFromNotification);
      final launchedWith = await notifications.launchAction();
      if (launchedWith != null) _openFromNotification(launchedWith);
      if (!mounted) return;
      await ref.read(notificationSettingsProvider.notifier).reapply();
      _runRecurring();
    });
  }

  StreamSubscription<String>? _taps;

  /// Makes any recurring entries that came due, once the device ledger is
  /// open (and again whenever the app returns to the front).
  Future<void> _runRecurring() async {
    final ready = await ref.read(localStoreReadyProvider.future);
    if (!ready || !mounted) return;
    final added = await ref.read(recurringRunnerProvider).run();
    if (added > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Added $added recurring '
            '${added == 1 ? 'entry' : 'entries'} that came due.',
          ),
        ),
      );
    }
  }

  void _openFromNotification(String action) {
    if (!mounted) return;
    switch (action) {
      case NotificationAction.addExpense:
        context.push('/transaction/add', extra: TransactionType.expense);
      case NotificationAction.openBudgets:
        context.go('/budgets');
    }
  }

  @override
  void dispose() {
    _taps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    BackgroundSync.setAppInForeground(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is a good moment to flush anything that piled up
    // while it was in the background.
    final resumed = state == AppLifecycleState.resumed;
    // Tells the background isolate whether the UI is live, so the two never
    // hold the same Hive box open at once.
    BackgroundSync.setAppInForeground(resumed);
    if (resumed) {
      ref.read(syncManagerProvider).syncNow();
      // Picks up an update that finished downloading while the app was away.
      ref.read(appUpdateControllerProvider.notifier).checkOnLaunch();
      _runRecurring();
    } else {
      // Leaving the app: hand anything still queued to the OS scheduler.
      final sync = ref.read(syncManagerProvider);
      if (sync.state.hasWork) BackgroundSync.scheduleWhenOnline();
    }
  }

  int _currentIndex(String location) {
    final index = _tabs.indexWhere((t) => location.startsWith(t.$1));
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _currentIndex(location);
    final scheme = Theme.of(context).colorScheme;

    // Purchases can arrive at any time (a renewal on launch, a purchase that
    // finished while the app was closed), so the controller is kept listening
    // for the whole session, not only while the plan screen is open. A
    // provider nothing listens to is paused, hence a listener, not a read.
    ref.listen(subscriptionControllerProvider, (_, _) {});

    // A background update has downloaded: offer the restart, never force it.
    ref.listen<AppUpdateState>(appUpdateControllerProvider, (prev, next) {
      if (next.phase != UpdatePhase.readyToInstall ||
          prev?.phase == UpdatePhase.readyToInstall) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(days: 1),
          content: const Text('An update is ready to install.'),
          action: SnackBarAction(
            label: 'Restart',
            onPressed: () =>
                ref.read(appUpdateControllerProvider.notifier).install(),
          ),
        ),
      );
    });

    final dark = Theme.of(context).brightness == Brightness.dark;
    const barRadius = BorderRadius.all(Radius.circular(28));

    return Scaffold(
      // The bar floats on the canvas, but pages stop above it (no
      // extendBody): each tab's own Scaffold places its button relative to
      // its own bottom edge, which would otherwise sit behind the bar.
      body: widget.child,
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: barRadius,
              border: dark ? Border.all(color: scheme.outlineVariant) : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.4 : 0.10),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: barRadius,
              child: NavigationBar(
                selectedIndex: currentIndex,
                onDestinationSelected: (i) {
                  if (i == currentIndex) return;
                  HapticFeedback.selectionClick();
                  context.go(_tabs[i].$1);
                },
                destinations: [
                  for (final tab in _tabs)
                    NavigationDestination(
                      icon: Icon(tab.$2),
                      selectedIcon: Icon(tab.$3),
                      label: tab.$4,
                      tooltip: tab.$4,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
