import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/settings_provider.dart';

/// What to do about an update the store reports.
enum UpdateDecision {
  /// Nothing to do: up to date, or asked recently.
  none,

  /// A blocking, full-screen update was interrupted; carry on with it.
  resumeImmediate,

  /// Download in the background while the user keeps working.
  flexible,

  /// Full-screen update the user must take before continuing.
  immediate,

  /// A background download already finished; offer the restart.
  readyToInstall,
}

/// When an update interrupts the user, and how hard.
///
/// Updates download in the background by default. Only a release marked
/// high priority in Google Play (priority 4–5, set when rolling it out), or
/// an install that has ignored updates for a month, is made blocking. Saying
/// "no" to a background update is respected for a few days.
class UpdatePolicy {
  static const immediatePriority = 4;
  static const immediateAfterStaleDays = 30;
  static const askAgainAfter = Duration(days: 3);

  static UpdateDecision decide(
    AppUpdateInfo info, {
    DateTime? lastDeclined,
    required DateTime now,
    bool userAsked = false,
  }) {
    if (info.installStatus == InstallStatus.downloaded) {
      return UpdateDecision.readyToInstall;
    }
    if (info.updateAvailability ==
        UpdateAvailability.developerTriggeredUpdateInProgress) {
      return info.immediateUpdateAllowed
          ? UpdateDecision.resumeImmediate
          : UpdateDecision.none;
    }
    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      return UpdateDecision.none;
    }
    final urgent =
        info.updatePriority >= immediatePriority ||
        (info.clientVersionStalenessDays ?? 0) >= immediateAfterStaleDays;
    if (urgent && info.immediateUpdateAllowed) return UpdateDecision.immediate;
    if (!info.flexibleUpdateAllowed) {
      return info.immediateUpdateAllowed && userAsked
          ? UpdateDecision.immediate
          : UpdateDecision.none;
    }
    final recentlyDeclined =
        lastDeclined != null && now.difference(lastDeclined) < askAgainAfter;
    if (recentlyDeclined && !userAsked) return UpdateDecision.none;
    return UpdateDecision.flexible;
  }
}

/// The Play Core calls, behind an interface so the controller can be tested.
abstract class UpdateClient {
  Future<AppUpdateInfo> checkForUpdate();
  Future<AppUpdateResult> performImmediateUpdate();
  Future<AppUpdateResult> startFlexibleUpdate();
  Future<void> completeFlexibleUpdate();
  Stream<InstallStatus> get installStatus;
}

class PlayUpdateClient implements UpdateClient {
  const PlayUpdateClient();

  @override
  Future<AppUpdateInfo> checkForUpdate() => InAppUpdate.checkForUpdate();

  @override
  Future<AppUpdateResult> performImmediateUpdate() =>
      InAppUpdate.performImmediateUpdate();

  @override
  Future<AppUpdateResult> startFlexibleUpdate() =>
      InAppUpdate.startFlexibleUpdate();

  @override
  Future<void> completeFlexibleUpdate() => InAppUpdate.completeFlexibleUpdate();

  @override
  Stream<InstallStatus> get installStatus => InAppUpdate.installUpdateListener;
}

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  downloading,
  readyToInstall,

  /// No Google Play here: an iOS build, a sideloaded APK, an emulator
  /// without the Play Store.
  unavailable,
}

@immutable
class AppUpdateState {
  final UpdatePhase phase;

  /// Bumped for every result of a check the user asked for, so the screen
  /// can tell a new answer from the one it already showed.
  final int manualCheck;

  const AppUpdateState({this.phase = UpdatePhase.idle, this.manualCheck = 0});

  AppUpdateState copyWith({UpdatePhase? phase, int? manualCheck}) =>
      AppUpdateState(
        phase: phase ?? this.phase,
        manualCheck: manualCheck ?? this.manualCheck,
      );
}

final updateClientProvider = Provider<UpdateClient>((ref) {
  return const PlayUpdateClient();
});

/// Whether this build can update in place (Google Play on Android).
final inAppUpdateSupportedProvider = Provider<bool>((ref) {
  return !kIsWeb && Platform.isAndroid;
});

/// Google Play in-app updates: checked once when the main screens open, and
/// on demand from Settings.
class AppUpdateController extends Notifier<AppUpdateState> {
  static const _declinedKey = 'app_update_last_declined';

