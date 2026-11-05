import Foundation
import CloudKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The push path (brief 25, item 2): the app delegate HITListApp installs with
/// `UIApplicationDelegateAdaptor` / `NSApplicationDelegateAdaptor`. It logs remote-notification
/// registration and every push to the sync log, through `CloudSyncMonitor`. SwiftUI keeps its own
/// delegate and forwards these calls. Shared Tasks (brief 51) adds two things: pushes for its own container go to
/// `SharedTasksCenter`, never to the task store's monitor and watchdog, and CloudKit share acceptance (the iOS
/// scene delegate class, `SharingSceneDelegate`; the Mac callback here).
enum SyncAppDelegateSupport {
    /// Hosted unit tests launch the app too; they must not register or log.
    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    /// How long an iOS background push may keep the app awake waiting for its import (the system
    /// allows about 30 s).
    static let backgroundImportWait: Duration = .seconds(25)
}

/// The wait behind the iOS push handler (George, 2026-11-02: it finishes as soon as the import it
/// waited for has finished). `CloudSyncMonitor` reports every import's end; `next(after:within:)`
/// answers with the first import that covers a push received at a given moment, at once if one already
/// has, or `.timedOut`. It used to wait only for an import ending after the handler's own task started,
/// so an import that finished first (CloudKit takes the push itself and can be done before the delegate
/// runs, or between the delegate and its task) kept the app awake the full 25 s.
///
/// An import covers a push when it finished after the push arrived, or started at most `slack` before
/// it (the watchdog's `importSlack`: the import a push triggers can start before the push is seen).
/// `sleep` is the clock, injectable so tests can time out without waiting.
@MainActor
final class ImportWaiter {
    typealias Outcome = CloudSyncMonitor.ImportOutcome

    /// One finished import.
    struct Ended: Equatable, Sendable {
        let startedAt: Date
        let endedAt: Date
        let outcome: Outcome
    }

    static let slack: TimeInterval = SyncWatchdog.Rules().importSlack

    private struct Waiter {
        let pushAt: Date
        let resume: (Outcome) -> Void
        var timeout: Task<Void, Never>?
    }

    private let sleep: @MainActor (Duration) async -> Void
    private var waiters: [UUID: Waiter] = [:]
    /// The latest import to finish, for a push whose handler starts waiting after it ended.
    private(set) var lastEnded: Ended?

    init(sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Pushes still waiting.
    var waitingCount: Int { waiters.count }

    nonisolated static func covers(_ ended: Ended, pushAt: Date) -> Bool {
        ended.endedAt >= pushAt || ended.startedAt >= pushAt.addingTimeInterval(-slack)
    }

    /// An import ended (`CloudSyncMonitor.record`): every push it covers stops waiting.
    func importEnded(startedAt: Date, at endedAt: Date, outcome: Outcome) {
        let ended = Ended(startedAt: startedAt, endedAt: endedAt, outcome: outcome)
        if lastEnded.map({ endedAt >= $0.endedAt }) ?? true { lastEnded = ended }
        for (id, waiter) in waiters where Self.covers(ended, pushAt: waiter.pushAt) {
            resolve(id, outcome)
        }
    }

    /// Waits for an import covering a push received at `pushAt`, or `timeout`.
    func next(after pushAt: Date, within timeout: Duration) async -> Outcome {
        if let lastEnded, Self.covers(lastEnded, pushAt: pushAt) { return lastEnded.outcome }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = Waiter(pushAt: pushAt, resume: { continuation.resume(returning: $0) })
            waiters[id]?.timeout = Task { [weak self, sleep] in
                await sleep(timeout)
                guard !Task.isCancelled else { return }
                self?.resolve(id, .timedOut)
            }
        }
    }

    private func resolve(_ id: UUID, _ outcome: Outcome) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.timeout?.cancel()
        waiter.resume(outcome)
    }
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

    /// Every window scene gets `SharingSceneDelegate`, only so that a CloudKit invitation link reaches the app
    /// (Shared Tasks, brief 51); SwiftUI still makes and manages the window.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication { configuration.delegateClass = SharingSceneDelegate.self }
        return configuration
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
    /// 25 s pass), so the import completes in the background instead of on the next launch. An import
    /// that finished before the wait began counts (`ImportWaiter`), so the app is not held for nothing.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard !SyncAppDelegateSupport.isTesting else { completionHandler(.noData); return }
        // Shared Tasks' own container (brief 51): its engines fetch; the task store's monitor never sees it.
        if SharedTasksPush.isForSharedTasks(userInfo) {
            Task { @MainActor in completionHandler(await SharedTasksCenter.shared.handlePush() ? .newData : .noData) }
            return
        }
        let receivedAt = Date()
        let monitor = CloudSyncMonitor.shared
        let state = application.applicationState == .active ? "active" : application.applicationState == .background ? "background" : "inactive"
        monitor.pushReceived(userInfo, appState: state)
        Task { @MainActor in
            let outcome = await monitor.nextImport(after: receivedAt, within: SyncAppDelegateSupport.backgroundImportWait)
            let waited = SyncLogFormat.duration(Date().timeIntervalSince(receivedAt))
            monitor.write(.push, "Push handler finished after \(waited): \(outcome)", fields: ["waited": waited, "outcome": "\(outcome)"])
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
        // Shared Tasks' own container (brief 51): its engines fetch; the task store's monitor never sees it.
        if SharedTasksPush.isForSharedTasks(userInfo) {
            Task { @MainActor in _ = await SharedTasksCenter.shared.handlePush() }
            return
        }
        CloudSyncMonitor.shared.pushReceived(userInfo, appState: application.isActive ? "active" : "inactive")
    }

    /// A CloudKit invitation link opened on the Mac (Shared Tasks, brief 51).
    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        guard !SyncAppDelegateSupport.isTesting else { return }
        SharedTasksCenter.shared.userAccepted(metadata)
    }

    /// A Dock click with no window on screen: the window closed earlier comes back as it was
    /// (`MacWindowKeeper`) instead of SwiftUI building a new one.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        flag || !MacWindowKeeper.shared.reopen()
    }

    /// ⌘Tab (or any other way back) with the window put away: show it, as a Dock click would.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard !NSApp.windows.contains(where: { $0.isVisible && $0.styleMask.contains(.titled) }) else { return }
        MacWindowKeeper.shared.reopen()
    }
}
#endif
