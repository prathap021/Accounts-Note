import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background sync task identifiers. These must match
    // BGTaskSchedulerPermittedIdentifiers in Info.plist and the constants in
    // lib/core/sync/background_sync.dart. Registration has to happen before
    // the app finishes launching or iOS will never run the tasks.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.accountsnote.sync.refresh"
    )
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "com.accountsnote.sync.processing"
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
