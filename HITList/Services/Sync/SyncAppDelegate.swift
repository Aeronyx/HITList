import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The push path (brief 25, item 2): the app delegate HITListApp installs with
/// `UIApplicationDelegateAdaptor` / `NSApplicationDelegateAdaptor`. It logs remote-notification
/// registration and every push to the sync log, through `CloudSyncMonitor`. SwiftUI keeps its own
/// delegate and forwards these calls; nothing else lives here.
enum SyncAppDelegateSupport {
    /// Hosted unit tests launch the app too; they must not register or log.
    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    /// How long an iOS background push may keep the app awake waiting for its import (the system
    /// allows about 30 s).
    static let backgroundImportWait: Duration = .seconds(25)
}

#if os(iOS)
final class SyncAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        guard !SyncAppDelegateSupport.isTesting else { return true }
        let monitor = CloudSyncMonitor.shared
        monitor.pushLaunchState(registered: application.isRegisteredForRemoteNotifications,
                                launchedByPush: launchOptions?[.remoteNotification] != nil)
        // On the Mac the container registers for pushes by itself once its setup succeeds (seen in the
        // sync log). On the iPhone that couldn't be checked (the simulator has no iCloud account), so the
        // app asks too: registering is idempotent, shows no prompt (silent pushes need no permission), and
        // the token can change between launches, which is why Apple asks apps to register at every launch.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard !SyncAppDelegateSupport.isTesting else { return }
        CloudSyncMonitor.shared.pushRegistered(tokenBytes: deviceToken.count)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        guard !SyncAppDelegateSupport.isTesting else { return }
        CloudSyncMonitor.shared.pushRegistrationFailed(error)
    }

    /// A silent CloudKit push wakes the app; it stays awake until the import it triggers finishes (or
    /// 25 s pass), so the import completes in the background instead of on the next launch.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard !SyncAppDelegateSupport.isTesting else { completionHandler(.noData); return }
        let monitor = CloudSyncMonitor.shared
        let state = application.applicationState == .active ? "active" : application.applicationState == .background ? "background" : "inactive"
        monitor.pushReceived(userInfo, appState: state)
        Task { @MainActor in
            let outcome = await monitor.nextImport(within: SyncAppDelegateSupport.backgroundImportWait)
            monitor.pushHandled(stillInBackground: application.applicationState == .background)
            switch outcome {
            case .succeeded: completionHandler(.newData)
            case .failed: completionHandler(.failed)
            case .timedOut: completionHandler(.noData)
            }
        }
    }
}
#else
final class SyncAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !SyncAppDelegateSupport.isTesting else { return }
        CloudSyncMonitor.shared.pushLaunchState(registered: NSApplication.shared.isRegisteredForRemoteNotifications,
                                                launchedByPush: false)
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard !SyncAppDelegateSupport.isTesting else { return }
        CloudSyncMonitor.shared.pushRegistered(tokenBytes: deviceToken.count)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        guard !SyncAppDelegateSupport.isTesting else { return }
        CloudSyncMonitor.shared.pushRegistrationFailed(error)
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        guard !SyncAppDelegateSupport.isTesting else { return }
        CloudSyncMonitor.shared.pushReceived(userInfo, appState: application.isActive ? "active" : "inactive")
    }
}
#endif
