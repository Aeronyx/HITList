import Foundation
import XCTest
@testable import HITListCore

/// Brief 146 (`sync-review`, round 28 wave 2): findings of an independent review of the engine, each shown by a test
/// on the brain's own parts (`MemoryLocalStore`, `MemoryLedger`, `FakeCloud`). A test here shows a bug: its failing
/// assertion is wrapped in a strict `XCTExpectFailure` naming the finding, so the suite stays green today and turns red
/// the day the bug is fixed (then take the wrapper off and keep the test). The findings themselves, with the sequence,
/// the lines and what to do, are in the notes folder (`146-sync-review/FINDINGS.md`, `REVIEW.md`).
final class SyncReviewFindingsTests: XCTestCase {

    // MARK: Finding 1: a sub-task made or moved under a task deleted elsewhere goes with it

    /// Device B adds a sub-task under P after device A deleted P. When B fetches the deletion, the store's cascade
    /// takes the new sub-task, which nobody deleted and which iCloud never held: it is gone without a trace.
    func testFinding1_aSubtaskMadeUnderATaskDeletedElsewhereIsLost() async throws {
        let cloud = FakeCloud()
        let clock = SimClock()
        let a = await Phone("A", cloud, clock, [Self.project("H", at: clock), Self.task("P", "Plan the trip", at: clock)])
        let b = await Phone("B", cloud, clock, [])
        try await a.sync()
        try await b.sync()
        let pOnB = await b.store.record(Self.taskKey("P"))
        XCTAssertNotNil(pOnB, "setup: both devices hold P")

        clock.advance(milliseconds: 60_000)
        await a.store.delete(Self.taskKey("P"))
        await a.core.localChanged(nil)
        try await a.sync()

        // A minute after A's deletion, on B (which has not fetched it yet): a sub-task under P.
        clock.advance(milliseconds: 60_000)
        await b.store.put(Self.task("C", "Book the ferry", parent: "P", at: clock))
        await b.core.localChanged(nil)
        try await b.sync()
        try await a.sync()
        try await b.sync()

        let onB = await b.store.record(Self.taskKey("C"))
        let inCloud = await cloud.record(Self.taskKey("C"))
        XCTExpectFailure("Finding 1: the store's cascade deletes a sub-task made after its parent was deleted elsewhere", strict: true) {
            XCTAssertNotNil(onB, "the sub-task B made after A's deletion is still on B")
            XCTAssertNotNil(inCloud, "and reached iCloud")
        }
    }

    /// Device B moves an existing task under P after device A deleted P. B's fetch of the deletion cascades it, the
    /// next compare reads it as deleted here, and its marker deletes it on A too: a task neither person deleted.
    func testFinding1_aTaskMovedUnderATaskDeletedElsewhereIsDeletedEverywhere() async throws {
        let cloud = FakeCloud()
        let clock = SimClock()
        let a = await Phone("A", cloud, clock, [
            Self.project("H", at: clock), Self.task("P", "Plan the trip", at: clock), Self.task("C", "Book the ferry", at: clock),
        ])
        let b = await Phone("B", cloud, clock, [])
        try await a.sync()
        try await b.sync()
        let cOnB = await b.store.record(Self.taskKey("C"))
        XCTAssertNotNil(cOnB, "setup: both devices hold C")

        clock.advance(milliseconds: 60_000)
        await a.store.delete(Self.taskKey("P"))
        await a.core.localChanged(nil)
        try await a.sync()

        clock.advance(milliseconds: 60_000)
        await b.store.edit(Self.taskKey("C"), ["parent": .reference("P"), "updatedAt": .millis(clock.millis)])
        await b.core.localChanged(nil)
        try await b.sync()
        try await a.sync()
        try await b.sync()

        let onA = await a.store.record(Self.taskKey("C"))
        let onB = await b.store.record(Self.taskKey("C"))
        XCTExpectFailure("Finding 1: a task moved under a parent deleted elsewhere is deleted on every device", strict: true) {
            XCTAssertNotNil(onA, "A never deleted C")
            XCTAssertNotNil(onB, "B moved C after A's deletion: a change after a deletion wins (M8/M9)")
        }
    }

