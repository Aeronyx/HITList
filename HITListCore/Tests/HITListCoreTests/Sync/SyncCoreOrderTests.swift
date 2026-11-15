import Foundation
import XCTest
@testable import HITListCore

/// The order of things: one operation at a time, the device written before the ledger and the ledger before the
/// return from `handle` (proved both ways), a crash between any two of them, and the brain at the size of a big list.
final class SyncCoreOrderTests: XCTestCase {
    func synced(_ records: [SyncRecord], store: MemoryLocalStore? = nil) async -> Device {
        await Device(records, store: store).started(fetching: records.map { cloud($0) } + [meta()])
    }

    // MARK: One thing at a time

    func testALocalChangeThatArrivesWhileABatchIsBeingWrittenIsDoneAfterItOnTheStateItLeft() async {
        // A project stays: a real store is never empty (and an empty one is held as a mass deletion).
        let memory = MemoryLocalStore([task("A", "Milk"), project("P", "Home")])
        let gated = GatedStore(memory)
        let ledger = MemoryLedger()
        let transport = ScriptedTransport()
        // The person's deletion comes after iCloud's edit (epoch + 30 s), so the deletion stands (M8).
        let clock = TestClock(epoch.addingTimeInterval(1_000))
        let core = SyncCore(store: gated, ledger: ledger, transport: transport, host: nil, clock: { clock.now })
        await core.start()
        await transport.deliver(.willFetch)
        await transport.deliver(.fetched(changed: [cloud(task("A", "Milk")), cloud(project("P", "Home")), meta()],
                                         removed: []))
        await transport.deliver(.didFetch(error: nil))

        await gated.arm()
        let batch = Task { await transport.deliver(.fetched(changed: [cloud(task("A", "Oat milk", updated: 30), "c2")],
                                                            removed: [])) }
        await until { await gated.inside }
        // The person deletes A while the batch is half written; the app says so.
        await memory.delete(taskKey("A"))
        let local = Task { await core.localChanged(nil) }
        await until { await core.queuedOperations == 1 }
        let early = await gated.log
        XCTAssertEqual(early.last, "apply begins", "the compare has not read anything yet")

        await gated.open()
        await batch.value
        await local.value
        let log = await gated.log
        let ends = log.firstIndex(of: "apply ends") ?? .max
        let compare = log.lastIndex(of: "read all") ?? -1
        XCTAssertGreaterThan(compare, ends, "the compare ran after the batch")
        // The batch was settled against the A it read; the compare then found it deleted, on the batch's base.
        let entry = await ledger.entry(taskKey("A"))
        XCTAssertEqual(entry?.system, token("c2"))
        XCTAssertNotNil(entry?.deletedHereAt)
        let pending = await transport.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
        let record = await core.recordToSend(taskKey("A"))
        XCTAssertEqual(record?.record.isDeleted, true)
        XCTAssertEqual(record?.system, token("c2"), "the marker goes against the version the batch brought")
    }

    // MARK: The device first, then the ledger, then the return (both halves)

