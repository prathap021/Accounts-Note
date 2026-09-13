import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Persistent bottom navigation for top-level tabs (ShellRoute).
class AppScaffold extends StatelessWidget {
  final Widget child;
  const AppScaffold({super.key, required this.child});

  static const _tabs = [
    ('/dashboard', Icons.home_outlined, Icons.home_rounded, 'Home'),
    ('/transactions', Icons.receipt_long_outlined, Icons.receipt_long_rounded,
        'Activity'),
    ('/budgets', Icons.pie_chart_outline_rounded, Icons.pie_chart_rounded,
        'Budgets'),
    ('/reports', Icons.insights_outlined, Icons.insights_rounded, 'Reports'),
  ];

  int _currentIndex(String location) {
    final index = _tabs.indexWhere((t) => location.startsWith(t.$1));
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _currentIndex(location);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: (i) => context.go(_tabs[i].$1),
          destinations: [
            for (final tab in _tabs)
              NavigationDestination(
                icon: Icon(tab.$2),
                selectedIcon: Icon(tab.$3),
                label: tab.$4,
              ),
          ],
        ),
      ),
    );
  }
}
