import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/settings_provider.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import 'core/router/app_router.dart';
import 'core/sync/background_sync.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

void _configEasyLoading() {
  // Overlay colours are fixed at startup, before a theme exists, so the
  // loader uses a dark scrim that reads correctly in light and dark mode.
  EasyLoading.instance
    ..displayDuration = const Duration(milliseconds: 2000)
    ..loadingStyle = EasyLoadingStyle.custom
    ..backgroundColor = AppColors.ink
    ..indicatorColor = AppColors.brand
    ..textColor = Colors.white
    ..maskColor = AppColors.ink.withValues(alpha: 0.35)
    ..maskType = EasyLoadingMaskType.custom
    ..indicatorSize = 40.0
    ..radius = AppRadii.card
    ..contentPadding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: AppSpacing.xl,
    )
    ..boxShadow = [
      BoxShadow(
        color: AppColors.ink.withValues(alpha: 0.2),
        blurRadius: 32,
        spreadRadius: 4,
        offset: const Offset(0, 16),
      )
    ]
    ..userInteractions = false
    ..dismissOnTap = false
    ..indicatorWidget = const SpinKitWave(
      color: AppColors.brand,
      size: 30.0,
    );
}

Future<void> main() async {
  _configEasyLoading();
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Local database first: the UI is served from Hive, so it must be ready
    // before the first frame. This is a local disk open — no network.
    await Hive.initFlutter();

    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Firestore offline persistence: reads/writes work with no network and
    // sync automatically once connectivity returns. Unlimited cache keeps
    // the full transaction history available offline.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    if (!kDebugMode) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } else {
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('Flutter Error: ${details.exception}\n${details.stack}');
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Platform Error: $error\n$stack');
        return true;
      };
    }

    // Registers the background isolate entry point. Cheap, and must happen
    // before any task is scheduled.
    await BackgroundSync.initialize();

    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!kDebugMode);
    final prefs = await SharedPreferences.getInstance();

    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const IncomeExpenseTrackerApp(),
      ),
    );
  }, (error, stack) {
    if (!kDebugMode) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } else {
      debugPrint('Uncaught error: $error\n$stack');
    }
  });
}

class IncomeExpenseTrackerApp extends ConsumerWidget {
  const IncomeExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);

    return MaterialApp.router(
      title: 'Accounts Note',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: EasyLoading.init(),
    );
  }
}
