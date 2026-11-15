import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 146 (`sync-review`, round 28 wave 2): findings of an independent review of the engine, shown on the app's own
/// parts against an in-memory SwiftData container (`SwiftDataSyncStore`, `SyncLedgerStore`, the task editor). A test
/// here shows a bug: its failing assertion is wrapped in a strict `XCTExpectFailure` naming the finding, so the suite
/// stays green today and turns red the day the bug is fixed (then take the wrapper off and keep the test). The
/// findings, with the sequence, the lines and what to do, are in the notes folder (`146-sync-review/FINDINGS.md`).
@MainActor
final class SyncReviewFindingsTests: XCTestCase {
    private var container: ModelContainer!
    private var main: ModelContext!
    private var store: SwiftDataSyncStore!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        main = container.mainContext
        store = SwiftDataSyncStore(container: container)
    }

    override func tearDown() async throws {
        store = nil
        main = nil
        container = nil
    }

    private func key(_ task: TaskItem) -> SyncKey { SyncKey(type: "TaskItem", name: task.id.uuidString) }

    private func record(_ key: SyncKey) async throws -> SyncRecord {
        let found = try await store.records([key])
        return try XCTUnwrap(found.first)
    }

    // MARK: Finding 1 (the store's side): a deletion takes rows no write named

    /// The brain writes one deletion, of P, with P's `expected`. SwiftData's cascade also deletes P's sub-task C,
    /// which no write named and whose `expected` was never checked (it may be new, or changed after P's deletion
    /// elsewhere). `apply` neither refuses nor reports it.
    func testFinding1_aDeletionTakesASubtaskNoWriteNamed() async throws {
        let parent = TaskItem(title: "Plan the trip")
        let child = TaskItem(title: "Book the ferry")
        main.insert(parent)
        main.insert(child)
        child.parent = parent
        try main.save()
        let parentKey = key(parent), childKey = key(child)
        let expected = try await record(parentKey)

        let stale = try await store.apply([LocalWrite(key: parentKey, expected: expected, record: nil)])
        let childLeft = try await store.records([childKey])

        XCTExpectFailure("Finding 1: apply deletes a sub-task that no LocalWrite named (the cascade)", strict: true) {
            XCTAssertTrue(stale.contains(parentKey) || !childLeft.isEmpty,
                          "either the parent comes back stale for the brain to decide again, or the sub-task stays")
        }
    }

    // MARK: Finding 5: an open editor writes its old notes over another device's edit

    /// The editor is open on a task; the engine writes another device's notes into the main context; the person
    /// changes only the title and confirms. The draft's notes (as they were at opening) are saved over the new ones,
    /// with a fresh `updatedAt`, so they win on every device.
    func testFinding5_anOpenEditorWritesItsOldNotesOverAnotherDevicesEdit() async throws {
        let task = TaskItem(title: "Trip", notes: "Ferry at nine")
        main.insert(task)
        try main.save()
        var draft = TaskEditorDraft(task: task)

        let before = try await record(key(task))
        var after = before
        after["notes"] = .string("Ferry moved to ten (typed on the Mac)")
        after["updatedAt"] = .date(Date().addingTimeInterval(5))
        let stale = try await store.apply([LocalWrite(key: key(task), expected: before, record: after)])
        XCTAssertTrue(stale.isEmpty, "setup: the engine's write landed")
        XCTAssertEqual(task.notes, "Ferry moved to ten (typed on the Mac)", "setup: the main context shows it")

        draft.title = "Trip to Oslo"
        try draft.commit(to: task, in: main)

        XCTAssertEqual(task.title, "Trip to Oslo", "the person's typing is saved")
        let notes = task.notes
        XCTExpectFailure("Finding 5: TaskEditorDraft saves the notes it opened with over a newer value it never showed", strict: true) {
            XCTAssertEqual(notes, "Ferry moved to ten (typed on the Mac)", "notes the person never touched keep the other device's edit")
        }
    }

    // MARK: Finding 6: one entry the ledger cannot decode stops the engine for good

    /// A ledger written by a newer build holds a value this build does not know (here a `SyncValue` case `double`).
    /// The ledger is meant to be disposable (`dev/SYNC-ENGINE.md` section 7), but the brain holds `failed` at every
    /// start and never forgets it.
    func testFinding6_aLedgerEntryThisBuildCannotReadHoldsTheEngineAtEveryStart() async throws {
        let ledger = SyncLedgerStore.inMemory()
        let context = ModelContext(ledger.container)
        let name = UUID().uuidString
        let newer = """
        {"key":{"type":"TaskItem","name":"\(name)"},"base":{"key":{"type":"TaskItem","name":"\(name)"},\
        "fields":{"title":{"string":{"_0":"Milk"}},"estimate":{"double":{"_0":1.5}}}}}
        """
        context.insert(LedgerEntryRow(key: "TaskItem/\(name)", payload: Data(newer.utf8)))
        try context.save()

        let cloud = FakeCloud()
        let transport = FakeTransport(cloud: cloud, device: "s146", state: ledger)
        let core = SyncCore(store: store, ledger: ledger, transport: transport, host: nil)
        await core.start()
        await core.resume()
        await core.start()
        let hold = await core.status.hold

        XCTExpectFailure("Finding 6: a ledger entry that does not decode holds the engine as failed for good", strict: true) {
            XCTAssertNil(hold, "an unreadable memory is forgotten and merged afresh (section 7), not held for ever")
        }
    }
}
