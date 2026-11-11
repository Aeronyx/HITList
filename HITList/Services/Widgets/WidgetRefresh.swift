import Foundation
import OSLog
#if os(iOS)
import BackgroundTasks
import UIKit
#endif

/// Widgets that stay true without being asked (brief 81, rule 6): the moments the app gets to run in the background end
/// in a fresh snapshot, the outbox drained, and a reload.
///
/// - **A silent push** (another device's change): the push handler waits for the import it triggers (`ImportWaiter`),
///   then calls `settle()` before telling the system it is done. Before 0.9.2 the snapshot followed the import only
///   through the writer's debounce, which ran after the handler had returned and the app had been suspended again, so
///   the widgets heard of the change only at the next launch.
/// - **The background refresh**: iPhone and iPad, a `BGAppRefreshTask` (`identifier`, Info.plist's
///   `BGTaskSchedulerPermittedIdentifiers`, SwiftUI's `.backgroundTask(.appRefresh)` in `HITListApp`), asked for an hour
///   ahead each time the app goes to the background and after each run; the system decides when, and whether, it runs.
///   It waits a little for CloudKit to import (an app launched for it imports as at any launch), then settles. The Mac
///   app keeps running with its window closed and gets pushes; `NSBackgroundActivityScheduler` adds an hourly settle,
///   timed by the system around sleep and power.
@MainActor
enum WidgetRefresh {
    static let identifier = "com.trammells.hitlist.widget-refresh"
    /// How soon after one run the next is asked for.
    static let interval: TimeInterval = 3600
    /// How long a refresh waits for CloudKit's import (the system allows about 30 s).
    static let importWait: Duration = .seconds(15)

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "widgets")
    private static var observers: [NSObjectProtocol] = []
    #if os(macOS)
    private static var activity: NSBackgroundActivityScheduler?
    #endif

    /// From `HITListApp.init`, after the snapshot writer and the completion center.
    static func start() {
        #if os(iOS)
        schedule()
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                                object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { schedule() }
        })
        #else
        let scheduler = NSBackgroundActivityScheduler(identifier: identifier)
        scheduler.repeats = true
        scheduler.interval = interval
        scheduler.tolerance = interval / 4
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            Task { @MainActor in
                await settle(waitForMerge: false)
                log.notice("widget refresh (Mac activity) settled")
                completion(.finished)
            }
        }
        activity = scheduler
        #endif
    }

    /// After an import, a push or a refresh: the import's changes merged into the store's context (a moment after the
    /// event ends), the outbox drained (a tap completed elsewhere resolves; an export may have finished), the snapshot
    /// written now and the widgets reloaded.
    static func settle(waitForMerge: Bool = true) async {
        if waitForMerge { try? await Task.sleep(for: .seconds(1)) }
        WidgetCompletionCenter.shared?.drain()
        WidgetSnapshotWriter.shared.writeNow()
    }

    #if os(iOS)
    /// Asks the system for a refresh an `interval` from now (one request stands at a time; a new one replaces it).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The simulator has no background refresh, and Settings → General → Background App Refresh can be off.
            log.info("widget refresh not scheduled: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The refresh itself (`HITListApp`'s `.backgroundTask`).
    static func run() async {
        let started = Date()
        let monitor = CloudSyncMonitor.shared
        var heard = "sync off"
        if ModelContainerFactory.isCloudKitEnabled {
            heard = "import \(await monitor.nextImport(after: started, within: importWait))"
        }
        await settle()
        schedule()
        monitor.write(.note, "Background refresh for the widgets after \(SyncLogFormat.duration(Date().timeIntervalSince(started))): \(heard)")
    }
    #endif
}
