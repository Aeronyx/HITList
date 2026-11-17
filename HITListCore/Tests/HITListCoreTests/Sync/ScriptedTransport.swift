import Foundation
import XCTest
@testable import HITListCore

/// A transport driven by hand, for `SyncCore`'s tests: it keeps the list as T3 says, delivers whatever events a test
/// hands it (one at a time, T1), and answers a send the way the test says (by default: iCloud accepts everything,
/// with a new token each time). It is not a pretend iCloud (that is `FakeCloud`, session 140's): it holds no records.
actor ScriptedTransport: SyncTransport {
    private(set) var delegate: (any SyncTransportDelegate)?
    private(set) var list: [PendingChange] = []
    private(set) var resets = 0
    private(set) var starts = 0
    /// Every record a send asked for and sent, in order.
    private(set) var sentRecords: [OutgoingRecord] = []
    /// "fetch" and "send", in the order they were called.
    private(set) var calls: [String] = []
    /// Events delivered as the first thing after `start` (an account that changed while the app was not running).
    var startEvents: [TransportEvent] = []
    /// What each `fetch()` delivers, one list per call; an empty fetch when none is left.
    var fetches: [[TransportEvent]] = []
    var fetchThrows: Error?
    /// How a send is answered: the records asked for and the deletes, to the `sent` events. Nil: accept everything.
    var answer: (@Sendable ([OutgoingRecord], [SyncKey]) -> [TransportEvent])?
    private var tokens = 0

    func start(delegate: any SyncTransportDelegate) async {
        self.delegate = delegate
        starts += 1
        for event in startEvents { await deliver(event) }
    }

    func stop() async { delegate = nil }

    func pending() async -> [PendingChange] { list }

    func add(_ changes: [PendingChange]) async {
        var listed = Set(list.map(\.key))
        for change in changes {
            guard listed.contains(change.key) else {
                list.append(change)
                listed.insert(change.key)
                continue
            }
            if let index = list.firstIndex(where: { $0.key == change.key }) {
                if list[index] == change { continue }
                list.remove(at: index)
            }
            list.append(change)
        }
    }

    func remove(_ changes: [PendingChange]) async {
        list.removeAll { changes.contains($0) }
    }

    func fetch() async throws {
        if delivering > 0 { XCTFail("T1: fetch() called while an event was being handled") }
        calls.append("fetch")
        if let fetchThrows { throw fetchThrows }
        let events = fetches.isEmpty ? [.willFetch, .didFetch(error: nil)] : fetches.removeFirst()
        for event in events { await deliver(event) }
    }

    func send() async throws {
        if delivering > 0 { XCTFail("T1: send() called while an event was being handled") }
        calls.append("send")
        guard let delegate else { return }
        var records: [OutgoingRecord] = []
        var deletes: [SyncKey] = []
        for change in list {
            switch change {
            case .save(let key):
                if let record = await delegate.recordToSend(key) {
                    records.append(record)
                } else {
                    list.removeAll { $0 == change }
                }
            case .delete(let key):
                deletes.append(key)
            }
        }
        sentRecords += records
        let events = answer?(records, deletes) ?? [accept(records, deletes)]
        await deliver(.willSend)
        for event in events { await deliver(event) }
        await deliver(.didSend(error: nil))
    }

    func reset() async {
        list = []
        resets += 1
    }

    /// Hands the brain one event. Like the real transports, the changes a `sent` answers for leave the list first.
    func deliver(_ event: TransportEvent) async {
        if case .sent(let saved, let removed, let failed) = event {
            let answered = Set(saved.map { PendingChange.save($0.key) } + removed.map { .delete($0) })
            list.removeAll { answered.contains($0) || failed[$0.key] != nil }
        }
        // T1: one event at a time.
        if delivering > 0 { XCTFail("T1: an event delivered while another was being handled") }
        delivering += 1
        await delegate?.handle(event)
        delivering -= 1
    }

    /// Events being handled right now (T1: never more than one; `fetch`/`send` never from inside one).
    private var delivering = 0

    func setFetches(_ fetches: [[TransportEvent]]) { self.fetches = fetches }
    func setAnswer(_ answer: (@Sendable ([OutgoingRecord], [SyncKey]) -> [TransportEvent])?) { self.answer = answer }
    func setStartEvents(_ events: [TransportEvent]) { startEvents = events }
    func setFetchThrows(_ error: Error?) { fetchThrows = error }
    func forgetList() { list = [] }

    /// iCloud accepting everything: each record saved as sent, with a new token.
    func accept(_ records: [OutgoingRecord], _ deletes: [SyncKey]) -> TransportEvent {
        let saved = records.map { record -> CloudRecord in
            tokens += 1
            return CloudRecord(record: record.record, system: Data("sent-\(tokens)".utf8))
        }
        return .sent(saved: saved, removed: deletes, failed: [:])
    }
}

// MARK: - Test helpers

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

/// A host that writes down what it hears.
final class TestHost: SyncHost, @unchecked Sendable {
    private let lock = NSLock()
    private var _written: [Set<SyncKey>] = []
    private var _accepted: [Set<SyncKey>] = []
    private var _statuses: [SyncStatus] = []
    private var _backups: [SyncRemovalReason] = []
    var backupError: Error?

    struct BackupFailed: Error {}

    private var _switches: [String] = []

    func willRemoveLocalData(reason: SyncRemovalReason) async throws {
        lock.withLock { _backups.append(reason) }
        if let backupError { throw backupError }
    }

