import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/contribute/contribution_dialogs.dart';
import '../core/sync/background_sync.dart';
import '../providers/contribution_provider.dart';
import '../providers/sync_provider.dart';

/// Persistent bottom navigation for top-level tabs (ShellRoute).
/// Also hosts the optional contribution prompt (never blocks transactions).
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

  bool _promptInFlight = false;
  bool _promptScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BackgroundSync.setAppInForeground(true);
  }

  @override
  void dispose() {
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

  void _scheduleContributionPrompt() {
    if (_promptInFlight || _promptScheduled || !mounted) return;
    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _promptScheduled = false;
      if (!mounted) return;
      if (!ref.read(shouldShowContributionPromptProvider)) return;
      await _presentContributionPrompt();
    });
  }

  Future<void> _presentContributionPrompt() async {
    if (_promptInFlight || !mounted) return;
    _promptInFlight = true;
    try {
      final result = await showContributionPromptDialog(context);
      if (!mounted) return;
      final actions = ref.read(contributionActionsProvider.notifier);
      if (result == ContributionPromptResult.contribute) {
        await actions.markPromptShownToday();
        if (mounted) context.push('/contribute');
      } else {
        // Not Now or barrier dismiss — suppress for the rest of today.
        await actions.declinePromptForToday();
      }
    } finally {
      _promptInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _currentIndex(location);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<bool>(shouldShowContributionPromptProvider, (prev, next) {
      if (next) _scheduleContributionPrompt();
    });

    if (ref.watch(shouldShowContributionPromptProvider)) {
      _scheduleContributionPrompt();
    }

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
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
    );
  }
}
