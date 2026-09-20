import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:income_expense_tracker/core/constants/app_constants.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/verify_email_screen.dart';
import '../../features/budgets/budgets_screen.dart';
import '../../features/categories/categories_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/contribute/contribute_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/transactions/add_edit_transaction_screen.dart';
import '../../features/transactions/transactions_screen.dart';
import '../../models/transaction_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../widgets/app_scaffold.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final hasSeenOnboarding = ref.watch(settingsProvider).hasSeenOnboarding;
  // Only email/password accounts are gated; Google and Apple verify the
  // address themselves.
  final needsVerification = ref.watch(needsEmailVerificationProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
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
    refreshListenable: GoRouterRefreshStream(ref),
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
          GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
          GoRoute(path: '/transactions', builder: (_, _) => const TransactionsScreen()),
          GoRoute(path: '/budgets', builder: (_, _) => const BudgetsScreen()),
          GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
        ],
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/contribute', builder: (_, _) => const ContributeScreen()),
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
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
});

/// Bridges a Riverpod stream to GoRouter's Listenable-based refresh API so
/// login/logout immediately triggers a redirect re-evaluation.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
}