    /// A crash after the device was written and before the ledger: the item differs from its base, so it goes with
    /// the old token; iCloud answers with a conflict; the merge finds the two the same. Nothing is lost.
    func testACrashAfterTheDeviceAndBeforeTheLedgerSettlesThroughAConflict() async throws {
        let store = MemoryLocalStore([task("A", "Milk")])
        let dying = DyingLedger()
        // In step first, on a ledger that will die mid-event.
        let t = ScriptedTransport()
        let core = SyncCore(store: store, ledger: dying, transport: t, host: nil)
        await core.start()
        await t.deliver(.willFetch)
        await t.deliver(.fetched(changed: [cloud(task("A", "Milk")), meta()], removed: []))
        await t.deliver(.didFetch(error: nil))

        await dying.dieAtNextWrite()
        await t.deliver(.fetched(changed: [cloud(task("A", "Oat milk", updated: 30), "c2")], removed: []))
        let written = await store.record(taskKey("A"))
        XCTAssertEqual(written?["title"], .string("Oat milk"), "the device was written")
        let base = await dying.inner.entry(taskKey("A"))
        XCTAssertEqual(base?.system, token("c1"), "the ledger was not: the process died in between")

        // The process again, on the same items and ledger. The transport never saw `handle` return.
        let relaunched = Device(store: store, ledger: dying.inner, transport: ScriptedTransport())
        await relaunched.core.start()
        let pending = await relaunched.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))], "the item differs from its base: a change to send")
        let outgoing = await relaunched.core.recordToSend(taskKey("A"))
        XCTAssertEqual(outgoing?.system, token("c1"), "with the OLD token, which iCloud refuses (T6)")
        let server = cloud(task("A", "Oat milk", updated: 30), "c2")
        await relaunched.transport.setAnswer { _, _ in
            [.sent(saved: [], removed: [], failed: [taskKey("A"): .conflict(server: server)])]
        }
        try await relaunched.transport.send()
        let settled = await relaunched.entry(taskKey("A"))
        XCTAssertEqual(settled?.system, token("c2"))
        let none = await relaunched.pending()
        XCTAssertEqual(none, [], "the merge found the two the same")
        let item = await store.record(taskKey("A"))
        XCTAssertEqual(item?["title"], .string("Oat milk"))
        let status = await relaunched.status()
        XCTAssertTrue(status.isSynced)

        // The event coming again instead (the bookmark never moved) changes nothing either.
        let applies = await store.applyCount
        await relaunched.deliverFetch([server])
        let after = await store.applyCount
        XCTAssertEqual(after, applies)
    }

    /// The other order is the one that loses: a base that says the device holds iCloud's new version while the
    /// device holds the old one sends the old value with the new token, which iCloud accepts. The brain never
    /// leaves that state: a device write that fails leaves the ledger as it was.
    func testTheOtherOrderWouldSendAnOldValueOverANewOneAndTheBrainNeverLeavesIt() async throws {
        // The state "the ledger first, then a crash before the device" would leave.
        let wrong = await synced([task("A", "Milk")])
        var write = LedgerWrite()
        write.upsert = [LedgerEntry(key: taskKey("A"), base: task("A", "Oat milk", updated: 30).comparable,
                                    system: token("c2"))]
        try await wrong.ledger.write(write)
        let relaunched = wrong.relaunched(transport: ScriptedTransport())
        await relaunched.core.start()
        let outgoing = await relaunched.core.recordToSend(taskKey("A"))
        XCTAssertEqual(outgoing?.record["title"], .string("Milk"), "the old value…")
        XCTAssertEqual(outgoing?.system, token("c2"), "…with the current token: iCloud would take it")

        // The brain's order: the device write fails, and the ledger is untouched.
        let failing = FailingStore(MemoryLocalStore([task("A", "Milk")]))
        let ledger = MemoryLedger()
        let transport = ScriptedTransport()
        let core = SyncCore(store: failing, ledger: ledger, transport: transport, host: nil)
        await core.start()
        await transport.deliver(.willFetch)
        await transport.deliver(.fetched(changed: [cloud(task("A", "Milk")), meta()], removed: []))
        await transport.deliver(.didFetch(error: nil))
        await failing.failWrites()
        await transport.deliver(.fetched(changed: [cloud(task("A", "Oat milk", updated: 30), "c2")], removed: []))
        let entry = await ledger.entry(taskKey("A"))
        XCTAssertEqual(entry?.system, token("c1"), "no base moved ahead of the device")
        let status = await core.status
        guard case .held(.failed)? = Optional(status.state) else { return XCTFail("\(status.state)") }
    }

    /// A crash after the ledger and before the transport moved its bookmark: the event comes again, and changes
    /// nothing.
    func testACrashAfterTheLedgerAndBeforeTheBookmarkBringsTheEventAgainAndChangesNothing() async {
        let device = await synced([task("A", "Milk")])
        let batch: [CloudRecord] = [cloud(task("A", "Oat milk", updated: 30), "c2"),
                                    cloud(task("C", "Child", parent: "P"), "c3"), cloud(task("P", "Parent"), "c4")]
        await device.transport.deliver(.fetched(changed: batch, removed: []))
        let entries = try? await device.ledger.entries()
        let applies = await device.store.applyCount

        let relaunched = device.relaunched(transport: ScriptedTransport())
        await relaunched.core.start()
        await relaunched.transport.deliver(.fetched(changed: batch, removed: []))
        await relaunched.transport.deliver(.didFetch(error: nil))
        let after = try? await relaunched.ledger.entries()
        XCTAssertEqual(after, entries)
        let applied = await relaunched.store.applyCount
        XCTAssertEqual(applied, applies)
        let pending = await relaunched.pending()
        XCTAssertEqual(pending, [])
    }

    func testRecordsSetAsideSurviveACrashAndAreSettledWhenTheFetchEnds() async {
        let device = await synced([])
        await device.transport.deliver(.willFetch)
        await device.transport.deliver(.fetched(changed: [cloud(task("C", "Child", parent: "P"))], removed: []))
        let relaunched = device.relaunched(transport: ScriptedTransport())
        await relaunched.core.start()
        let early = await relaunched.item(taskKey("C"))
        XCTAssertNil(early, "still set aside: the fetch has not ended")
        await relaunched.transport.deliver(.willFetch)
        await relaunched.transport.deliver(.fetched(changed: [cloud(task("P", "Parent"))], removed: []))
        await relaunched.transport.deliver(.didFetch(error: nil))
        let c = await relaunched.item(taskKey("C"))
        XCTAssertEqual(c?["parent"], .reference("P"))
        let pending = await relaunched.pending()
        XCTAssertEqual(pending, [])
    }

    // MARK: A big list

    func testFiveThousandRecords() async throws {
        let count = 5_000
        var records: [SyncRecord] = [project("P", "Home")]
        for index in 0..<count { records.append(task(String(format: "T%05d", index), "Task \(index)", project: "P")) }
        let device = Device(records)
        await device.core.start()

        var clock = ContinuousClock.now
        await device.deliverFetch(records.map { cloud($0) } + [meta()])
        let fetchTime = ContinuousClock.now - clock
        let none = await device.pending()
        XCTAssertEqual(none, [])

        for index in stride(from: 0, to: count, by: 100) {
            await device.store.edit(taskKey(String(format: "T%05d", index)), ["notes": .string("changed")])
        }
        clock = ContinuousClock.now
        await device.core.localChanged(nil)
        let compareTime = ContinuousClock.now - clock
        let pending = await device.pending()
        XCTAssertEqual(pending.count, count / 100)
        let waiting = await device.status().waiting
        XCTAssertEqual(waiting, count / 100)

        // Everything new to iCloud at once (a first device moving over).
        let fresh = Device(records)
        await fresh.core.start()
        clock = ContinuousClock.now
        await fresh.deliverFetch([])
        let allNewTime = ContinuousClock.now - clock
        let all = await fresh.pending()
        XCTAssertEqual(all.count, count + 2, "every item, the project and the meta")
        print("SyncCore at \(count) records: a whole fetch settled in \(fetchTime), a whole compare in \(compareTime), " +
              "\(count + 1) new items listed in \(allNewTime)")
        XCTAssertLessThan(compareTime, .seconds(5))
    }
}

