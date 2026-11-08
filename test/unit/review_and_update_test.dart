import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:accounts_note/core/services/app_review_service.dart';
import 'package:accounts_note/core/services/app_update_service.dart';
import 'package:accounts_note/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppUpdateInfo info({
  UpdateAvailability availability = UpdateAvailability.updateAvailable,
  InstallStatus status = InstallStatus.unknown,
  bool immediate = true,
  bool flexible = true,
  int priority = 0,
  int? staleDays,
}) => AppUpdateInfo(
  updateAvailability: availability,
  immediateUpdateAllowed: immediate,
  immediateAllowedPreconditions: null,
  flexibleUpdateAllowed: flexible,
  flexibleAllowedPreconditions: null,
  availableVersionCode: 42,
  installStatus: status,
  packageName: 'com.accountsnote.app',
  clientVersionStalenessDays: staleDays,
  updatePriority: priority,
);

class _FakeReview implements StoreReview {
  bool available = true;
  int requests = 0;
  String? openedWith;
  bool opened = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async => requests++;

  @override
  Future<void> openStoreListing({String? appStoreId}) async {
    opened = true;
    openedWith = appStoreId;
  }
}

class _FakeUpdates implements UpdateClient {
  _FakeUpdates(this.next);

  AppUpdateInfo next;
  bool throwOnCheck = false;
  AppUpdateResult flexibleResult = AppUpdateResult.success;
  int immediateCalls = 0;
  int flexibleCalls = 0;
  int completeCalls = 0;
  final status = StreamController<InstallStatus>.broadcast();

  @override
  Future<AppUpdateInfo> checkForUpdate() async {
    if (throwOnCheck) throw Exception('ERROR_API_NOT_AVAILABLE');
    return next;
  }

  @override
  Future<AppUpdateResult> performImmediateUpdate() async {
    immediateCalls++;
    return AppUpdateResult.userDeniedUpdate;
  }

  @override
  Future<AppUpdateResult> startFlexibleUpdate() async {
    flexibleCalls++;
    return flexibleResult;
  }

  @override
  Future<void> completeFlexibleUpdate() async => completeCalls++;

  @override
  Stream<InstallStatus> get installStatus => status.stream;
}

void main() {
  group('UpdatePolicy', () {
    final now = DateTime(2026, 11, 7);

    UpdateDecision decide(
      AppUpdateInfo i, {
      DateTime? declined,
      bool asked = false,
    }) => UpdatePolicy.decide(
      i,
      lastDeclined: declined,
      now: now,
      userAsked: asked,
    );

    test('a normal release downloads in the background', () {
      expect(decide(info()), UpdateDecision.flexible);
    });

    test('a high-priority release is blocking', () {
      expect(decide(info(priority: 4)), UpdateDecision.immediate);
      expect(decide(info(priority: 5)), UpdateDecision.immediate);
    });

    test('a month without updating makes it blocking', () {
      expect(decide(info(staleDays: 30)), UpdateDecision.immediate);
      expect(decide(info(staleDays: 29)), UpdateDecision.flexible);
    });

    test('a declined update waits 3 days, unless the user asks', () {
      final yesterday = now.subtract(const Duration(days: 1));
      expect(decide(info(), declined: yesterday), UpdateDecision.none);
      expect(
        decide(info(), declined: yesterday, asked: true),
        UpdateDecision.flexible,
      );
      expect(
        decide(info(), declined: now.subtract(const Duration(days: 4))),
        UpdateDecision.flexible,
      );
    });

    test('a finished download is offered for restart', () {
      expect(
        decide(info(status: InstallStatus.downloaded)),
        UpdateDecision.readyToInstall,
      );
    });

    test('an interrupted blocking update resumes', () {
      expect(
        decide(
          info(
            availability: UpdateAvailability.developerTriggeredUpdateInProgress,
          ),
        ),
        UpdateDecision.resumeImmediate,
      );
    });

    test('nothing to do when up to date', () {
      expect(
        decide(info(availability: UpdateAvailability.updateNotAvailable)),
        UpdateDecision.none,
      );
    });
  });

  group('AppUpdateController', () {
    late _FakeUpdates updates;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      updates = _FakeUpdates(info());
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          updateClientProvider.overrideWithValue(updates),
          inAppUpdateSupportedProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      container.listen(appUpdateControllerProvider, (_, _) {});
    });

    AppUpdateController controller() =>
        container.read(appUpdateControllerProvider.notifier);
    UpdatePhase phase() => container.read(appUpdateControllerProvider).phase;

    test('downloads in the background, then waits for the restart', () async {
      await controller().checkOnLaunch();
      expect(updates.flexibleCalls, 1);
      expect(phase(), UpdatePhase.downloading);

      updates.status.add(InstallStatus.downloaded);
      await Future<void>.delayed(Duration.zero);
      expect(phase(), UpdatePhase.readyToInstall);
      expect(updates.completeCalls, 0, reason: 'never restarts on its own');

      await controller().install();
      expect(updates.completeCalls, 1);
    });

    test('checks once per session on launch', () async {
      updates.next = info(availability: UpdateAvailability.updateNotAvailable);
      await controller().checkOnLaunch();
      await controller().checkOnLaunch();
      expect(phase(), UpdatePhase.upToDate);
      updates.next = info();
      await controller().checkOnLaunch();
      expect(updates.flexibleCalls, 0);
    });

    test('a declined update is not offered again on the next launch', () async {
      updates.flexibleResult = AppUpdateResult.userDeniedUpdate;
      await controller().checkOnLaunch();
      expect(phase(), UpdatePhase.idle);

      final next = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            container.read(sharedPreferencesProvider),
          ),
          updateClientProvider.overrideWithValue(updates),
          inAppUpdateSupportedProvider.overrideWithValue(true),
        ],
      );
      addTearDown(next.dispose);
      await next.read(appUpdateControllerProvider.notifier).checkOnLaunch();
      expect(updates.flexibleCalls, 1, reason: 'asked again only after 3 days');
    });

    test('without Google Play, says updates are unavailable', () async {
      updates.throwOnCheck = true;
      await controller().checkNow();
      expect(phase(), UpdatePhase.unavailable);
    });

    test('a high-priority release opens the blocking update', () async {
      updates.next = info(priority: 5);
      await controller().checkOnLaunch();
      expect(updates.immediateCalls, 1);
    });
  });

  group('AppReviewService', () {
    late _FakeReview review;
    late SharedPreferences prefs;
    var now = DateTime(2026, 11, 7);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      review = _FakeReview();
      now = DateTime(2026, 11, 7);
    });

    AppReviewService service() =>
        AppReviewService(prefs: prefs, review: review, clock: () => now);

    Future<void> add(int n) async {
      for (var i = 0; i < n; i++) {
        await service().recordTransactionAdded();
      }
    }

    test('asks on the 5th transaction, not before', () async {
      await add(4);
      expect(review.requests, 0);
      await add(1);
      expect(review.requests, 1);
    });

    test('never twice within 60 days', () async {
      await add(5);
      await add(25); // the 30th, the same day
      expect(review.requests, 1);
    });

    test('asks again at the next milestone once 60 days have passed', () async {
      await add(5);
      now = now.add(const Duration(days: 61));
      await add(25);
      expect(review.requests, 2);
    });

    test('a device without the store sheet is never asked', () async {
      review.available = false;
      await add(5);
      expect(review.requests, 0);
    });

    test('"Rate Accounts Note" opens the store page', () async {
      await service().openStorePage();
      expect(review.opened, isTrue);
    });
  });
}
