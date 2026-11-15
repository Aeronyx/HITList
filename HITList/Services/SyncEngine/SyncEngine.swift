import Foundation
import OSLog
import SwiftData
import HITListCore

/// HITList's own sync engine in the app (round 28, brief 143; `dev/SYNC-ENGINE.md`): the parts wave 1 built, put
/// together and run from launch to quit, behind `SyncEngineSwitch`. On the mirror (every released build) nothing here
/// is made: `launchIfSwitchedOn` publishes the mirror to the board, with only the move wired, and returns.
///
/// One per process, on the main actor, a facade: every call into the brain is awaited from a task (the main thread is
/// never blocked on it: the store's `apply` hops to the main actor, and waiting there would deadlock).
///
/// The parts: the ledger beside the store (`SyncLedgerStore`, bound to the store file's identity before anything reads
/// it), the device's side (`SwiftDataSyncStore`, writes through the main context), the road to iCloud
/// (`CloudKitTransport` in the app, `PretendCloudTransport` in a Debug pretend run, a `FakeTransport` in tests), the
/// brain (`SyncCore`) and the host (`SyncEngineHost`).
@MainActor
final class SyncEngine {
    private(set) static var shared: SyncEngine?

    let container: ModelContainer
    let ledger: SyncLedgerStore
    let store: SwiftDataSyncStore
    let transport: any SyncTransport
    let core: SyncCore
    let host: SyncEngineHost
    let board: SyncEngineBoard
    let widgetFacts = SyncEngineWidgetFacts()
    /// The store file this engine's ledger is bound to; nil in tests that bind nothing.
    let storeURL: URL?

    private var hintObserver: SyncSaveHintObserver?
    /// Save hints, in the order the saves posted them, read by one task (`feedHints`): the brain hears them in order.
    private let hints: AsyncStream<Hint>.Continuation
    private let hintStream: AsyncStream<Hint>
    /// Hints posted (counted on the saving thread) and hints the brain has finished with: equal means the brain has
    /// every save of this process in hand.
    private let hintCount = HintCount()
    private var hintsDone = 0
    private var workers: [Task<Void, Never>] = []
    private(set) var isStarted = false
    /// The duplicate keys the app last merged for a `duplicates` hold: a hold that comes back with the same keys after
    /// a merge is left for the person (no loop).
    private var mergedFor: [SyncKey]?
    /// Lines of what the engine did, for tests and the Debug pretend run's stdout; the board's log gets each too.
    var echo: ((String) -> Void)?

    private struct Hint: Sendable {
        var keys: Set<SyncKey>?
        var serial: Int
        /// Not a hint: `settle()`'s marker, run when every hint before it has been through the brain.
        var barrier: (@Sendable () -> Void)? = nil
    }

    private static let osLog = Logger(subsystem: "com.trammells.hitlist", category: "sync")

    /// A counter the saving thread bumps (a save on any thread posts a hint) and the main actor reads.
    private final class HintCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    /// - Parameters:
    ///   - storeURL: the store file, for the ledger's binding (`SyncLedgerStore.bind(toStore:)`); nil binds nothing.
    ///   - makeTransport: the road to iCloud, given the ledger (the transport keeps its state in it).
    init(container: ModelContainer, ledger: SyncLedgerStore, storeURL: URL?, board: SyncEngineBoard = .shared,
         clock: @escaping @Sendable () -> Date = { Date() },
         backUp: (@MainActor (SyncRemovalReason) throws -> Void)? = nil,
         makeTransport: (SyncLedgerStore) -> any SyncTransport) {
        self.container = container
        self.ledger = ledger
        self.storeURL = storeURL
        self.board = board
        store = SwiftDataSyncStore(container: container, writer: .mainContext)
        let transport = makeTransport(ledger)
        self.transport = transport
        host = SyncEngineHost(clock: clock, backUp: backUp ?? { reason in try SyncEngineHost.backUpStore(container, reason: reason) })
        core = SyncCore(store: store, ledger: ledger, transport: transport, host: host, clock: clock, log: host.logLine)
        var continuation: AsyncStream<Hint>.Continuation!
        hintStream = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        hints = continuation
    }

    // MARK: - Launch (the app)

