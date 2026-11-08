import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Notes something worth knowing that the app recovered from: a sync that
/// will retry, a reminder that could not be scheduled, and so on.
///
/// Printed to the console while developing. In installed (release) builds
/// nothing is printed: the note goes to Crashlytics as a breadcrumb, so it
/// shows up alongside any later crash report without filling the device log.
/// Never pass personal data such as email addresses.
void appLog(String message) {
  if (!kReleaseMode) {
    debugPrint(message);
    return;
  }
  try {
    FirebaseCrashlytics.instance.log(message);
  } catch (_) {
    // Crashlytics not set up (tests, a failed start): drop the note.
  }
}

/// Notes an unexpected error the app recovered from (it showed the user a
/// message instead of crashing).
///
/// Printed with its type and stack while developing. In release builds it is
/// sent to Crashlytics as a non-fatal error, so real users' failures show up
/// in the Firebase console without anything printed on their phones.
void appError(Object error, [StackTrace? stack, String? context]) {
  final where = context == null ? '' : '$context: ';
  if (!kReleaseMode) {
    debugPrint('⚠️ $where${error.runtimeType}: $error');
    if (stack != null) debugPrint(stack.toString());
    return;
  }
  try {
    FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: context,
      fatal: false,
    );
  } catch (_) {
    // Crashlytics not set up: drop it.
  }
}
