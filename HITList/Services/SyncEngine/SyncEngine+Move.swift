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
///
/// **The way back** (rehearsed in round 32 on CloudKit Development, two stores): the first device to go back keeps
/// its file, and the mirror, reopened, sends everything that changed while it was off (SwiftData records history on
/// a store open without the mirror; the mirror's own audit agreed on the second launch). **Every other device must
/// come back with a fresh copy** (`freshCopy`): an item made on the engine has no record of the mirror's on any
/// device, so each device that came back with its own file would send it as a record of its own, and every device
/// would then hold it twice (seen: 21 tasks where 19 were right). A fresh copy downloads what the first device sent.
/// What a device changed on the engine and had not yet synced when it takes a fresh copy is in its backup only.
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
                let name = engine == .own ? "the new sync" : "the earlier sync"
                #if os(macOS)
                return "Ready: quit HITList and open it again to finish moving to \(name)."
                #else
                return "Ready: swipe HITList away in the app switcher and open it again to finish moving to \(name)."
                #endif
            }
        }
    }

    private static let moveLog = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    /// Moves this store to `engine` and relaunches (the Mac's real store) or asks to be reopened (`reopenToFinish`).
    /// Nothing happens when the store is already on `engine` and no move is waiting. A move that was asked for and
    /// is still waiting for the app to be reopened (the iPhone) is taken back by moving to the engine this launch
    /// runs on: the preference is put back and nothing else is needed, because nothing else had changed.
    static func move(to engine: SyncEngineBoard.Engine, container: ModelContainer,
                     storeName: String = ModelContainerFactory.storeName, defaults: UserDefaults = AppGroup.defaults,
                     current: SyncEngineBoard.Engine = SyncEngineSwitch.current,
                     freshCopy: Bool = false,
                     backUp: @MainActor (ModelContext) throws -> URL? = { try SyncRepair.backUp(context: $0) },
                     relaunch: Bool = true) async throws {
        guard engine != current else {
            if SyncEngineSwitch.nextEngine(storeName: storeName, defaults: defaults) != engine {
                SyncEngineSwitch.setPreference(engine, storeName: storeName, defaults: defaults)
                // A waiting move that asked for a fresh copy is taken back whole: without this the store was still set
                // aside at the next launch, on the engine it never left (brief 167's finding).
                if ModelContainerFactory.requestedReset(in: defaults) == storeName {
                    defaults.removeObject(forKey: ModelContainerFactory.resetLocalStoreKey)
                }
                moveLog.notice("move to \(engine.rawValue, privacy: .public): a waiting move was taken back")
            }
            return
        }
        guard !ModelContainerFactory.isRunningInMemory else { throw MoveError.inMemory }
        let context = container.mainContext
        // 1. The backup. Nothing of the person's is at risk in a move (the file stays), but it is the moment a person
        //    would want one, and a failed backup is a reason to stop.
        let backup = try backUp(context)
        moveLog.notice("move to \(engine.rawValue, privacy: .public): backup \(backup?.lastPathComponent ?? "not needed (empty store)", privacy: .public)")
        // 1b. Moving to the engine, that backup is also kept under a name the daily rotation never removes: the
        //     person's tasks as they were on this device before the new sync touched anything.
        if engine == .own, let backup { LocalBackup.keepBeforeTheNewSync(backup) }
        // 2. Rows that share an id, merged.
        if engine == .own {
            let merged = try Deduplicator.mergeSharedIDs(in: context)
            moveLog.notice("move to the engine: \(merged.description, privacy: .public)")
        }
        // 3. The preference: from here on the next launch opens the store on `engine`. A move back is the person's
        //    word that this store stays on the mirror: the move made by the app itself never moves it again.
        SyncEngineSwitch.setPreference(engine, storeName: storeName, defaults: defaults)
        if engine == .mirror { defaults.set(true, forKey: SyncEngineAutoMove.stayKey(storeName)) }
        // 3b. A move that takes a fresh copy (the hand move back, for every device but the first): the store is set
        //     aside at that launch (as Reset local cache does, never deleted), and the mirror downloads its zone into
        //     a new one. The move the app makes by itself never takes one: it always merges (round 34).
        if freshCopy {
            LocalCacheReset.request(storeName: storeName, defaults: defaults)
            moveLog.notice("move to \(engine.rawValue, privacy: .public): with a fresh copy; the store is set aside at the next launch")
        }
        guard relaunch else { return }
        #if os(macOS)
        if storeName == ModelContainerFactory.mainStoreName {
            // 4. The running engine stops before the process goes, so the transport's state is written.
            if let running = shared { await running.stop() }
            relaunchMac(defaults: defaults)
            return
        }
        #endif
        // On the iPhone and iPad (and a side store on the Mac) the person reopens the app, perhaps much later: until
        // then this process goes on syncing on the engine it runs, and taking its deletions down. Stopping it here
        // left an app that looked synced and sent nothing for as long as it stayed in the background (147's F5).
        throw MoveError.reopenToFinish(engine)
    }

    #if os(macOS)
    /// As Reset local cache relaunches: a new instance, which waits for this one to exit before it opens the store
    /// (`SyncRecovery.waitForPreviousInstance`, through the App Group's defaults), then this one quits.
    /// `activates: false` (the move the app finishes by itself, `SyncEngineMoveFinish`): the new instance opens behind
    /// whatever the person is working in.
    static func relaunchMac(defaults: UserDefaults, activates: Bool = true) {
        let me = ProcessInfo.processInfo.processIdentifier
        defaults.set(Int(me), forKey: SyncRecovery.pidKey)
        defaults.set(Date(), forKey: SyncRecovery.atKey)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = activates
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
