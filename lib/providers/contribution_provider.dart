import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/result.dart';
import '../data/repositories/contribution_repository.dart';
import '../models/app_user_model.dart';
import 'auth_provider.dart';

final contributionRepositoryProvider = Provider<ContributionRepository>((ref) {
  return ContributionRepository();
});

final userProfileProvider = StreamProvider<AppUserModel?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(contributionRepositoryProvider).watchProfile(uid);
});

final isContributorProvider = Provider<bool>((ref) {
  return ref.watch(userProfileProvider).asData?.value?.isContributor ?? false;
});

/// Whether the optional contribution dialog should appear (non-blocking).
final shouldShowContributionPromptProvider = Provider<bool>((ref) {
  final profile = ref.watch(userProfileProvider).asData?.value;
  if (profile == null) return false;
  return profile.shouldShowContributionPrompt();
});

class ContributionActionsNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<Result<void>> contribute(
    double amountUsd, {
    String supportType = 'one_time',
    String? featureNote,
  }) async {
    state = const AsyncLoading();
    final result = await ref
        .read(contributionRepositoryProvider)
        .startContribution(
          amountUsd,
          supportType: supportType,
          featureNote: featureNote,
        );
    result.when(
      success: (_) => state = const AsyncData(null),
      failure: (f) => state = AsyncError(f, StackTrace.current),
    );
    return result;
  }

  /// Not Now / dialog dismissed — suppress for the rest of today.
  Future<void> declinePromptForToday() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    await ref.read(contributionRepositoryProvider).markContributionPromptHandled(
          uid,
          declined: true,
        );
  }

  /// Dialog shown and user chose Contribute — suppress re-show today.
  Future<void> markPromptShownToday() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    await ref.read(contributionRepositoryProvider).markContributionPromptHandled(
          uid,
          declined: false,
        );
  }
}

final contributionActionsProvider =
    NotifierProvider<ContributionActionsNotifier, AsyncValue<void>>(
  ContributionActionsNotifier.new,
);

/// Kept for any leftover references; income/expense are never blocked.
@Deprecated('Contribution no longer gates transactions')
final isUnlockedProvider = isContributorProvider;