    /// Brief 160: an account switch's backup names both accounts (the host sets the previous one's backups aside).
    func willRemoveLocalData(reason: SyncRemovalReason, switchingFrom previous: String?, to current: String?) async throws {
        lock.withLock { _switches.append("\(reason.rawValue) \(previous ?? "-") → \(current ?? "-")") }
        try await willRemoveLocalData(reason: reason)
    }

    var switches: [String] { lock.withLock { _switches } }
    func didWrite(_ keys: Set<SyncKey>) { lock.withLock { _written.append(keys) } }
    func didAccept(_ keys: Set<SyncKey>) { lock.withLock { _accepted.append(keys) } }
    func statusDidChange(_ status: SyncStatus) { lock.withLock { _statuses.append(status) } }

    var written: Set<SyncKey> { lock.withLock { _written.reduce(into: Set()) { $0.formUnion($1) } } }
    var accepted: Set<SyncKey> { lock.withLock { _accepted.reduce(into: Set()) { $0.formUnion($1) } } }
    var statuses: [SyncStatus] { lock.withLock { _statuses } }
    var backups: [SyncRemovalReason] { lock.withLock { _backups } }
}

/// A log the test can read.
final class TestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    func write(_ line: String) { lock.withLock { _lines.append(line) } }
    var lines: [String] { lock.withLock { _lines } }
}

/// One device: its items, its ledger, a scripted transport and the brain on them.
struct Device {
    let store: MemoryLocalStore
    let ledger: MemoryLedger
    let transport: ScriptedTransport
    let host = TestHost()
    let clock: TestClock
    let log = TestLog()
    let core: SyncCore

    init(_ records: [SyncRecord] = [], store: MemoryLocalStore? = nil, ledger: MemoryLedger? = nil,
         transport: ScriptedTransport? = nil, clock: TestClock = TestClock()) {
        self.store = store ?? MemoryLocalStore(records)
        self.ledger = ledger ?? MemoryLedger()
        self.transport = transport ?? ScriptedTransport()
        self.clock = clock
        let log = self.log
        core = SyncCore(store: self.store, ledger: self.ledger, transport: self.transport, host: host,
                        clock: { clock.now }, log: { log.write($0) })
    }

    /// The same device after its process was thrown away: a new brain on the same items, ledger and transport.
    func relaunched(transport: ScriptedTransport? = nil) -> Device {
        Device(store: store, ledger: ledger, transport: transport ?? self.transport, clock: clock)
    }

    /// Started, with a first whole fetch of `records` behind it.
    func started(fetching records: [CloudRecord] = []) async -> Device {
        await core.start()
        await deliverFetch(records)
        return self
    }

    func deliverFetch(_ records: [CloudRecord], removed: [SyncKey] = []) async {
        await transport.deliver(.willFetch)
        await transport.deliver(.fetched(changed: records, removed: removed))
        await transport.deliver(.didFetch(error: nil))
    }

    func status() async -> SyncStatus { await core.status }
    func pending() async -> [PendingChange] { await transport.pending() }
    func entry(_ key: SyncKey) async -> LedgerEntry? { await ledger.entry(key) }
    func item(_ key: SyncKey) async -> SyncRecord? { await store.record(key) }
}

// MARK: - Records

let epoch = Date(timeIntervalSince1970: 1_800_000_000)

func at(_ seconds: TimeInterval) -> SyncValue { .date(epoch.addingTimeInterval(seconds)) }

func taskKey(_ name: String) -> SyncKey { SyncKey(type: "TaskItem", name: name) }
func projectKey(_ name: String) -> SyncKey { SyncKey(type: "Project", name: name) }
func labelKey(_ name: String) -> SyncKey { SyncKey(type: "TaskLabel", name: name) }

func task(_ name: String, _ title: String, updated: TimeInterval = 0, project: String? = nil, parent: String? = nil,
          labels: [String] = []) -> SyncRecord {
    var fields: [String: SyncValue] = ["title": .string(title), "updatedAt": at(updated), "createdAt": at(0)]
    if let project { fields["project"] = .reference(project) }
    if let parent { fields["parent"] = .reference(parent) }
    if !labels.isEmpty { fields["labels"] = .references(labels) }
    return SyncSchema.filled(SyncRecord(type: "TaskItem", name: name, fields: fields))
}

func project(_ name: String, _ title: String, updated: TimeInterval = 0) -> SyncRecord {
    SyncSchema.filled(SyncRecord(type: "Project", name: name,
                                 fields: ["name": .string(title), "updatedAt": at(updated), "createdAt": at(0)]))
}

func label(_ name: String, _ title: String) -> SyncRecord {
    SyncSchema.filled(SyncRecord(type: "TaskLabel", name: name,
                                 fields: ["name": .string(title), "updatedAt": at(0), "createdAt": at(0)]))
}

func cloud(_ record: SyncRecord, _ token: String = "c1") -> CloudRecord {
    CloudRecord(record: record, system: Data(token.utf8))
}

func meta(_ version: Int = SyncSchema.formatVersion, _ token: String = "m1") -> CloudRecord {
    CloudRecord(record: SyncRecord(key: SyncCore.metaKey, fields: [SyncSchema.metaFormatVersion: .int(Int64(version))]),
                system: Data(token.utf8))
}

func token(_ string: String) -> Data { Data(string.utf8) }

extension XCTestCase {
    /// Waits, without sleeping, until `condition` holds: the test yields its turn until the brain gets there.
    func until(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<10_000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("condition never held", file: file, line: line)
    }
}