  late UpdateClient _client;
  late SharedPreferences _prefs;
  StreamSubscription<InstallStatus>? _installSub;
  bool _checkedThisSession = false;

  @override
  AppUpdateState build() {
    _client = ref.watch(updateClientProvider);
    _prefs = ref.watch(sharedPreferencesProvider);
    ref.onDispose(() => _installSub?.cancel());
    return const AppUpdateState();
  }

  bool get _supported => ref.read(inAppUpdateSupportedProvider);

  /// Once per session, quietly. Safe to call on every resume: it also picks
  /// up a background download that finished while the app was away.
  Future<void> checkOnLaunch() async {
    if (!_supported) return;
    if (_checkedThisSession && state.phase != UpdatePhase.downloading) {
      return;
    }
    _checkedThisSession = true;
    await _check(userAsked: false);
  }

  /// From "Check for updates" in Settings. Always offers what is available.
  Future<void> checkNow() async {
    if (!_supported) {
      state = state.copyWith(
        phase: UpdatePhase.unavailable,
        manualCheck: state.manualCheck + 1,
      );
      return;
    }
    await _check(userAsked: true);
    state = state.copyWith(manualCheck: state.manualCheck + 1);
  }

  /// Restarts into the downloaded update.
  Future<void> install() async {
    try {
      await _client.completeFlexibleUpdate();
    } catch (e) {
      debugPrint('Installing the update failed: $e');
    }
  }

  Future<void> _check({required bool userAsked}) async {
    state = state.copyWith(phase: UpdatePhase.checking);
    final AppUpdateInfo info;
    try {
      info = await _client.checkForUpdate();
    } catch (e) {
      // Not installed from Google Play, or no Play Store on the device.
      debugPrint('Update check unavailable: $e');
      state = state.copyWith(phase: UpdatePhase.unavailable);
      return;
    }

    final declinedMs = _prefs.getInt(_declinedKey);
    final decision = UpdatePolicy.decide(
      info,
      lastDeclined: declinedMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(declinedMs),
      now: DateTime.now(),
      userAsked: userAsked,
    );

    switch (decision) {
      case UpdateDecision.none:
        state = state.copyWith(
          phase: info.updateAvailability == UpdateAvailability.updateAvailable
              ? UpdatePhase.idle
              : UpdatePhase.upToDate,
        );
      case UpdateDecision.readyToInstall:
        state = state.copyWith(phase: UpdatePhase.readyToInstall);
      case UpdateDecision.immediate:
      case UpdateDecision.resumeImmediate:
        final result = await _guard(_client.performImmediateUpdate);
        // Play restarts the app when it succeeds, so returning means the
        // user backed out or it failed.
        if (result == AppUpdateResult.userDeniedUpdate) await _declined();
        state = state.copyWith(phase: UpdatePhase.idle);
      case UpdateDecision.flexible:
        await _startFlexible();
    }
  }

  Future<void> _startFlexible() async {
    _installSub ??= _client.installStatus.listen((status) {
      if (status == InstallStatus.downloaded) {
        state = state.copyWith(phase: UpdatePhase.readyToInstall);
      } else if (status == InstallStatus.failed ||
          status == InstallStatus.canceled) {
        state = state.copyWith(phase: UpdatePhase.idle);
      }
    });
    state = state.copyWith(phase: UpdatePhase.downloading);
    final result = await _guard(_client.startFlexibleUpdate);
    if (result == AppUpdateResult.userDeniedUpdate) {
      await _declined();
      state = state.copyWith(phase: UpdatePhase.idle);
    } else if (result == AppUpdateResult.inAppUpdateFailed) {
      state = state.copyWith(phase: UpdatePhase.idle);
    }
    // On success the download carries on; the listener reports the end.
  }

  Future<AppUpdateResult> _guard(Future<AppUpdateResult> Function() run) async {
    try {
      return await run();
    } catch (e) {
      debugPrint('Update failed: $e');
      return AppUpdateResult.inAppUpdateFailed;
    }
  }

  Future<void> _declined() =>
      _prefs.setInt(_declinedKey, DateTime.now().millisecondsSinceEpoch);
}

final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateState>(
      AppUpdateController.new,
    );
