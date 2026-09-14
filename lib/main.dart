import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/settings_provider.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

void _configEasyLoading() {
  EasyLoading.instance
    ..displayDuration = const Duration(milliseconds: 2000)
    ..loadingStyle = EasyLoadingStyle.custom
    ..backgroundColor = Colors.white
    ..indicatorColor = AppColors.brand
    ..textColor = AppColors.ink
    ..maskColor = AppColors.brandDeep.withValues(alpha: 0.2)
    ..maskType = EasyLoadingMaskType.custom
    ..indicatorSize = 40.0
    ..radius = 20.0
    ..boxShadow = [
      BoxShadow(
        color: AppColors.brandDeep.withValues(alpha: 0.15),
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
