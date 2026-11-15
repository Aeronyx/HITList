import Foundation
import Observation
import HITListCore

/// Where the two halves of the engine's place in the app meet (round 28, wave 2): the side that runs the engine
/// (`SyncEngine`, brief 143) writes here, and the side that shows sync (the bolt, Settings → iCloud, the sync log:
/// brief 144) reads here. Neither knows the other. While a launch runs on SwiftData's mirror, as every released
/// build does, `engine` is `.mirror`, `status` is nil and nothing here changes.
@MainActor
@Observable
final class SyncEngineBoard {
    static let shared = SyncEngineBoard()

    /// Which engine syncs this launch's store.
    enum Engine: String, Sendable {
        /// SwiftData's CloudKit mirror: every released build so far.
        case mirror
        /// HITList's own engine (`dev/SYNC-ENGINE.md`).
        case own
    }

    /// What a person can ask of the engine, wired by the side that runs it; nil on the mirror.
    struct Actions {
        /// Fetch, then send, now ("Sync now").
        var syncNow: @MainActor () async throws -> Void
        /// Try again after `failed`, `storageFull`, `duplicates` (`SyncCore.resume`).
        var resume: @MainActor () async -> Void
        /// The answer to a purge in iCloud's settings (`SyncCore.answer`).
        var answerPurge: @MainActor (PurgeAnswer) async throws -> Void
        /// "I deleted them" (`SyncCore.confirmDeletions`).
        var confirmDeletions: @MainActor () async throws -> Void
        /// Move this device's store to the other engine (a backup first, then a relaunch); the words of what
        /// went wrong when it throws.
        var move: @MainActor (Engine) async throws -> Void
    }

    private(set) var engine: Engine = .mirror
    /// The engine's own status, exact; nil on the mirror and until the engine has started.
    private(set) var status: SyncStatus?
    private(set) var actions: Actions?
    /// One plain line per thing the engine did, for the sync log; set by whoever shows the log.
    @ObservationIgnored var onLog: (@MainActor (String) -> Void)?

    /// Posted on the main actor after `status` changed, for listeners that are not views.
    static let statusChanged = Notification.Name("HITList.syncEngineStatusChanged")

    /// The side that runs the engine says which engine this launch uses, once, at launch.
    func launched(_ engine: Engine, actions: Actions?) {
        self.engine = engine
        self.actions = actions
        if engine == .mirror { status = nil }
    }

    func publish(_ status: SyncStatus) {
        guard self.status != status else { return }
        self.status = status
        NotificationCenter.default.post(name: Self.statusChanged, object: self)
    }

    func log(_ line: String) { onLog?(line) }

    /// For tests and the Debug demo of the bolt's states: as if the engine ran and said `status`.
    func show(_ status: SyncStatus?, engine: Engine = .own, actions: Actions? = nil) {
        self.engine = engine
        self.actions = actions
        if let status { publish(status) } else { self.status = nil }
    }
}
