import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Wraps every top-level tab in a persistent bottom navigation bar.
/// Using GoRouter's ShellRoute means the tab state (scroll position etc.)
/// is preserved when switching tabs, unlike pushing new pages.
class AppScaffold extends StatelessWidget {
  final Widget child;
  const AppScaffold({super.key, required this.child});

  static const _tabs = [
    ('/dashboard', Icons.dashboard_outlined, Icons.dashboard, 'Home'),
    ('/transactions', Icons.receipt_long_outlined, Icons.receipt_long, 'Transactions'),
    ('/budgets', Icons.pie_chart_outline, Icons.pie_chart, 'Budgets'),
    ('/reports', Icons.bar_chart_outlined, Icons.bar_chart, 'Reports'),
    ('/settings', Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  int _currentIndex(String location) {
    final index = _tabs.indexWhere((t) => location.startsWith(t.$1));
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _currentIndex(location);

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
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
    );
  }
}
