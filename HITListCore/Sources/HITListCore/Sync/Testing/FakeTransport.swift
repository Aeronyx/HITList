import Foundation

// One device's road to `FakeCloud`: a `SyncTransport` that keeps the rules T1 to T14 (`dev/SYNC-ENGINE.md`, section 6)
// exactly, as `CKSyncEngine` is documented to keep them (`round-28/SDK-CKSyncEngine.md`), with every way it can go
// wrong on a switch. Where the SDK is silent the rules decide, and each place says what was chosen.
//
// Nothing runs by itself: no timer, no background task. What the real engine does "by itself" (a push, its schedule,
// noticing an account change) happens here when a test calls `syncByItself()` or `noticeChanges()`, so every run is
// the same run.

public enum FakeTransportError: Error, Equatable, Sendable {
    /// `fetch()` or `send()` before `start(delegate:)` or after `stop()`.
    case notStarted
    /// No iCloud account on the device: nothing is fetched or sent (T12).
    case noAccount
    /// The network is down (T5): what was pending is still pending.
    case networkDown
    /// iCloud took the batch but its answer never came back (CloudKit's `serverResponseLost`): the changes are still
    /// pending, and sending them again meets the versions iCloud saved.
    case responseLost
    /// The device's process "died" (a crash switch): nothing more happens on this transport. Make a new one on the
    /// same `SyncTransportState`, as a relaunch would.
    case crashed
    /// `fetch()` or `send()` from inside `handle` (only when `Options.onMisuse` returns instead of stopping).
    case calledFromHandle
}

/// The events a transport can deliver, by kind, for the switches that pick one.
public enum FakeEventKind: String, Sendable, CaseIterable {
    case account, willFetch, fetched, zoneLost, didFetch, willSend, sent, didSend

    init(_ event: TransportEvent) {
        switch event {
        case .account: self = .account
        case .willFetch: self = .willFetch
        case .fetched: self = .fetched
        case .zoneLost: self = .zoneLost
        case .didFetch: self = .didFetch
        case .willSend: self = .willSend
        case .sent: self = .sent
        case .didSend: self = .didSend
        }
    }
}

/// Where a device's process can die (`FakeTransport.crash(_:)`).
public enum FakeCrash: Hashable, Sendable {
    /// The next event of this kind is handled, then the process dies before the transport records it: the bookmark
    /// does not move, the pending list is not saved. After a relaunch the same changes arrive again.
    case afterHandling(FakeEventKind)
    /// iCloud has applied the next batch; the process dies before `sent` reaches the device: iCloud holds the save,
    /// the device does not know.
    case beforeSent
}

/// What a test's observer hears after each event was handled (`FakeTransport.observe(_:)`).
public struct FakeDelivery: Sendable {
    public var kind: FakeEventKind
    /// 0 the first time, 1 when the event is delivered again (`deliverTwice`).
    public var round: Int
    /// Whether this event will be delivered again right after.
    public var willRepeat: Bool
    /// A `didFetch` or `didSend` that carried an error.
    public var failed: Bool = false
}

enum FakeTransportContext {
    /// The transports whose `handle` (or `recordToSend`) the current task is inside.
    @TaskLocal static var handling: Set<UUID> = []
}

