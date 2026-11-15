import Foundation
import OSLog
import SwiftData
import HITListCore

/// The app's side of the brain's `SyncHost` (round 28, brief 143): what only the app can do for the engine, and where
/// what the brain says goes.
///
/// The brain calls `didWrite`, `didAccept` and `statusDidChange` on its own executor and they must return at once, so
/// each is put, in the order it came, on one stream (`events`) that the engine reads on the main actor
/// (`SyncEngine.consume`). One stream for all of them keeps their order: a status that follows a write is never shown
/// before the write's consequences have been posted. `willRemoveLocalData` is the one call the brain awaits: it writes
/// a backup on the main actor and throws when it could not, and then nothing is removed.
final class SyncEngineHost: SyncHost, @unchecked Sendable {
    enum Event: Sendable {
        case status(SyncStatus)
        /// Items a fetch, a conflict or a sign-out wrote or removed here.
        case wrote(Set<SyncKey>)
        /// Records iCloud accepted from this device, and when.
        case accepted(Set<SyncKey>, at: Date)
        /// One plain line from the brain, for the board's log.
        case log(String)
    }

    /// Read once, by the engine.
    let events: AsyncStream<Event>
    private let feed: AsyncStream<Event>.Continuation
    private let backUp: @MainActor (SyncRemovalReason) throws -> Void
    private let clock: @Sendable () -> Date

    /// - Parameter backUp: writes the backup before anything of the person's leaves the device (`SyncEngine` passes
    ///   `SyncEngineHost.backUpStore`); throwing stops the removal.
    init(clock: @escaping @Sendable () -> Date = { Date() },
         backUp: @escaping @MainActor (SyncRemovalReason) throws -> Void) {
        var continuation: AsyncStream<Event>.Continuation!
        // Unbounded: nothing the brain says may be dropped (a lost `wrote` would leave a reminder or a widget stale).
        events = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        feed = continuation
        self.backUp = backUp
        self.clock = clock
    }

    /// The brain's log closure (`SyncCore.init(log:)`): onto the same stream, in order with everything else.
    var logLine: @Sendable (String) -> Void { { [feed] line in feed.yield(.log(line)) } }

    func finish() { feed.finish() }

    // MARK: SyncHost

    func willRemoveLocalData(reason: SyncRemovalReason) async throws {
        try await MainActor.run { try backUp(reason) }
    }

    func didWrite(_ keys: Set<SyncKey>) {
        guard !keys.isEmpty else { return }
        feed.yield(.wrote(keys))
    }

    func didAccept(_ keys: Set<SyncKey>) {
        guard !keys.isEmpty else { return }
        feed.yield(.accepted(keys, at: clock()))
    }

    func statusDidChange(_ status: SyncStatus) {
        feed.yield(.status(status))
    }

    // MARK: The backup

    struct BackupFailed: Error, LocalizedError {
        let words: String
        var errorDescription: String? { "No backup could be written, so nothing was removed from this device: \(words)" }
    }

    /// The backup the pre-repair backups write (`SyncRepair.backUp`): today's daily backup for HITList.store, a file of
    /// its own for a side store. An empty store writes nothing and that is no failure: there is nothing to lose.
    @MainActor
    static func backUpStore(_ container: ModelContainer, reason: SyncRemovalReason) throws {
        do {
            let url = try SyncRepair.backUp(context: container.mainContext)
            log.notice("sync engine: backup before removing local data (\(reason.rawValue, privacy: .public)): \(url?.lastPathComponent ?? "nothing to back up", privacy: .public)")
        } catch {
            log.error("sync engine: backup before removing local data failed: \(error.localizedDescription, privacy: .public)")
            throw BackupFailed(words: error.localizedDescription)
        }
    }

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "sync")
}

/// What the widgets' completions need to know (`WidgetSyncFacts`), answered from the engine instead of the mirror's
/// export events: a completion is finished when iCloud accepted that task's record after it was applied, or when the
/// engine has had nothing waiting since (every save before that moment is in iCloud).
@MainActor
final class SyncEngineWidgetFacts: WidgetSyncFacts {
    private(set) var status = SyncStatus()
    /// When iCloud last accepted each record from this device, this launch.
    private var acceptedAt: [SyncKey: Date] = [:]
    /// The last moment the brain had every save of this process in hand and nothing waiting (`quiet(at:)`).
    private(set) var quietAt: Date?

    func update(_ status: SyncStatus) { self.status = status }

    func accepted(_ keys: Set<SyncKey>, at date: Date) {
        for key in keys { acceptedAt[key] = date }
    }

    /// Called by the engine when the brain had nothing waiting after it had seen every save hint posted until then.
    func quiet(at date: Date) { quietAt = date }

    var finishLine: WidgetCompletion.FinishLine {
        // Signed out: nothing will sync, the save is the end (as on the mirror).
        status.hold == .noAccount ? .save : .export
    }

    var lastExportStart: Date? { quietAt }

    var canTellGone: Bool { status.firstFetchDone }

    var widgetSync: WidgetSnapshot.Sync {
        switch status.state {
        case .held(.noAccount): return .localOnly
        case .held: return .waiting
        default: return status.lastError == nil ? .fine : .waiting
        }
    }

    func accepted(_ taskID: UUID, since date: Date) -> Bool {
        guard let at = acceptedAt[SyncSchema.key(SyncSchema.taskItem, id: taskID)] else { return false }
        return at >= date
    }
}
