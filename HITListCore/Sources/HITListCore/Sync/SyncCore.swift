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
    /// What records wait for (the ledger's `deferred` list, section 8): by record, the reference fields it waits for.
    var waits: [SyncKey: CloudRecord] = [:]
    var firstFetchDone = false
    var account: String?
    var hold: SyncHold?
    /// Fetched records were let go unread (a hold, a write that failed): the transport must bring everything again
    /// before the brain trusts its memory. Kept as a fact too, so a relaunch does it.
    var refetch = false
    /// The account a switch is to join once the previous account's items could be backed up and removed (a backup
    /// that failed). Kept as a fact.
    var switchTo: String?
    /// The hold a failure (`failed`, `duplicates`) fell on, which comes back when the failure lifts.
    var heldUnder: SyncHold?
    /// A sign-in whose ledger write failed: joined on `resume()` (the transport will not say it twice).
    var joinTo: String?
    /// What this device last sent for a record while no answer has come (`SyncCore+Sent`): kept on disk as one fact
    /// per key (`sentFact`), read whole at a start, and only valid for the memory it was written in (`sentEpoch`,
    /// moved on by every forget).
    var remembered: [SyncKey: SyncRecord] = [:]
    var sentEpoch = 0
    /// Records iCloud sent that could not be written because the person had the item changed and not saved, three
    /// tries running (`staleRounds`): kept to be settled again when a save names the item, when everything is
    /// compared, and at the end of every fetch. Their keys are kept as a fact too (`unsettledFact`), so that a launch
    /// which finds any asks for every record again: the bookmark has moved past them.
    var unsettled: [SyncKey: CloudRecord] = [:]
    /// A sign-in to the account the device was signed out of, whose whole fetch has not finished (`rejoin`). Kept as
    /// a fact: a launch that finds it asks for every record again, because the check at that fetch's end
    /// (`checkRejoin`) needs every record of one whole fetch.
    var rejoining = false
    /// The keys that whole fetch brought so far (not kept: a launch fetches everything again).
    var rejoinSeen: Set<SyncKey> = []

    // MARK: Working state, not kept

    /// An event is being handled: nothing may reset the transport now.
    var inEvent = false
    /// Items found missing (M14) for which every record was already asked for again and that have not been seen on
    /// the device since: not asked for a second time, so an item iCloud holds that this device can never write (a
    /// record a broken build made) does not have everything fetched again at every compare.
    var askedAgain: Set<SyncKey> = []
    /// Deletions noted (`noteDeletions`) whose keys no compare has looked at yet: the next one does, whatever keys
    /// it was asked for (a save's hint names the rows it knows of; the store may have written down more).
    var noted: Set<SyncKey> = []
    /// Records the transport fetched in this fetch and could not read (`TransportEvent.owed`): iCloud holds them, so
    /// the fetch is no proof that iCloud lacks these keys (brief 160, 149's "brain gap"). Cleared at each `willFetch`.
    var owedKeys: Set<SyncKey> = []

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
    /// What `recordToSend` last answered for each key (nil inside: a marker), so a refusal remembers the version
    /// iCloud refused rather than whatever the device holds by the time the answer comes.
    var sentAs: [SyncKey: SyncRecord?] = [:]
    /// The items sent for a key that has a base and had no answer since (the newest last, a few at most). A save
    /// can land while its answer is lost; when iCloud's record then turns out to be exactly one of these, that
    /// record, not the older base, is what the two last agreed on (`decide`). Cleared when a send is answered.
    var unanswered: [SyncKey: [SyncRecord]] = [:]
    static let unansweredKept = 4
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
    static let switchFact = "switchTo"
    static let epochFact = "sentEpoch"
    static let unsettledFact = "unsettled"
    static let rejoinFact = "rejoin"
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
            await compare(nil, launch: true)
            await refetchIfOwed()
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
    /// `keys` is what a save touched (the rows it made or changed, and the ones it deleted, which the store has
    /// written down: `SyncLocalStore.deletions`); nil compares everything, which only a launch and a save that could
    /// not be named need. A nil compare also tries a full iCloud, or one not ready for this build, again
    /// (`SyncHold.triedOnReturn`).
    public func localChanged(_ keys: Set<SyncKey>?) async {
        await serially {
            guard loaded else { return }
            if keys == nil, hold?.triedOnReturn == true { await lift(resetTransport: false) }
            await compare(keys)
            await settleUnsettled(keys)
            await refetchIfOwed()
            publish()
        }
    }

    /// A fetch, then a send: the person's "sync now". Throws `SyncCoreError.held` while held (a full iCloud, or one
    /// not ready for this build, is tried again first), and what the transport throws. Never call it from inside
    /// `handle`.
    public func syncNow() async throws {
        try await serially {
            guard loaded, transportStarted else { throw SyncCoreError.notStarted }
            if hold?.triedOnReturn == true {
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
    /// `storageFull`, `iCloudNotReady`, and an account switch whose backup failed (`noAccount` with the account to join
    /// remembered). Everything iCloud brought while held is fetched again. Other holds stay.
    public func resume() async {
        await serially {
            guard loaded else { return }
            switch hold {
            case .duplicates?, .failed?, .storageFull?, .iCloudNotReady?:
                log("Resumed after: \(hold?.words ?? "")")
                await lift(resetTransport: true)
            default: break
            }
            if hold == .noAccount {
                if let next = switchTo {
                    // An account switch whose backup failed: tried again.
                    await retrySwitch(to: next)
                } else if let next = joinTo {
                    // A sign-in the ledger could not take: taken again, decided afresh (back to the account it was
                    // signed out of is a rejoin, brief 165).
                    await accountChanged(.signedIn(current: next))
                }
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
            inEvent = true
            await process(event)
            inEvent = false
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
            owedKeys = []
        case .fetched(let changed, let removed):
            await fetched(changed, removed: removed)
        case .zoneLost(let reason):
            await zoneLost(reason)
        case .didFetch(let error):
            fetching = false
            await didFetch(error: error)
        case .owed(let keys):
            owedKeys = Set(keys)
            log("\(keys.count) record\(keys.count == 1 ? "" : "s") in iCloud could not be read here yet; not taken as missing from iCloud")
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
        for record in write.deferUpsert { waits[record.key] = record }
        for key in write.deferRemove { waits[key] = nil }
        for (name, value) in write.facts {
            switch name {
            case LedgerFact.account: account = value.flatMap { String(data: $0, encoding: .utf8) }
            case LedgerFact.firstFetchDone: firstFetchDone = value != nil
            case Self.refetchFact: refetch = value != nil
            case Self.switchFact: switchTo = value.map { String(decoding: $0, as: UTF8.self) }
            case Self.epochFact: sentEpoch = value.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
            case Self.rejoinFact: rejoining = value != nil
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
            let waitList = try await ledger.deferred()
            let first = try await ledger.fact(LedgerFact.firstFetchDone)
            let owner = try await ledger.fact(LedgerFact.account)
            let held = try await ledger.fact(LedgerFact.hold)
            let again = try await ledger.fact(Self.refetchFact)
            // Records set aside unwritten when the app last ran are gone with that process: everything is asked for again.
            let aside = try await ledger.fact(Self.unsettledFact)
            let next = try await ledger.fact(Self.switchFact)
            let epoch = try await ledger.fact(Self.epochFact)
            let rejoin = try await ledger.fact(Self.rejoinFact)
            sentEpoch = epoch.flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
            try await loadRememberedSends()
            unanswered = [:]
            unsettled = [:]
            entries = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
            waits = Dictionary(waitList.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
            firstFetchDone = first != nil
            account = owner.flatMap { String(data: $0, encoding: .utf8) }
            rejoining = rejoin != nil
            rejoinSeen = []
            // A sign-in's whole fetch that had not finished: every record is asked for again.
            refetch = refetch || again != nil || aside != nil || rejoining
            switchTo = next.map { String(decoding: $0, as: UTF8.self) }
            if let held {
                hold = try? JSONDecoder().decode(SyncHold.self, from: held)
                heldUnder = nil
            } else if hold?.persists == true {
                hold = nil
            }
            loaded = true
            log("Started: \(entries.count) records remembered, \(waits.count) waiting for an item" +
                (hold.map { ", held: \($0.words)" } ?? ""))
            return true
        } catch {
            phase = .off
            hold = .failed(SyncFailureWords.recordsNotRead)
            log("Not started: \(SyncFailureWords.recordsNotRead) The error: \(error)")
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
        var refusalWords = refusedKeys.first.flatMap { key in refused[key].map { "\(key): \($0.words)" } }
        if refusedKeys.count > 1, let first = refusalWords {
            refusalWords = "\(refusedKeys.count) items iCloud refused for good, the first \(first)"
        }
        return SyncStatus(state: state, waiting: waiting.count, firstFetchDone: firstFetchDone,
                          lastFetchEnded: lastFetchEnded, lastSendEnded: lastSendEnded,
                          lastError: fetchError ?? sendError ?? holdNote, refused: refusedKeys, refusal: refusalWords)
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

    /// Where a type stands in the order changes are added to the list in: those pointed at first (`SyncSchema.types`).
    static func rank(_ type: String) -> Int {
        if type == SyncSchema.metaType { return -1 }
        return SyncSchema.types.firstIndex { $0.name == type } ?? Int.max
    }
}