    /// From `HITListApp.init`, after the container opened. On the mirror: the board hears `.mirror` with only the move
    /// wired, and nothing else happens (no engine object, no ledger, no observer). On the engine: the engine is made and
    /// started, or, on the in-memory fallback, the board says why it does not run.
    static func launchIfSwitchedOn(container: ModelContainer) {
        let board = SyncEngineBoard.shared
        guard SyncEngineSwitch.current == .own else {
            board.launched(.mirror, actions: mirrorActions(container: container))
            return
        }
        guard !ModelContainerFactory.isRunningInMemory, let url = ModelContainerFactory.storeURL() else {
            // The in-memory fallback is empty: an engine on it would read "everything deleted here". It never runs.
            board.launched(.own, actions: nil)
            let why = ModelContainerFactory.isRunningInMemory ? ModelContainerFactory.localOnlyReason : "the store has no file of its own"
            board.publish(SyncStatus(state: .held(.failed("The sync engine is not running: \(why)."))))
            osLog.error("sync engine: not started: \(why, privacy: .public)")
            return
        }
        let ledger = SyncLedgerStore.forAppStore(storeURL: url, storeInMemory: false)
        let storeName = ModelContainerFactory.storeName
        let arguments = ProcessInfo.processInfo.arguments
        let zone = SyncEngineSwitch.zoneName(storeName: storeName, isDebug: SyncEngineSwitch.isDebugBuild, arguments: arguments)
        let pretend = SyncEngineSwitch.pretendName(storeName: storeName, isDebug: SyncEngineSwitch.isDebugBuild, arguments: arguments)
        let engine = SyncEngine(container: container, ledger: ledger, storeURL: url) { ledger in
            #if DEBUG
            if let pretend {
                return PretendCloudTransport(name: pretend, device: storeName, state: ledger)
            }
            #endif
            return CloudKitTransport(containerID: SyncEngineSwitch.containerID, zoneName: zone, state: ledger,
                                     automaticallySync: true)
        }
        #if DEBUG
        if pretend != nil {
            // The pretend run is watched from a terminal: one line per thing on stdout, as well as in the board's log.
            engine.echo = { line in print("SYNCENGINE \(line)"); fflush(stdout) }
        }
        #endif
        shared = engine
        if let moved = ledger.movedAside { engine.say("The ledger could not be read and was set aside (\(moved.lastPathComponent)); merging afresh") }
        engine.say("Engine: \(pretend.map { "pretend iCloud ‘\($0)’" } ?? "\(SyncEngineSwitch.containerID), zone \(zone)"), store \(storeName)")
        board.launched(.own, actions: engine.actions)
        Task { await engine.start() }
    }

    /// On the mirror, only the move is wired: there is no engine to ask for anything else.
    private static func mirrorActions(container: ModelContainer) -> SyncEngineBoard.Actions {
        SyncEngineBoard.Actions(
            syncNow: { throw SyncCoreError.notStarted },
            resume: {},
            answerPurge: { _ in throw SyncCoreError.notStarted },
            confirmDeletions: { throw SyncCoreError.notStarted },
            move: { engine in try await SyncEngine.move(to: engine, container: container) })
    }

    var actions: SyncEngineBoard.Actions {
        SyncEngineBoard.Actions(
            syncNow: { [core] in try await core.syncNow() },
            resume: { [core] in await core.resume() },
            answerPurge: { [core] choice in try await core.answer(choice) },
            confirmDeletions: { [core] in try await core.confirmDeletions() },
            move: { [container] engine in try await SyncEngine.move(to: engine, container: container) })
    }

    // MARK: - Life cycle

    /// Binds the ledger to the store file, merges rows that share an `id`, starts the brain and the first sync. Order:
    /// the binding before anything reads the ledger (a ledger written for another file would read as "everything
    /// deleted here"); the merge before the brain's first read (it refuses two rows with one key); the save hints before
    /// the brain starts (a save between the two would otherwise wait for the next whole compare).
    func start() async {
        guard !isStarted else { return }
        isStarted = true
        workers.append(Task { [weak self] in await self?.consume() })
        workers.append(Task { [weak self] in await self?.feedHints() })
        await bindLedger()
        mergeSharedIDs(trigger: "before the engine started")
        let hints = self.hints, count = hintCount
        hintObserver = SyncSaveHintObserver(container: container) { keys in
            // On the saving thread, inside the save: only counted and passed on, never waited for.
            hints.yield(Hint(keys: keys, serial: count.next()))
        }
        await core.start()
        await syncNow(reason: "launch")
    }

    /// Binds the ledger to the store file's identity. A ledger reset by the binding takes the transport's state with
    /// it (the state is one of the ledger's facts), so the transport, started after this by the brain, starts with no
    /// state: the reset T13 asks for. `reset()` is not called here because the transport has not started yet
    /// (`CloudKitTransport.reset()` before `start` would make an engine with no delegate).
    private func bindLedger() async {
        guard let storeURL else { return }
        do {
            if let identity = SyncLedgerStore.storeIdentity(at: storeURL) {
                if try await ledger.bind(toStore: identity) {
                    say("The ledger belonged to another store file (a reset or a new store): forgotten, merging afresh")
                }
            } else {
                // A file with no identity cannot be told from another: the cautious answer is a merge without memory.
                try await ledger.reset()
                say("The store file's identity could not be read: the ledger is forgotten, merging afresh")
            }
        } catch {
            // The brain's start reads the ledger and holds `failed` with the words if it cannot.
            say("The ledger could not be bound to the store: \(error.localizedDescription)")
        }
    }