public actor FakeTransport: SyncTransport {
    public struct Options: Sendable {
        /// Records per batch (T10): CloudKit's is 250, saves and deletes together. Tests use 2 or 3.
        public var batchSize: Int
        /// Records and removals per `fetched` event (T2). CloudKit's page size is not documented.
        public var fetchPageSize: Int
        /// Deliver the records of each fetched page in an order drawn from `seed` instead of the log's (T2: "in no
        /// particular order"; a task before its Group).
        public var shuffleFetches: Bool
        /// A device's next fetch brings back what it saved itself (T2). On by default: the real engine's behaviour is
        /// not documented, so the brain must not care either way.
        public var echo: Bool
        public var seed: UInt64
        /// What a programming error does (a call from inside `handle`): stops the process by default, as the real
        /// engine would hang it. A test of the check passes a closure that records the words instead.
        public var onMisuse: @Sendable (String) -> Void

        public init(batchSize: Int = 250, fetchPageSize: Int = 200, shuffleFetches: Bool = false, echo: Bool = true,
                    seed: UInt64 = 0, onMisuse: @escaping @Sendable (String) -> Void = { preconditionFailure($0) }) {
            self.batchSize = batchSize
            self.fetchPageSize = fetchPageSize
            self.shuffleFetches = shuffleFetches
            self.echo = echo
            self.seed = seed
            self.onMisuse = onMisuse
        }
    }

    /// What the transport keeps between launches, through `SyncTransportState` (CloudKit: the engine's state
    /// serialization). Forgotten with the ledger.
    struct State: Equatable, Sendable {
        /// The account this state belongs to; nil before the transport first saw one.
        var account: String?
        /// The making of the zone this device knows (`FakeCloud.Zone.incarnation`); nil when it knows none.
        var zone: Int?
        /// The log position fetched up to, in that zone; nil: nothing fetched yet (the next fetch brings everything).
        var bookmark: Int?
        /// T3: in the order added, a key once.
        var pending: [PendingChange] = []
        /// With `echo` off: the version of each record this device saved since it last fetched that record.
        var ownSaves: [String: Int] = [:]
        /// An account change found and not yet handled by the brain: kept with the state, so that a relaunch before
        /// it is delivered delivers it then (as `CKSyncEngine`'s saved state still names the old account until a
        /// later state is stored). Cleared only after `handle` returned for it.
        var announce: AccountChange?

        init() {}

        // Kept as lines of text, one fact per line ("account alice", "save TaskItem 6B1F…"): what the state holds is
        // readable in a failing test, and a run of thousands of steps does not spend its time in a JSON coder. A
        // record's type never holds a space; its name is the rest of the line.
        var data: Data {
            var lines = ["fake-transport 1"]
            if let account { lines.append("account \(account)") }
            if let zone { lines.append("zone \(zone)") }
            if let bookmark { lines.append("bookmark \(bookmark)") }
            for change in pending {
                switch change {
                case .save(let key): lines.append("save \(key.type) \(key.name)")
                case .delete(let key): lines.append("delete \(key.type) \(key.name)")
                }
            }
            for name in ownSaves.keys.sorted() { lines.append("own \(ownSaves[name]!) \(name)") }
            switch announce {
            case .signedIn(let current)?: lines.append("announce in \(current)")
            case .signedOut(let previous)?: lines.append("announce out \(previous)")
            case .switched(let previous, let current)?: lines.append("announce switch \(previous)\u{1F}\(current)")
            case nil: break
            }
            return Data(lines.joined(separator: "\n").utf8)
        }

        init?(_ data: Data) {
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.first == "fake-transport 1" else { return nil }
            for line in lines.dropFirst() {
                let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 2 else { return nil }
                switch parts[0] {
                case "account": account = parts.dropFirst().joined(separator: " ")
                case "zone": zone = Int(parts[1])
                case "bookmark": bookmark = Int(parts[1])
                case "save", "delete":
                    guard parts.count == 3 else { return nil }
                    let key = SyncKey(type: parts[1], name: parts[2])
                    pending.append(parts[0] == "save" ? .save(key) : .delete(key))
                case "own":
                    guard parts.count == 3, let tag = Int(parts[1]) else { return nil }
                    ownSaves[parts[2]] = tag
                case "announce":
                    guard parts.count == 3 else { return nil }
                    switch parts[1] {
                    case "in": announce = .signedIn(current: parts[2])
                    case "out": announce = .signedOut(previous: parts[2])
                    case "switch":
                        let both = parts[2].split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
                        guard both.count == 2 else { return nil }
                        announce = .switched(previous: both[0], current: both[1])
                    default: return nil
                    }
                default: return nil
                }
            }
        }
    }

    public nonisolated let device: String
    public let cloud: FakeCloud
    private let store: any SyncTransportState
    private var options: Options
    private nonisolated let identity = UUID()

    private var state = State()
    private var delegate: (any SyncTransportDelegate)?
    private var started = false
    private var dead = false
    /// Changes on every `reset()` and every forgetting (an account change, a lost zone), so an operation in flight
    /// does not move a bookmark that was forgotten under it.
    private var generation = 0
    private var random: SimRandom

    // Switches.
    private var networkUp = true
    private var networkFailsAfter: Int?
    private var loseNextResponse = false
    private var crashPoint: FakeCrash?
    private var twice: Set<FakeEventKind> = []
    private var observer: (@Sendable (FakeDelivery) async -> Void)?

    /// Inside `handle`: what the brain adds or removes then is saved with the event, after it (`CKSyncEngine` hands
    /// its state over in a later `stateUpdate` event), so a crash right after the event loses it.
    private var delivering = false
    private var unsaved = false

    // One operation at a time (T1): a second fetch or send waits for the first.
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// How many events were delivered, all kinds (a repeat counts), for tests.
    public private(set) var deliveredCount = 0

    public init(cloud: FakeCloud, device: String, state: any SyncTransportState, options: Options = Options()) {
        self.cloud = cloud
        self.device = device
        self.store = state
        self.options = options
        self.random = SimRandom(seed: options.seed)
    }

    // MARK: SyncTransport

    public func start(delegate: any SyncTransportDelegate) async {
        guard !dead else { return }
        if let data = await store.loadTransportState(), let saved = State(data) {
            state = saved
        } else {
            // No state, or one this build cannot read: as `CKSyncEngine` with a nil serialization, a first launch.
            state = State()
        }
        self.delegate = delegate
        started = true
        // T12. The account is compared now and, when it changed, the bookmark and the list are forgotten now, so
        // that what the brain adds from here on is kept. The event itself is the first one of the next operation
        // (or of `noticeChanges()`): never delivered from inside `start`, as `CKSyncEngine` delivers nothing from
        // its initialiser, and a brain that holds its own queue while it starts the transport must not be called
        // back into it.
        await compareAccount()
    }

    /// T12: the device's account against the one the state belongs to. When they differ the bookmark and the list are
    /// forgotten now, and one change is kept to announce: from the account the brain last heard of to this one (SDK:
    /// several changes while the app was away are one event).
    private func compareAccount() async {
        let current = await cloud.account(of: device)
        guard current != state.account else { return }
        let heard: String?
        switch state.announce {
        case .signedIn?: heard = nil
        case .signedOut(let previous)?, .switched(let previous, _)?: heard = previous
        case nil: heard = state.account
        }
        state.announce = FakeTransport.change(from: heard, to: current)
        forget()
        state.account = current
        await persist()
    }

    public func stop() async {
        delegate = nil
        started = false
    }

    public func pending() async -> [PendingChange] { dead ? [] : state.pending }

    public func add(_ changes: [PendingChange]) async {
        guard !dead else { return }
        var changed = false
        for change in changes {
            if let index = state.pending.firstIndex(where: { $0.key == change.key }) {
                // T3: adding one that is there changes nothing; a save and a delete of one key replace each other
                // and the last added stays. It goes to the end, where it was added (`CKSyncEngine` does not say
                // where the survivor sits; the end keeps "in the order they were added" true).
                if state.pending[index] == change { continue }
                state.pending.remove(at: index)
            }
            state.pending.append(change)
            changed = true
        }
        if changed { await persistUnlessDelivering() }
    }

    public func remove(_ changes: [PendingChange]) async {
        guard !dead else { return }
        let gone = Set(changes)
        let before = state.pending.count
        state.pending.removeAll { gone.contains($0) }
        if state.pending.count != before { await persistUnlessDelivering() }
    }

    private func persistUnlessDelivering() async {
        if delivering { unsaved = true } else { await persist() }
    }

    public func fetch() async throws {
        try check("fetch()")
        await acquire()
        defer { release() }
        try await announceAccount()
        try await runFetch()
    }

    public func send() async throws {
        try check("send()")
        await acquire()
        defer { release() }
        try await announceAccount()
        try await runSend()
    }

    public func reset() async {
        guard !dead else { return }
        // T13. The account stays: a reset is the ledger's, not the device's sign-in. The zone this device knew is
        // forgotten with the bookmark, as a `CKSyncEngine` made with no state would forget it.
        forget()
        await persist()
    }

    // MARK: What the real engine does by itself (T14), when a test says so

    /// The transport syncs by itself, as on a push or its schedule: a fetch, then a send. The same events arrive as
    /// for `fetch()` and `send()`; trouble is reported only in `didFetch` / `didSend` (and a crash stops it).
    public func syncByItself() async {
        guard (try? checkNotInHandle("syncByItself()")) != nil, started, !dead else { return }
        await acquire()
        defer { release() }
        do {
            try await announceAccount()
            try await runFetch()
            try await runSend()
        } catch {
            // Reported through the events already; nobody called, so nobody is told otherwise.
        }
    }

    /// The device tells the running transport what changed under it (an account signed in, out or switched): the
    /// account event now, if there is one.
    public func noticeChanges() async {
        guard (try? checkNotInHandle("noticeChanges()")) != nil, started, !dead else { return }
        await acquire()
        defer { release() }
        try? await announceAccount()
    }

    // MARK: Switches

    /// The network down (`fetch`/`send` throw `networkDown`, the list is kept: T5) or up again.
    public func setNetwork(up: Bool) {
        networkUp = up
        networkFailsAfter = nil
    }

    /// The network drops after `count` more batches sent or pages fetched have gone through: the fetch or send in
    /// progress stops there (T5), what was not acknowledged stays pending.
    public func dropNetwork(after count: Int) { networkFailsAfter = count }

    /// iCloud applies the next batch, and its answer is lost on the way back (`serverResponseLost`).
    public func loseNextResponse(_ lose: Bool = true) { loseNextResponse = lose }

    /// The device's process dies at this point, once.
    public func crash(_ point: FakeCrash) { crashPoint = point }

    /// The next event of this kind is delivered a second time, right after the first (I4).
    public func deliverTwice(_ kind: FakeEventKind) { twice.insert(kind) }

    /// Forgets the bookmark (and nothing else): the next fetch brings every record (T2).
    public func loseBookmark() async {
        guard !dead else { return }
        state.bookmark = nil
        generation += 1
        await persist()
    }

    /// Hears every event after it was handled (a repeat too), for checks that compare the device before and after.
    public func observe(_ observer: (@Sendable (FakeDelivery) async -> Void)?) { self.observer = observer }

    public func setOptions(_ options: Options) { self.options = options }

    /// Whether a crash switch has stopped this transport.
    public var hasCrashed: Bool { dead }

    // MARK: Fetch (T2, T11)

    private func runFetch() async throws {
        guard let account = state.account else { throw FakeTransportError.noAccount }
        guard networkUp else {
            // T5. SDK: `willFetchChanges` "might not always occur"; here it does, so the words reach the status.
            try await deliver(.willFetch)
            try await deliver(.didFetch(error: "The network is unavailable."))
            throw FakeTransportError.networkDown
        }
        try await deliver(.willFetch)
        if let known = state.zone, let reason = await cloud.loss(account: account, incarnation: known) {
            // T11: by the time the brain hears of it, the bookmark and the list are forgotten.
            forget()
            await persist()
            try await deliver(.zoneLost(reason))
        }
        guard let incarnation = await cloud.incarnation(account: account) else {
            try await deliver(.didFetch(error: nil))
            return
        }
        if state.zone != incarnation {
            // A zone this device has not known (its first fetch, or one made again after a loss): everything in it.
            state.zone = incarnation
            state.bookmark = nil
        }
        let generation = self.generation
        let entries = await cloud.changes(account: account, incarnation: incarnation, after: state.bookmark)
        var start = 0
        while start < entries.count {
            let page = Array(entries[start..<min(start + max(1, options.fetchPageSize), entries.count)])
            start += page.count
            guard networkStillUp() else {
                try await deliver(.didFetch(error: "The network connection was lost."))
                throw FakeTransportError.networkDown
            }
            var changed: [CloudRecord] = []
            var removed: [SyncKey] = []
            var items = page
            if options.shuffleFetches { random.shuffle(&items) }
            for entry in items {
                if let record = entry.record {
                    let tag = FakeCloud.token(record.system)?.tag
                    if !options.echo, let tag, state.ownSaves[entry.key.description] == tag { continue }
                    changed.append(record)
                } else {
                    removed.append(entry.key)
                }
            }
            if !changed.isEmpty || !removed.isEmpty {
                try await deliver(.fetched(changed: changed, removed: removed))
            }
            guard generation == self.generation else {
                // The bookmark was forgotten while the page was handled (a `reset()` from the brain): moving it now
                // would skip what came before. The rest of this fetch is not delivered; the next brings everything.
                // (The SDK says nothing of a reset during a fetch.)
                try await deliver(.didFetch(error: "The transport was reset during the fetch."))
                return
            }
            // T1: the page was handled and kept; only now does the bookmark move past it.
            state.bookmark = page.map(\.seq).max()
            for entry in page { state.ownSaves[entry.key.description] = nil }
            await persist()
        }
        try await deliver(.didFetch(error: nil))
    }

    // MARK: Send (T3 to T11)

    private func runSend() async throws {
        guard let account = state.account else { throw FakeTransportError.noAccount }
        guard networkUp else {
            try await deliver(.willSend)
            try await deliver(.didSend(error: "The network is unavailable."))
            throw FakeTransportError.networkDown
        }
        try await deliver(.willSend)
        // A change goes at most once in one send: a conflict the brain adds again goes in the next one, so a send
        // always ends. (`CKSyncEngine` asks for batches "until your app has no more changes"; it does not say
        // whether a change added during the send joins it.)
        var attempted = Set<PendingChange>()
        while true {
            if let known = state.zone, let reason = await cloud.loss(account: account, incarnation: known) {
                // T11, found by a send. The list is forgotten first; what the brain adds while it handles the loss
                // goes in this send, to a zone made again.
                forget()
                await persist()
                try await deliver(.zoneLost(reason))
                attempted = []
                continue
            }
            let batch = try await nextBatch(skipping: &attempted)
            if batch.saves.isEmpty && batch.deletes.isEmpty && batch.failed.isEmpty { break }
            guard networkStillUp() else {
                try await deliver(.didSend(error: "The network connection was lost."))
                throw FakeTransportError.networkDown
            }
            var result = FakeCloud.BatchResult()
            if !batch.saves.isEmpty || !batch.deletes.isEmpty {
                if state.zone == nil {
                    // The transport makes the zone when it has something to send and knows none (section 3).
                    state.zone = await cloud.ensureZone(account: account)
                    state.bookmark = nil
                    await persist()
                }
                guard let incarnation = state.zone,
                      let applied = await cloud.apply(account: account, incarnation: incarnation, saves: batch.saves,
                                                      deletes: batch.deletes) else {
                    // The zone was lost since the check: the next turn of the loop says so, and this batch goes again
                    // if the brain adds it again.
                    continue
                }
                result = applied
            }
            if loseNextResponse {
                loseNextResponse = false
                try await deliver(.didSend(error: "The network connection was lost before iCloud answered."))
                throw FakeTransportError.responseLost
            }
            if crashPoint == .beforeSent {
                crashPoint = nil
                die()
                throw FakeTransportError.crashed
            }
            for (key, failure) in batch.failed { result.failed[key] = failure }
            // The changes iCloud answered for leave the list before the brain hears of them (T4, T6, T7, T9), so
            // that whatever it adds while it handles the answer is kept.
            var answered = Set<PendingChange>()
            for record in result.saved {
                answered.insert(.save(record.key))
                if !options.echo, let tag = FakeCloud.token(record.system)?.tag {
                    state.ownSaves[record.key.description] = tag
                }
            }
            for key in result.removed { answered.insert(.delete(key)) }
            for change in batch.sent where result.failed[change.key] != nil { answered.insert(change) }
            state.pending.removeAll { answered.contains($0) }
            try await deliver(.sent(saved: result.saved, removed: result.removed, failed: result.failed))
            await persist()
        }
        try await deliver(.didSend(error: nil))
    }

    private struct Batch {
        var saves: [FakeCloud.WireSave] = []
        var deletes: [SyncKey] = []
        /// Refused before they left the device (a type this build does not sync).
        var failed: [SyncKey: SendFailure] = [:]
        /// The changes the batch carries, as they were on the list.
        var sent: [PendingChange] = []
    }

    /// The next batch, from the list as it is now, in its order (T3, T10). A save's record is asked for when its
    /// turn comes; nil drops the change (T3).
    private func nextBatch(skipping attempted: inout Set<PendingChange>) async throws -> Batch {
        var batch = Batch()
        let size = max(1, options.batchSize)
        var index = 0
        while batch.sent.count < size, index < state.pending.count {
            let change = state.pending[index]
            index += 1
            guard !attempted.contains(change) else { continue }
            attempted.insert(change)
            switch change {
            case .delete(let key):
                batch.deletes.append(key)
                batch.sent.append(change)
            case .save(let key):
                guard let delegate, !dead else { throw dead ? FakeTransportError.crashed : FakeTransportError.notStarted }
                let identity = self.identity
                let outgoing = await FakeTransportContext.$handling.withValue(FakeTransportContext.handling.union([identity])) {
                    await delegate.recordToSend(key)
                }
                // The list may have changed while the brain answered: look the change up again.
                guard let outgoing else {
                    if let at = state.pending.firstIndex(of: change) {
                        state.pending.remove(at: at)
                        await persist()
                    }
                    index = 0
                    continue
                }
                guard outgoing.record.key == key else {
                    options.onMisuse("FakeTransport(\(device)): recordToSend(\(key)) answered with \(outgoing.record.key)")
                    batch.failed[key] = .rejected(code: 12, message: "recordToSend answered with another record")
                    batch.sent.append(change)
                    continue
                }
                if let wire = FakeTransport.wire(outgoing) {
                    batch.saves.append(wire)
                } else {
                    batch.failed[key] = .rejected(code: 12, message: "\(key.type) is not a type this build syncs")
                }
                batch.sent.append(change)
            }
            // A change may have been taken off (or added) while the brain answered: start over from the top, skipping
            // what this send has already taken.
            index = 0
        }
        return batch
    }

    /// T4: what a save writes. Every field of the record's type: present with its value, absent emptied, and
    /// `deletedAt` likewise. A key the type does not list is neither sent nor cleared. Nil for a type this build
    /// does not sync (`Meta` has its one field).
    static func wire(_ outgoing: OutgoingRecord) -> FakeCloud.WireSave? {
        let key = outgoing.record.key
        let names: [String]
        if let type = SyncSchema.type(key.type) {
            names = type.fields.map(\.key) + [SyncSchema.deletedAt]
        } else if key.type == SyncSchema.metaType {
            names = [SyncSchema.metaFormatVersion]
        } else {
            return nil
        }
        var write: [String: SyncValue?] = [:]
        for name in names { write[name] = .some(outgoing.record.fields[name]) }
        return FakeCloud.WireSave(key: key, system: outgoing.system, write: write)
    }

    // MARK: Delivering (T1)

    /// Hands one event to the brain and waits until it is handled. Throws when there is nobody to hand it to, or when
    /// the process "dies" after it.
    private func deliver(_ event: TransportEvent) async throws {
        let kind = FakeEventKind(event)
        let rounds = twice.remove(kind) == nil ? 1 : 2
        for round in 0..<rounds {
            guard let delegate, !dead else { throw dead ? FakeTransportError.crashed : FakeTransportError.notStarted }
            let identity = self.identity
            delivering = true
            await FakeTransportContext.$handling.withValue(FakeTransportContext.handling.union([identity])) {
                await delegate.handle(event)
            }
            delivering = false
            deliveredCount += 1
            if let observer {
                var failed = false
                if case .didFetch(let error?) = event { failed = !error.isEmpty }
                if case .didSend(let error?) = event { failed = !error.isEmpty }
                await observer(FakeDelivery(kind: kind, round: round, willRepeat: round + 1 < rounds, failed: failed))
            }
        }
        if crashPoint == .afterHandling(kind) {
            crashPoint = nil
            die()
            throw FakeTransportError.crashed
        }
        if unsaved {
            unsaved = false
            await persist()
        }
    }

    private func announceAccount() async throws {
        // Changed while running: forgotten now, announced now.
        await compareAccount()
        if let change = state.announce {
            try await deliver(.account(change))
            // Handled (a crash in `deliver` throws before this): only now is it off the state.
            state.announce = nil
            await persist()
        }
    }

    static func change(from previous: String?, to current: String?) -> AccountChange? {
        switch (previous, current) {
        case (nil, let current?): return .signedIn(current: current)
        case (let previous?, nil): return .signedOut(previous: previous)
        case (let previous?, let current?): return .switched(previous: previous, current: current)
        case (nil, nil): return nil
        }
    }

    // MARK: -

    private func check(_ call: String) throws {
        try checkNotInHandle(call)
        if dead { throw FakeTransportError.crashed }
        guard started, delegate != nil else { throw FakeTransportError.notStarted }
    }

    /// T1: a call that waits for events, made while one is being handled, would hang the real engine. Said loudly.
    /// (A `Task` started inside `handle` inherits the mark and is flagged too: it would not hang, but it is the same
    /// mistake one step removed.)
    private func checkNotInHandle(_ call: String) throws {
        if FakeTransportContext.handling.contains(identity) {
            options.onMisuse("FakeTransport(\(device)).\(call) was called from inside the transport's own delegate "
                + "call (handle or recordToSend). CKSyncEngine deadlocks there: \(call) waits for events the delegate "
                + "has not finished handling (T1). Call it after handle returns.")
            throw FakeTransportError.calledFromHandle
        }
    }

    private func networkStillUp() -> Bool {
        if let count = networkFailsAfter {
            if count <= 0 {
                networkUp = false
                networkFailsAfter = nil
            } else {
                networkFailsAfter = count - 1
            }
        }
        return networkUp
    }

    private func forget() {
        state.zone = nil
        state.bookmark = nil
        state.pending = []
        state.ownSaves = [:]
        generation += 1
    }

    private func die() {
        dead = true
        delegate = nil
        started = false
    }

    private func persist() async {
        guard !dead else { return }
        await store.saveTransportState(state.data)
    }

    private func acquire() async {
        if busy {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiting.append(continuation)
            }
        } else {
            busy = true
        }
    }

    private func release() {
        if waiting.isEmpty {
            busy = false
        } else {
            // Handed straight to the next in line: `busy` stays true.
            waiting.removeFirst().resume()
        }
    }
}
