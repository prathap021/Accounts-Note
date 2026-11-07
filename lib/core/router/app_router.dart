import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';

import '../../features/accounts/accounts_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/verify_email_screen.dart';
import '../../features/budgets/budgets_screen.dart';
import '../../features/categories/categories_screen.dart';
import '../../features/credit_cards/credit_cards_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/recurring/recurring_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/subscription/subscription_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/transactions/add_edit_transaction_screen.dart';
import '../../features/transactions/transactions_screen.dart';
import '../../models/transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/double_back_to_exit.dart';

/// One router for the life of the app.
///
/// The auth and settings state is read inside [GoRouter.redirect], not
/// watched here. Watching would build a fresh router, back at `/splash`, every
/// time `userChanges()` emits. Firebase emits on every profile reload and ID
/// token refresh, so saving a display name or simply staying signed in for an
/// hour would throw the user out of whatever screen they were on. Changes
/// reach the router through [GoRouterRefreshStream] instead, which re-runs
/// [GoRouter.redirect] without touching the navigation stack.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = GoRouterRefreshStream(ref);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final hasSeenOnboarding = ref.read(settingsProvider).hasSeenOnboarding;
      // Only email/password accounts are gated; Google and Apple verify the
      // address themselves.
      final needsVerification = ref.read(needsEmailVerificationProvider);

      final isLoading = authState.isLoading;
      final isLoggedIn = authState.asData?.value != null;
      final loc = state.matchedLocation;

      if (isLoading) return loc == '/splash' ? null : '/splash';
      if (!isLoggedIn) {
        if (!hasSeenOnboarding && loc != '/onboarding') {
          return '/onboarding';
        }
        if (hasSeenOnboarding && loc != '/login') {
          return '/login';
        }
        return null;
      }
      // Signed in but the address is unconfirmed: hold here until it is.
      if (needsVerification) {
        return loc == '/verify-email' ? null : '/verify-email';
      }
      // Verified (or a provider that never needed it) — never strand the user
      // on the verification screen.
      if (loc == '/verify-email') return '/dashboard';

      if (isLoggedIn && (loc == '/login' || loc == '/splash' || loc == '/onboarding')) return '/dashboard';
      return null;
    },
    refreshListenable: refresh,
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/verify-email',
        builder: (_, _) => const VerifyEmailScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppScaffold(child: child),
        routes: [
          // Each tab carries its own back handling. It has to sit inside the
          // shell's Navigator rather than around it: a Navigator announces
          // "nothing to pop" to the platform on every history change, and
          // that announcement would overwrite one made above it, leaving
          // Android to close the app without ever asking Flutter.
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => const _BackHandledTab(
              atHome: true,
              child: DashboardScreen(),
            ),
          ),
          GoRoute(
            path: '/transactions',
            builder: (_, _) => const _BackHandledTab(
              child: TransactionsScreen(),
            ),
          ),
          GoRoute(
            path: '/budgets',
            builder: (_, _) => const _BackHandledTab(child: BudgetsScreen()),
          ),
          GoRoute(
            path: '/reports',
            builder: (_, _) => const _BackHandledTab(child: ReportsScreen()),
          ),
        ],
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/recurring',
        builder: (_, _) => const RecurringScreen(),
      ),
      GoRoute(
        path: '/subscription',
        builder: (_, _) => const SubscriptionScreen(),
      ),
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
      GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
      GoRoute(
        path: '/credit-cards',
        builder: (_, _) => const CreditCardsScreen(),
      ),
      GoRoute(
        path: '/transaction/add',
        builder: (_, state) {
          final type = state.extra as TransactionType? ?? TransactionType.expense;
          return AddEditTransactionScreen(initialType: type);
        },
      ),
      GoRoute(
        path: '/transaction/edit',
        builder: (_, state) {
          final tx = state.extra as TransactionModel;
          return AddEditTransactionScreen(existing: tx);
        },
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Bridges Riverpod state to GoRouter's Listenable-based refresh API, so
/// sign-in, sign-out, verification and finishing onboarding immediately
/// re-run the redirect.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(needsEmailVerificationProvider, (_, _) => notifyListeners());
    ref.listen(
      settingsProvider.select((s) => s.hasSeenOnboarding),
      (_, _) => notifyListeners(),
    );
  }
}

/// A top-level tab, with the app's root back behaviour attached.
///
/// Switching tabs replaces this page, so the "pressed back once" state resets
/// whenever the user leaves and returns to the home tab — which is what makes
/// a press that merely navigated home safe rather than half an exit.
class _BackHandledTab extends StatelessWidget {
  final Widget child;
  final bool atHome;

  const _BackHandledTab({required this.child, this.atHome = false});

  @override
  Widget build(BuildContext context) {
    return DoubleBackToExit(
      atHome: atHome,
      onReturnHome: () => context.go('/dashboard'),
      child: child,
    );
  }
}