    /// The app came forward: everything compared (whatever wrote the store while it was away), then a sync.
    func cameForward() {
        guard isStarted else { return }
        Task { [core] in
            await core.localChanged(nil)
            await self.syncNow(reason: "the app came forward")
        }
    }

    /// A fetch and a send now, for a push or the background refresh, bounded by `limit` (what the system gives).
    /// Returns whether it finished in time without an error.
    func syncWithin(_ limit: Duration, reason: String) async -> Bool {
        guard isStarted else { return false }
        let core = self.core
        let finished = await withTaskGroup(of: Bool?.self) { group -> Bool in
            group.addTask {
                do { try await core.syncNow(); return true } catch { return false }
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? false
        }
        say("Sync for \(reason): \(finished ? "done" : "not finished in \(limit)")")
        return finished
    }

    /// Returns once everything the brain said before this call has been handled here (posted, re-read), and every save
    /// hint posted before it has been through the brain. Never waits on time: two markers, one down each stream. For
    /// the hosted tests, which then know what the engine knows.
    func settle() async {
        guard isStarted else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in host.barrier { done.resume() } }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            hints.yield(Hint(keys: nil, serial: 0, barrier: { done.resume() }))
        }
    }

    /// Quit: the transport stopped (its state written), no event after.
    func stop() async {
        guard isStarted else { return }
        hintObserver?.stop()
        hintObserver = nil
        await core.stop()
        hints.finish()
        host.finish()
        isStarted = false
    }

    private func syncNow(reason: String) async {
        do {
            try await core.syncNow()
        } catch SyncCoreError.held(let hold) {
            say("Not synced (\(reason)): \(hold.words)")
        } catch {
            say("Sync after \(reason) stopped: \(error.localizedDescription)")
        }
    }

    // MARK: - What the brain says

    /// Reads the host's events in order, on the main actor.
    private func consume() async {
        for await event in host.events {
            switch event {
            case .status(let status):
                board.publish(status)
                widgetFacts.update(status)
                noteQuietIfSo(status)
                if case .held(.duplicates(let keys)) = status.state { mergeForHold(keys) }
            case .wrote(let keys):
                // What the mirror's import used to trigger (the name merge, reminders, widgets, Spotlight, the popout
                // of a task deleted elsewhere, the day anchoring's pass, Settings' counts) hangs on this notice.
                NotificationCenter.default.post(name: .cloudKitImportSucceeded, object: nil)
                // The engine's own save gives no hint (141's WAVE2 point 8), and the day anchoring may have rewritten
                // what it wrote inside that save: read those keys again, so the anchored day goes in the next send.
                hints.yield(Hint(keys: keys, serial: hintCount.next()))
            case .accepted(let keys, let at):
                widgetFacts.accepted(keys, at: at)
                // What the mirror's export used to post: the widgets' completions finish on it.
                NotificationCenter.default.post(name: .cloudKitExportSucceeded, object: nil)
            case .log(let line):
                say(line)
            case .barrier(let reached):
                reached()
            }
        }
    }

    /// Passes the save hints to the brain one at a time, in order.
    private func feedHints() async {
        for await hint in hintStream {
            if let barrier = hint.barrier { barrier(); continue }
            await core.localChanged(hint.keys)
            hintsDone = max(hintsDone, hint.serial)
            noteQuietIfSo(await core.status)
        }
    }

    /// Every save of this process is in the brain's hands and nothing waits: every save until now is in iCloud.
    private func noteQuietIfSo(_ status: SyncStatus) {
        guard hintsDone == hintCount.value, status.state == .idle, status.waiting == 0, status.firstFetchDone else { return }
        let before = widgetFacts.quietAt
        widgetFacts.quiet(at: Date())
        if before == nil || hintsDone > 0 { NotificationCenter.default.post(name: .cloudKitExportSucceeded, object: nil) }
    }

    /// `duplicates`: the app merges the rows that share an `id`, then the brain resumes. A hold that comes back with
    /// the same keys after a merge stays, for the person (the words say what).
    private func mergeForHold(_ keys: [SyncKey]) {
        guard mergedFor != keys else {
            say("Rows that share an id are still there after a merge: \(keys.prefix(5).map(\.description).joined(separator: ", "))")
            return
        }
        mergedFor = keys
        mergeSharedIDs(trigger: "the engine found rows that share an id")
        Task { [core] in await core.resume() }
    }

    func mergeSharedIDs(trigger: String) {
        let context = container.mainContext
        do {
            let merged = try Deduplicator.mergeSharedIDs(in: context)
            let names = try Deduplicator.run(in: context, profileLog: { _, _, _ in })
            if merged.removed > 0 || names.removed > 0 {
                say("Rows merged \(trigger): \(merged.description); by name \(names.description)")
            }
        } catch {
            context.rollback()
            say("Merging rows that share an id failed (\(trigger)): \(error.localizedDescription)")
        }
    }

    func say(_ line: String) {
        Self.osLog.notice("sync engine: \(line, privacy: .public)")
        board.log(line)
        echo?(line)
    }
}