/// A store whose next `apply` waits until the test opens it, and that writes down what was asked of it.
actor GatedStore: SyncLocalStore {
    let inner: MemoryLocalStore
    private(set) var log: [String] = []
    private(set) var inside = false
    private var armed = false
    private var gate: CheckedContinuation<Void, Never>?

    init(_ inner: MemoryLocalStore) { self.inner = inner }

    func arm() { armed = true }

    func open() {
        gate?.resume()
        gate = nil
    }

    func records() async throws -> [SyncRecord] {
        log.append("read all")
        return try await inner.records()
    }

    func records(_ keys: Set<SyncKey>) async throws -> [SyncRecord] {
        log.append("read some")
        return try await inner.records(keys)
    }

    func apply(_ writes: [LocalWrite]) async throws -> Set<SyncKey> {
        if armed {
            armed = false
            log.append("apply begins")
            inside = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in gate = continuation }
            let stale = try await inner.apply(writes)
            log.append("apply ends")
            return stale
        }
        return try await inner.apply(writes)
    }
}

/// A store whose writes throw once told to.
actor FailingStore: SyncLocalStore {
    struct WriteFailed: Error {}
    let inner: MemoryLocalStore
    private var failing = false
    init(_ inner: MemoryLocalStore) { self.inner = inner }
    func failWrites() { failing = true }
    func records() async throws -> [SyncRecord] { try await inner.records() }
    func records(_ keys: Set<SyncKey>) async throws -> [SyncRecord] { try await inner.records(keys) }
    func apply(_ writes: [LocalWrite]) async throws -> Set<SyncKey> {
        if failing { throw WriteFailed() }
        return try await inner.apply(writes)
    }
}

/// A ledger whose process dies at a write: that write and every one after it throw, as nothing more reaches the
/// disk. `inner` is what the disk holds, for the relaunch.
actor DyingLedger: SyncLedger {
    struct Dead: Error {}
    let inner = MemoryLedger()
    private var dead = false
    private var dying = false

    func dieAtNextWrite() { dying = true }

    func entries() async throws -> [LedgerEntry] { try await inner.entries() }
    func deferred() async throws -> [CloudRecord] { try await inner.deferred() }
    func fact(_ name: String) async throws -> Data? { try await inner.fact(name) }
    func write(_ write: LedgerWrite) async throws {
        if dying { dead = true }
        if dead { throw Dead() }
        try await inner.write(write)
    }
    func reset() async throws {
        if dead { throw Dead() }
        try await inner.reset()
    }
    func loadTransportState() async -> Data? { await inner.loadTransportState() }
    func saveTransportState(_ state: Data?) async {
        if !dead { await inner.saveTransportState(state) }
    }
}
