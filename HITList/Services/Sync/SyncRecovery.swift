import Foundation
import OSLog
#if os(macOS)
import AppKit
#endif

/// A stretch of sync trouble: when it began and the words of its first trouble.
struct SyncTroubleSpan: Codable, Equatable {
    var since: Date
    /// "Sync paused: iCloud needs you to sign in again".
    var cause: String
    /// Kept from an earlier launch of this store: the app quit (or was relaunched) in between.
    var relaunched = false
}

/// Watches the raw sync state for stretches of trouble (offline, an error, signed out or restricted, stuck) and, when
/// one ends, gives the line the sync log ends it with: "Sync recovered after 21 s" (brief 78: George's blip of
/// 2026-11-10 ended without a word in the log). A stretch survives a relaunch, kept in the app group's defaults for
/// the store, and then ends only with a sync newer than its start ("…, after a relaunch"). Pure but for those defaults.
struct SyncTroubleTracker {
    /// A stretch shorter than this ends without a line (a Wi-Fi hand-over), unless a relaunch came in between.
    static let minimum: TimeInterval = 5
    static let key = "sync.troubleSpan"

    private let defaults: UserDefaults?
    private let storeName: String
    private(set) var span: SyncTroubleSpan?

    /// `defaults` nil: nothing is kept across launches (tests).
    init(defaults: UserDefaults? = nil, storeName: String = ModelContainerFactory.storeName) {
        self.defaults = defaults
        self.storeName = storeName
        if let data = defaults?.data(forKey: keyName), var saved = try? JSONDecoder().decode(SyncTroubleSpan.self, from: data) {
            saved.relaunched = true
            span = saved
        }
    }

    private var keyName: String { CloudSyncMonitor.syncTimeKey(Self.key, storeName: storeName) }

    /// A raw state at `now`. Returns the recovery line when a stretch worth a line just ended.
    mutating func observe(_ state: SyncState, at now: Date) -> (message: String, fields: [String: String])? {
        if state.showsTrouble {
            if span == nil {
                span = SyncTroubleSpan(since: now, cause: state.summary(now: now))
                save()
            }
            return nil
        }
        guard case .synced(let syncedAt) = state, let ended = span else { return nil }
        // After a relaunch the remembered "Synced 3 min ago" proves nothing: wait for a sync of this launch.
        if ended.relaunched, syncedAt <= ended.since { return nil }
        span = nil
        save()
        let lasted = now.timeIntervalSince(ended.since)
        guard lasted >= Self.minimum || ended.relaunched else { return nil }
        let message = "Sync recovered after \(SyncLogFormat.duration(lasted))" + (ended.relaunched ? ", after a relaunch" : "")
        return (message, ["cause": ended.cause, "since": ended.since.formatted(date: .omitted, time: .standard)])
    }

    private func save() {
        guard let defaults else { return }
        if let span, let data = try? JSONEncoder().encode(span) {
            defaults.set(data, forKey: keyName)
        } else {
            defaults.removeObject(forKey: keyName)
        }
    }
}

/// Getting a stuck sync going again (brief 25, item 6).
///
/// CloudKit's mirroring runs one request at a time. On Nov 1 an import started at 18:51:54 in the
/// TestFlight Mac app and never ended; every later export was refused ("a request is already pending",
/// NSCocoaErrorDomain 134417) until George quit at 18:59:31, and the task made at 18:56 reached iCloud
/// only at the next launch, 16 hours later. Nothing in SwiftData can cancel or restart that request; a
/// new process sets the mirroring up afresh and exported everything within a second every time. So when
/// `SyncWatchdog` says an event has stalled, Settings → iCloud offers to relaunch (Mac) or explains how
/// to reopen the app (iPhone).
enum SyncRecovery {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    /// The relaunching instance's pid and when it asked, in the app group's defaults: the App Sandbox
    /// drops the arguments and environment of an app opened through NSWorkspace, so the handoff goes
    /// through the shared defaults instead.
    static let pidKey = "sync.relaunchFromPid"
    static let atKey = "sync.relaunchAt"
    /// A handoff older than this is stale (the relaunch failed, or another build launched instead).
    static let handoffLifetime: TimeInterval = 30

    #if os(macOS)
    /// Opens a new instance of this app and quits this one once it is running. The new instance waits
    /// for this one to exit before it opens the store (`waitForPreviousInstance`), so the store is
    /// never open in two processes. Calls `failed` when no new instance appeared within 10 s.
    @MainActor
    static func relaunch(defaults: UserDefaults = AppGroup.defaults, failed: @escaping @MainActor () -> Void) {
        let me = ProcessInfo.processInfo.processIdentifier
        CloudSyncMonitor.shared.write(.note, "Relaunching to restart a stuck sync", level: .notice)
        defaults.set(Int(me), forKey: pidKey)
        defaults.set(Date(), forKey: atKey)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error { log.error("Relaunch failed: \(error.localizedDescription, privacy: .public)") }
        }
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        Task { @MainActor in
            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(100))
                let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                if others.contains(where: { $0.processIdentifier != me && !$0.isTerminated }) {
                    NSApplication.shared.terminate(nil)
                    return
                }
            }
            defaults.removeObject(forKey: pidKey)
            defaults.removeObject(forKey: atKey)
            CloudSyncMonitor.shared.write(.note, "Relaunch: no new instance appeared", level: .error)
            failed()
        }
    }
    #endif

    /// The pid of the instance that asked for this launch, if it asked within `handoffLifetime`. The
    /// handoff is consumed by whichever instance reads it first.
    static func previousInstance(defaults: UserDefaults, now: Date = Date(),
                                 me: Int32 = ProcessInfo.processInfo.processIdentifier) -> Int32? {
        guard let pid = defaults.object(forKey: pidKey) as? Int else { return nil }
        let at = defaults.object(forKey: atKey) as? Date
        defaults.removeObject(forKey: pidKey)
        defaults.removeObject(forKey: atKey)
        guard let at, abs(now.timeIntervalSince(at)) < handoffLifetime, Int32(pid) != me else { return nil }
        return Int32(pid)
    }

    /// Called first thing in `HITListApp.init`: an instance relaunched by `relaunch` waits (up to 10 s)
    /// for the one that launched it to exit. Returns how long it waited, or nil when it wasn't relaunched.
    @discardableResult
    static func waitForPreviousInstance(defaults: UserDefaults = AppGroup.defaults) -> TimeInterval? {
        #if os(macOS)
        guard let pid = previousInstance(defaults: defaults) else { return nil }
        let start = Date()
        while let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, Date().timeIntervalSince(start) < 10 {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return Date().timeIntervalSince(start)
        #else
        return nil
        #endif
    }
}