    // MARK: Finding 2: the mass-deletion guard walked round by one item

    /// A device that synced 30 items relaunches on a store that reads empty by mistake (the app's in-memory fallback)
    /// in which the person has typed one task. The guard tests "nothing here", so one item walks round it; 31 gone is
    /// under its floor of 50, so every item is deleted in iCloud and on every device.
    func testFinding2_aStoreThatReadsEmptyButForOneNewItemDeletesEverything() async throws {
        let cloud = FakeCloud()
        let clock = SimClock()
        let ledger = MemoryLedger()
        var items = [Self.project("H", at: clock)]
        for i in 0..<30 { items.append(Self.task("T\(i)", "Task \(i)", at: clock)) }
        let first = await Phone("A", cloud, clock, items, ledger: ledger)
        try await first.sync()
        await first.core.stop()
        let aliveBefore = await Self.alive(cloud)
        XCTAssertEqual(aliveBefore, 31, "setup: iCloud holds every item")

        clock.advance(milliseconds: 60_000)
        let fallback = MemoryLocalStore([Self.task("N", "Typed into the empty-looking app", at: clock)])
        let again = await Phone("A", cloud, clock, store: fallback, ledger: ledger)
        let hold = await again.core.status.hold
        try? await again.sync()
        let aliveAfter = await Self.alive(cloud)

        XCTExpectFailure("Finding 2: the mass-deletion guard only fires on a store with exactly nothing in it", strict: true) {
            if case .massDeletion? = hold {} else { XCTFail("held for a mass deletion; got \(String(describing: hold))") }
            XCTAssertGreaterThanOrEqual(aliveAfter, 31, "nothing deleted in iCloud before the person confirms")
        }
    }

    // MARK: The parts

    /// One device: its store, its ledger, a transport on the shared pretend iCloud, and a brain, started.
    struct Phone {
        let store: MemoryLocalStore
        let ledger: MemoryLedger
        let transport: FakeTransport
        let core: SyncCore

        init(_ name: String, _ cloud: FakeCloud, _ clock: SimClock, _ records: [SyncRecord] = [],
             ledger: MemoryLedger = MemoryLedger()) async {
            await self.init(name, cloud, clock, store: MemoryLocalStore(records), ledger: ledger)
        }

        init(_ name: String, _ cloud: FakeCloud, _ clock: SimClock, store: MemoryLocalStore, ledger: MemoryLedger) async {
            self.store = store
            self.ledger = ledger
            transport = FakeTransport(cloud: cloud, device: name, state: ledger)
            core = SyncCore(store: store, ledger: ledger, transport: transport, host: nil, clock: clock.function)
            await core.start()
        }

        /// A fetch then a send, twice (what the first send settles is sent by the second), unless held.
        func sync() async throws {
            for _ in 0..<2 {
                if await core.status.hold != nil { return }
                try await core.syncNow()
            }
        }
    }

    static func taskKey(_ name: String) -> SyncKey { SyncKey(type: "TaskItem", name: name) }

    static func task(_ name: String, _ title: String, parent: String? = nil, at clock: SimClock) -> SyncRecord {
        var record = SyncRecord(type: "TaskItem", name: name, fields: [
            "title": .string(title), "createdAt": .millis(clock.millis), "updatedAt": .millis(clock.millis),
        ])
        if let parent { record["parent"] = .reference(parent) }
        return record
    }

    static func project(_ name: String, at clock: SimClock) -> SyncRecord {
        SyncRecord(type: "Project", name: name, fields: [
            "name": .string("Home"), "createdAt": .millis(clock.millis), "updatedAt": .millis(clock.millis),
        ])
    }

    /// Items iCloud holds alive (not markers, not the zone's meta).
    static func alive(_ cloud: FakeCloud) async -> Int {
        await cloud.records().filter { SyncSchema.type($0.key.type) != nil && !$0.record.isDeleted }.count
    }
}
