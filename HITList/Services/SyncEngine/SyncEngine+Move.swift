import Foundation
import OSLog
import SwiftData
import HITListCore
#if os(macOS)
import AppKit
#endif

/// Moving a device's store from one engine to the other (`dev/SYNC-ENGINE.md` section 11; `SyncEngineBoard.Actions.move`).
///
/// The store file itself never changes hands: the next launch opens the same file with the mirror or without it. In
/// order: a backup (none, nothing moves: the move throws), the rows that share an `id` merged (moving to the engine: its
/// records are keyed by `id`; the merge runs again before the engine starts, with the mirror off, so this one is only
/// the first), the preference (`SyncEngineSwitch`), then the relaunch. A crash between any two leaves either the old
/// engine with a backup written (and perhaps rows merged, which any launch would merge too) or the new preference,
/// which the next launch reads. The engine's ledger needs nothing: a store that comes back to the engine after time on
/// the mirror keeps its file, so its ledger is still bound to it, and the brain's compare finds whatever the mirror
/// brought or changed meanwhile as changed here, as it finds any write.
extension SyncEngine {
    enum MoveError: Error, LocalizedError, Equatable {
        /// The store could not be opened and the app runs on an empty one: nothing to move.
        case inMemory
        /// The move is made; the app must be opened again to run on the other engine (iPhone, iPad, and a side store on
        /// the Mac, which a relaunch through the system would not reopen: the sandbox drops its environment).
        case reopenToFinish(SyncEngineBoard.Engine)

        var errorDescription: String? {
            switch self {
            case .inMemory: return "This device's data couldn't be opened, so there is nothing to move."
            case .reopenToFinish(let engine):
                let name = engine == .own ? "HITList's own sync engine" : "iCloud's mirror"
                return "Ready: quit HITList and open it again to sync on \(name)."
            }
        }
    }

    private static let moveLog = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    /// Moves this store to `engine` and relaunches (the Mac's real store) or asks to be reopened (`reopenToFinish`).
    /// Nothing happens when the store is already on `engine`.
    static func move(to engine: SyncEngineBoard.Engine, container: ModelContainer,
                     storeName: String = ModelContainerFactory.storeName, defaults: UserDefaults = AppGroup.defaults,
                     backUp: @MainActor (ModelContext) throws -> URL? = { try SyncRepair.backUp(context: $0) },
                     relaunch: Bool = true) async throws {
        guard engine != SyncEngineSwitch.current else { return }
        guard !ModelContainerFactory.isRunningInMemory else { throw MoveError.inMemory }
        let context = container.mainContext
        // 1. The backup. Nothing of the person's is at risk in a move (the file stays), but it is the moment a person
        //    would want one, and a failed backup is a reason to stop.
        let backup = try backUp(context)
        moveLog.notice("move to \(engine.rawValue, privacy: .public): backup \(backup?.lastPathComponent ?? "not needed (empty store)", privacy: .public)")
        // 2. Rows that share an id, merged.
        if engine == .own {
            let merged = try Deduplicator.mergeSharedIDs(in: context)
            moveLog.notice("move to the engine: \(merged.description, privacy: .public)")
        }
        // 3. The preference: from here on the next launch opens the store on `engine`.
        SyncEngineSwitch.setPreference(engine, storeName: storeName, defaults: defaults)
        // 4. The running engine stops before the process goes, so the transport's state is written.
        if let running = shared { await running.stop() }
        guard relaunch else { return }
        #if os(macOS)
        if storeName == ModelContainerFactory.mainStoreName {
            relaunchMac(defaults: defaults)
            return
        }
        #endif
        throw MoveError.reopenToFinish(engine)
    }

    #if os(macOS)
    /// As Reset local cache relaunches: a new instance, which waits for this one to exit before it opens the store
    /// (`SyncRecovery.waitForPreviousInstance`, through the App Group's defaults), then this one quits.
    private static func relaunchMac(defaults: UserDefaults) {
        let me = ProcessInfo.processInfo.processIdentifier
        defaults.set(Int(me), forKey: SyncRecovery.pidKey)
        defaults.set(Date(), forKey: SyncRecovery.atKey)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error { moveLog.error("move: relaunch failed: \(error.localizedDescription, privacy: .public)") }
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
            defaults.removeObject(forKey: SyncRecovery.pidKey)
            defaults.removeObject(forKey: SyncRecovery.atKey)
            moveLog.error("move: no new instance appeared; the move finishes at the next launch")
        }
    }
    #endif
}
