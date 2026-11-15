import Foundation

/// The sync engine's brain (`dev/SYNC-ENGINE.md`): finds what changed on the device by comparing it with what iCloud
/// last held, settles what arrives from iCloud (`RecordMerge`), keeps the engine's memory (`SyncLedger`), keeps the
/// transport's pending list matching what is waiting, and says what the bolt should show (`SyncStatus`). It knows
/// neither SwiftData nor CloudKit: the device is a `SyncLocalStore`, iCloud a `SyncTransport`.
///
/// One thing at a time: every operation (an event, a compare, a record asked for, a hold lifted) goes through one
/// queue of its own, so a compare never runs in the middle of an event and two never run at once, even though an
/// actor lets its methods interleave at every `await`. The transport is called from inside an operation only for
/// its list (`pending`, `add`, `remove`) and `reset`, which never wait for the brain; `start`, `stop`, `fetch` and
/// `send` are called outside the queue, because their events come back through it.
///
/// Files: this one (the parts, the queue, the public surface, the status), `SyncCore+Compare` (finding what changed,
/// what to send), `SyncCore+Settle` (what arrives, what comes back from a send), `SyncCore+Holds` (accounts, a lost
/// zone, holds and their ways out).
public actor SyncCore: SyncTransportDelegate {
    // MARK: The parts

    let store: any SyncLocalStore
    let ledger: any SyncLedger
    let transport: any SyncTransport
    /// Weak: the app's engine owns the brain and is usually its host.
    weak var host: (any SyncHost)?
    let clock: @Sendable () -> Date
    let log: @Sendable (String) -> Void

    // MARK: The ledger, as read at start and kept in step with every write (`commit`)

    var entries: [SyncKey: LedgerEntry] = [:]
    var deferred: [SyncKey: CloudRecord] = [:]
    var firstFetchDone = false
    var account: String?
    var hold: SyncHold?
    /// Fetched records were let go unread (a hold, a write that failed): the transport must bring everything again
    /// before the brain trusts its memory. Kept as a fact too, so a relaunch does it.
    var refetch = false

    // MARK: Working state, not kept

    enum Phase { case off, starting, running }
    var phase = Phase.off
    /// The ledger has been read: the brain may compare and settle.
    var loaded = false
    var transportStarted = false
    var fetching = false
    var sending = false
    /// The keys waiting to go: the last compare's answer for each key (`waiting.count` is the bolt's number).
    var waiting: Set<SyncKey> = []
    /// Records iCloud refused for good, and what the device held when it did: kept out of the list until the item
    /// changes. Not kept across a launch: each launch tries a refused record once more, never in a loop.
    var refused: [SyncKey: Refusal] = [:]
    var fetchError: String?
    var sendError: String?
    /// Words that go with the current hold (a backup that failed).
    var holdNote: String?
    var lastFetchEnded: Date?
    var lastSendEnded: Date?

    struct Refusal {
        /// The device's item when iCloud refused it (nil: the marker of an item deleted here).
        var local: SyncRecord?
        var words: String
    }

    // MARK: The status

    public private(set) var status = SyncStatus()
    private var listeners: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]

    // MARK: The queue

    private var busy = false
    private var queue: [CheckedContinuation<Void, Never>] = []

    /// The ledger's own fact this brain adds (`LedgerFact` names the contract's).
    static let refetchFact = "refetch"
    static let metaKey = SyncKey(type: SyncSchema.metaType, name: SyncSchema.metaName)
    /// How many times a record the person changed between the read and the write is decided again within one event
    /// before it is set aside for the next.
    static let staleRounds = 3

    public init(store: any SyncLocalStore, ledger: any SyncLedger, transport: any SyncTransport,
                host: (any SyncHost)?, clock: @escaping @Sendable () -> Date = { Date() },
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.store = store
        self.ledger = ledger
        self.transport = transport
        self.host = host
        self.clock = clock
        self.log = log
    }

    // MARK: - Public surface

    /// Reads the ledger, starts the transport with this brain as its delegate, and compares everything. Lifts what a
    /// new start lifts: a failure (tried again), duplicates (checked again), a full iCloud (tried again), and a
    /// format this build now reads. A ledger that cannot be read holds the brain (`failed`) and starts nothing.
    public func start() async {
        let ready: Bool = await serially { await loadMemory() }
        guard ready else { return }
        if !transportStarted {
            // Outside the queue: an account that changed while the app was not running arrives as the first event,
            // through `handle`, which takes its turn in the queue.
            transportStarted = true
            await transport.start(delegate: self)
        }
        await serially {
            phase = .running
            await liftForStart()
            await compare(nil)
            publish()
        }
    }

    /// Stops the transport; no event arrives after this returns. The memory stays as it is.
    public func stop() async {
        if transportStarted {
            await transport.stop()
            transportStarted = false
        }
        await serially {
            phase = .off
            fetching = false
            sending = false
            publish()
        }
    }

    /// The device's items changed: compare them with the ledger and make the transport's list match (section 4).
    /// `keys` is the app's hint of what a save touched; nil compares everything (at start, on return to the app,
    /// after an import). A nil compare also tries a full iCloud again (`storageFull`).
    public func localChanged(_ keys: Set<SyncKey>?) async {
        await serially {
            guard loaded else { return }
            if keys == nil, hold == .storageFull { await lift(resetTransport: false) }
            await compare(keys)
            publish()
        }
    }

    /// A fetch, then a send: the person's "sync now". Throws `SyncCoreError.held` while held (a full iCloud is tried
    /// again first), and what the transport throws. Never call it from inside `handle`.
    public func syncNow() async throws {
        try await serially {
            guard loaded, transportStarted else { throw SyncCoreError.notStarted }
            if hold == .storageFull {
                await lift(resetTransport: false)
                await compare(nil)
            }
            publish()
            if let hold { throw SyncCoreError.held(hold) }
        }
        try await transport.fetch()
        try await transport.send()
    }

    /// Tries again after a hold the app or time can lift: `duplicates` (after the app merged them), `failed`,
    /// `storageFull`. Everything iCloud brought while held is fetched again. Other holds stay.
    public func resume() async {
        await serially {
            guard loaded else { return }
            switch hold {
            case .duplicates?, .failed?, .storageFull?:
                log("Resumed after: \(hold?.words ?? "")")
                await lift(resetTransport: true)
            default: break
            }
            await compare(nil)
            publish()
        }
    }

    /// The person's answer after HITList's data was removed from iCloud (`SyncHold.zonePurged`). Throws
    /// `SyncCoreError.noQuestion` when the brain is not asking, and what the host's backup throws (nothing is then
    /// removed and the brain stays held).
    public func answer(_ choice: PurgeAnswer) async throws {
        try await serially {
            guard hold == .zonePurged else { throw SyncCoreError.noQuestion }
            try await answerPurge(choice)
            publish()
        }
    }

    /// The status's changes, one value per change, starting with the current one.
    public func statusUpdates() -> AsyncStream<SyncStatus> {
        let id = UUID()
        var continuation: AsyncStream<SyncStatus>.Continuation!
        let stream = AsyncStream<SyncStatus>(bufferingPolicy: .bufferingNewest(64)) { continuation = $0 }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.dropListener(id) }
        }
        continuation.yield(status)
        listeners[id] = continuation
        return stream
    }

    // MARK: - SyncTransportDelegate

    public func handle(_ event: TransportEvent) async {
        await serially {
            await process(event)
            publish()
        }
    }

    public func recordToSend(_ key: SyncKey) async -> OutgoingRecord? {
        await serially { await outgoing(key) }
    }

    // MARK: - Events

    private func process(_ event: TransportEvent) async {
        guard loaded else {
            log("An event arrived before the engine's memory was read; let go")
            return
        }
        switch event {
        case .account(let change):
            await accountChanged(change)
        case .willFetch:
            fetching = true
        case .fetched(let changed, let removed):
            await fetched(changed, removed: removed)
        case .zoneLost(let reason):
            await zoneLost(reason)
        case .didFetch(let error):
            fetching = false
            await didFetch(error: error)
        case .willSend:
            sending = true
        case .sent(let saved, let removed, let failed):
            await sent(saved, removed: removed, failed: failed)
        case .didSend(let error):
            sending = false
            sendError = error
            if let error { log("A send stopped early: \(error). What is waiting stays waiting") }
        }
    }

    // MARK: - The queue

    /// Runs `body` when every operation before it has finished, and holds the next until it has.
    func serially<T>(_ body: () async throws -> T) async rethrows -> T {
        await enter()
        defer { leave() }
        return try await body()
    }

    private func enter() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.append(continuation)
        }
    }

    private func leave() {
        // Handed straight to the next in line: `busy` stays set, so nothing can slip in between.
        if queue.isEmpty { busy = false } else { queue.removeFirst().resume() }
    }

    /// Operations waiting their turn (tests).
    var queuedOperations: Int { queue.count }

    // MARK: - The ledger

    /// Writes to the ledger, all or nothing, then to the brain's copy of it. Nothing is changed in memory if the
    /// write throws.
    func commit(_ write: LedgerWrite) async throws {
        guard !write.isEmpty else { return }
        try await ledger.write(write)
        for entry in write.upsert { entries[entry.key] = entry }
        for key in write.remove { entries[key] = nil }
        for record in write.deferUpsert { deferred[record.key] = record }
        for key in write.deferRemove { deferred[key] = nil }
        for (name, value) in write.facts {
            switch name {
            case LedgerFact.account: account = value.flatMap { String(data: $0, encoding: .utf8) }
            case LedgerFact.firstFetchDone: firstFetchDone = value != nil
            case Self.refetchFact: refetch = value != nil
            default: break
            }
        }
    }

    /// Reads the whole ledger into memory. False when it cannot be read: the brain is then held (`failed`).
    private func loadMemory() async -> Bool {
        phase = .starting
        publish()
        do {
            let list = try await ledger.entries()
            let aside = try await ledger.deferred()
            let first = try await ledger.fact(LedgerFact.firstFetchDone)
            let owner = try await ledger.fact(LedgerFact.account)
            let held = try await ledger.fact(LedgerFact.hold)
            let again = try await ledger.fact(Self.refetchFact)
            entries = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
            deferred = Dictionary(aside.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
            firstFetchDone = first != nil
            account = owner.flatMap { String(data: $0, encoding: .utf8) }
            refetch = refetch || again != nil
            if let held { hold = try? JSONDecoder().decode(SyncHold.self, from: held) } else if hold?.persists == true { hold = nil }
            loaded = true
            log("Started: \(entries.count) records remembered, \(deferred.count) set aside" +
                (hold.map { ", held: \($0.words)" } ?? ""))
            return true
        } catch {
            phase = .off
            hold = .failed("The engine's memory could not be read: \(error)")
            log("Not started: \(hold?.words ?? "")")
            publish()
            return false
        }
    }

    // MARK: - The status

    func publish() {
        let next = currentStatus()
        guard next != status else { return }
        status = next
        for continuation in listeners.values { continuation.yield(next) }
        host?.statusDidChange(next)
    }

    private func currentStatus() -> SyncStatus {
        let state: SyncStatus.State
        switch phase {
        case .off:
            // A start that failed says why; a brain stopped on purpose is simply off.
            if case .failed? = hold { state = .held(hold!) } else { state = .off }
        case .starting: state = .starting
        case .running:
            if let hold { state = .held(hold) } else if fetching { state = .fetching } else if sending { state = .sending } else { state = .idle }
        }
        let refusedKeys = refused.keys.sorted()
        let refusalWords = refusedKeys.first.flatMap { key in refused[key].map { "\(key): \($0.words)" } }
        return SyncStatus(state: state, waiting: waiting.count, firstFetchDone: firstFetchDone,
                          lastFetchEnded: lastFetchEnded, lastSendEnded: lastSendEnded,
                          lastError: fetchError ?? sendError ?? holdNote ?? refusalWords, refused: refusedKeys)
    }

    private func dropListener(_ id: UUID) {
        listeners[id] = nil
    }

    // MARK: - Helpers

    /// What a ledger keeps as a base: the fields this build knows, `data` as digests. (`Meta/meta`, a type the
    /// schema does not list, is kept whole.)
    static func base(_ record: SyncRecord) -> SyncRecord {
        (SyncSchema.known(record) ?? record).comparable
    }

    /// The records `record` points at.
    static func references(_ record: SyncRecord) -> [SyncKey] {
        guard let type = SyncSchema.type(record.key.type) else { return [] }
        var out: [SyncKey] = []
        for field in type.fields {
            switch (field.kind, record.fields[field.key]) {
            case (.reference(let target), .reference(let name)?):
                out.append(SyncKey(type: target, name: name))
            case (.references(let target), .referenceList(let names)?):
                out.append(contentsOf: names.map { SyncKey(type: target, name: $0) })
            default: break
            }
        }
        return out
    }

    /// The order changes are added to the list in: those pointed at first (`SyncSchema.types`), then by name.
    static func sendOrder(_ a: SyncKey, _ b: SyncKey) -> Bool {
        let ra = rank(a.type), rb = rank(b.type)
        if ra != rb { return ra < rb }
        return a.name < b.name
    }

    private static func rank(_ type: String) -> Int {
        if type == SyncSchema.metaType { return -1 }
        return SyncSchema.types.firstIndex { $0.name == type } ?? Int.max
    }
}
