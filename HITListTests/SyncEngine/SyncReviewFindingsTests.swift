import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 146 (`sync-review`, round 28 wave 2): findings of an independent review of the engine, shown on the app's own
/// parts against an in-memory SwiftData container (`SwiftDataSyncStore`, `SyncLedgerStore`, the task editor). Each
/// test showed a bug behind a strict `XCTExpectFailure`; every one here is fixed, the wrappers are off, and the tests
/// stay as guards. The findings are in the notes folder (`146-sync-review/FINDINGS.md`).
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

        // Fixed on master 6743b04 (the store deletes exactly the rows named): the wrapper is off, the test guards it.
        XCTAssertTrue(stale.contains(parentKey) || !childLeft.isEmpty,
                      "either the parent comes back stale for the brain to decide again, or the sub-task stays")
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
        // Fixed on master b17f77b (the draft saves only what the person changed): the wrapper is off.
        XCTAssertEqual(notes, "Ferry moved to ten (typed on the Mac)", "notes the person never touched keep the other device's edit")
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

        // Fixed on master b17f77b and fdd3804 (an unreadable row is forgotten alone and everything is fetched again).
        XCTAssertNil(hold, "an unreadable memory is forgotten and merged afresh (section 7), not held for ever")
    }

    // MARK: Finding 18: a change that arrives while the person has the row unsaved

    /// The person has an unsaved change on a task in the main context when another device's edit of it arrives. The
    /// write comes back stale (right: the person's edit is not saved over); the brain decides again on a fresh read,
    /// which sees only the saved row, so it can never agree with the main context, and after three rounds it sets
    /// iCloud's record aside. The finding: it was then fetched again only at the next launch, so if the person dropped
    /// the change (Discard, an undo) the other device's edit was missing here until a relaunch. Fixed 2026-11-15: the
    /// record set aside is settled again when a save names the item, and at the end of the next fetch.
    func testFinding18_anEditThatArrivesWhileARowIsUnsavedIsWrittenOnceTheTypingIsGone() async throws {
        let notes = try await anEditArriving(whileTyping: true)
        XCTAssertEqual(notes, .string("Ferry moved to ten"), "the other device's edit is here once the person's typing is gone")
    }

    /// The same without the unsaved typing: the edit arrives (so the test above shows the stale rounds, not the rig).
    func testFinding18_control_anEditThatArrivesWithNothingUnsavedIsWritten() async throws {
        let notes = try await anEditArriving(whileTyping: false)
        XCTAssertEqual(notes, .string("Ferry moved to ten"))
    }

    private func anEditArriving(whileTyping: Bool) async throws -> SyncValue? {
        main.autosaveEnabled = false
        let task = TaskItem(title: "Trip", notes: "Ferry at nine")
        main.insert(task)
        try main.save()
        let ledger = SyncLedgerStore.inMemory()
        let cloud = FakeCloud()
        let transport = FakeTransport(cloud: cloud, device: "s146", state: ledger)
        let core = SyncCore(store: store, ledger: ledger, transport: transport, host: nil)
        await core.start()
        try await core.syncNow()
        try await core.syncNow()
        let first = await cloud.record(key(task))
        XCTAssertNotNil(first, "setup: the task is in iCloud")

        // Another device's edit reaches iCloud while this person has the title half typed, unsaved.
        _ = await cloud.poke(key(task), ["notes": .string("Ferry moved to ten"), "updatedAt": .date(Date().addingTimeInterval(60))])
        if whileTyping { task.title = "Trip to O" }
        try await core.syncNow()
        // The person drops the typing (Discard); nothing is saved, so no save hint follows.
        main.rollback()
        try await core.syncNow()
        try await core.syncNow()
        return try await record(key(task))["notes"]
    }
}
