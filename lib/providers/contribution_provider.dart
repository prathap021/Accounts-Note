import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/result.dart';
import '../data/repositories/contribution_repository.dart';
import 'auth_provider.dart';

final contributionRepositoryProvider = Provider<ContributionRepository>((ref) {
  return ContributionRepository();
});

final userProfileProvider = StreamProvider((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(contributionRepositoryProvider).watchProfile(uid);
});

final isUnlockedProvider = Provider<bool>((ref) {
  return ref.watch(userProfileProvider).asData?.value?.isUnlocked ?? false;
});

final transactionEntitlementProvider = Provider<TransactionEntitlement>((ref) {
  final profile = ref.watch(userProfileProvider).asData?.value;
  final limit = AppDefaults.freeDailyTransactionLimit;
  if (profile == null) {
    return const TransactionEntitlement(
      allowed: false,
      isUnlocked: false,
      usedToday: 0,
      dailyLimit: AppDefaults.freeDailyTransactionLimit,
      message: 'Sign in to add transactions.',
    );
  }
  if (profile.isUnlocked) {
    return TransactionEntitlement(
      allowed: true,
      isUnlocked: true,
      usedToday: profile.dailyTxnCount,
      dailyLimit: limit,
    );
  }
  final today = _todayKey();
  final used = profile.dailyTxnDate == today ? profile.dailyTxnCount : 0;
  final allowed = used < limit;
  return TransactionEntitlement(
    allowed: allowed,
    isUnlocked: false,
    usedToday: used,
    dailyLimit: limit,
    message: allowed
        ? null
        : 'You have used today\'s $limit free income & expense entries. '
            'You can add more again tomorrow. Contribution is optional.',
  );
});

String _todayKey() {
  final n = DateTime.now();
  final m = n.month.toString().padLeft(2, '0');
  final d = n.day.toString().padLeft(2, '0');
  return '${n.year}-$m-$d';
}

class ContributionActionsNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<Result<void>> contribute(double amountUsd) async {
    state = const AsyncLoading();
    final result = await ref
        .read(contributionRepositoryProvider)
        .startContribution(amountUsd);
    result.when(
      success: (_) => state = const AsyncData(null),
      failure: (f) => state = AsyncError(f, StackTrace.current),
    );
    return result;
  }
}

final contributionActionsProvider =
    NotifierProvider<ContributionActionsNotifier, AsyncValue<void>>(
  ContributionActionsNotifier.new,
);
