import XCTest
import Observation
import SwiftData
import HITListCore
@testable import HITList

/// Round 28, brief 141: `SwiftDataSyncStore` (`SyncLocalStore` on the app's container) and `SyncSaveHints`. Every test
/// runs on an in-memory container with its main context used as the app's views use it.
@MainActor
class SwiftDataSyncStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var folder: URL?
    private var main: ModelContext!
    private var store: SwiftDataSyncStore!
    private var hook: DayAnchoring.SaveHook?
    private var observers: [NSObjectProtocol] = []

    /// The container the tests run on: in memory here, a file as the app has (`SwiftDataSyncStoreFileTests`).
    func makeContainer(in folder: URL) throws -> ModelContainer? { nil }

    override func setUp() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SwiftDataSyncStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        container = try makeContainer(in: folder) ?? ModelContainerFactory.preview()
        main = container.mainContext
        store = SwiftDataSyncStore(container: container)
    }

    override func tearDown() async throws {
        hook?.stop()
        hook = nil
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers = []
        store = nil
        main = nil
        container = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    // MARK: - Helpers

    private func key(_ task: TaskItem) -> SyncKey { SyncKey(type: "TaskItem", name: task.id.uuidString) }

    private func saved(_ id: UUID) throws -> TaskItem? {
        let fresh = ModelContext(container)
        return try fresh.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }

    private func record(_ key: SyncKey) async throws -> SyncRecord {
        let found = try await store.records([key])
        return try XCTUnwrap(found.first)
    }

    /// Counts the saves of the engine's own contexts on this container (`ModelContext.author`).
    private func countEngineSaves() -> Locked<Int> {
        let count = Locked(0)
        let container = container!
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { note in
            guard let context = note.object as? ModelContext, context.container === container,
                  context.author == SwiftDataSyncStore.author else { return }
            count.mutate { $0 += 1 }
        })
        return count
    }

    /// Lets the main queue run everything enqueued on it so far (a merge SwiftData posts to the main context, say).
    private func drainMainQueue() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { done.resume() }
        }
    }

    // MARK: - records()

    func testRecordsAreWhatIsSavedNow() async throws {
        let group = Project(name: "Home")
        let label = TaskLabel(name: "errand")
        main.insert(group)
        main.insert(label)
        let task = TaskItem(title: "Milk", project: group, labels: [label])
        main.insert(task)
        try main.save()
        let unsaved = TaskItem(title: "Not yet")
        main.insert(unsaved)

        let records = try await store.records()
        XCTAssertEqual(records.map(\.key.type).sorted(), ["Project", "TaskItem", "TaskLabel"], "an unsaved row is not read")
        let milk = try XCTUnwrap(records.first { $0.key == key(task) })
        XCTAssertEqual(milk["project"], .reference(group.id.uuidString))
        XCTAssertEqual(milk["labels"], .references([label.id.uuidString]))
        XCTAssertEqual(records, records.sorted { $0.key < $1.key })

        let some = try await store.records([key(task), SyncKey(type: "TaskItem", name: UUID().uuidString),
                                            SyncKey(type: "Nothing", name: "x")])
        XCTAssertEqual(some, [milk], "a key with no item is absent from the answer")
    }

    func testTwoRowsWithOneKeyAreDuplicates() async throws {
        let a = TaskItem(title: "a")
        let b = TaskItem(title: "b")
        b.id = a.id
        main.insert(a)
        main.insert(b)
        try main.save()
        do {
            _ = try await store.records()
            XCTFail("two rows with one id must not read as one record")
        } catch let error as SyncStoreError {
            XCTAssertEqual(error, .duplicates([key(a)]))
        }
        do {
            _ = try await store.apply([LocalWrite(key: key(a), expected: nil, record: nil)])
            XCTFail("a write to a key with two rows must throw")
        } catch let error as SyncStoreError {
            XCTAssertEqual(error, .duplicates([key(a)]))
        }
    }

    func testSeveralProfileRowsAreDuplicatesOfTheOneRecord() async throws {
        main.insert(Profile())
        main.insert(Profile())
        try main.save()
        do {
            _ = try await store.records([SyncKey(type: "Profile", name: "profile")])
            XCTFail("two profiles are two rows for the record profile")
        } catch let error as SyncStoreError {
            XCTAssertEqual(error, .duplicates([SyncKey(type: "Profile", name: "profile")]))
        }
    }

    // MARK: - apply()

    func testApplyInsertsUpdatesAndDeletesInOneSave() async throws {
        let keep = TaskItem(title: "Keep")
        let gone = TaskItem(title: "Gone")
        main.insert(keep)
        main.insert(gone)
        try main.save()
        let saves = countEngineSaves()

        var changed = try await record(key(keep))
        changed["title"] = .string("Kept and changed")
        let new = SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: ["title": .string("New")])
        let stale = try await store.apply([
            LocalWrite(key: key(keep), expected: try await record(key(keep)), record: changed),
            LocalWrite(key: new.key, expected: nil, record: new),
            LocalWrite(key: key(gone), expected: try await record(key(gone)), record: nil),
        ])
        XCTAssertEqual(stale, [])
        XCTAssertEqual(saves.value, 1, "one save for the whole write")
        XCTAssertEqual(try saved(keep.id)?.title, "Kept and changed")
        XCTAssertNil(try saved(gone.id))
        let inserted = try await record(new.key)
        XCTAssertEqual(inserted, SyncSchema.filled(new), "required fields filled in")
    }

    func testAnEqualRecordWritesNothing() async throws {
        let task = TaskItem(title: "Same")
        task.dueDate = Date(timeIntervalSince1970: 1_763_190_000.123_45)
        main.insert(task)
        try main.save()
        let saves = countEngineSaves()
        let now = try await record(key(task))
        let stale = try await store.apply([LocalWrite(key: key(task), expected: now, record: now)])
        XCTAssertEqual(stale, [])
        XCTAssertEqual(saves.value, 0, "nothing differed, so nothing was saved")
        XCTAssertEqual(try saved(task.id)?.dueDate, task.dueDate, "the sub-millisecond digits are untouched")
    }

    func testAnInsertWhereTheRowAlreadyIsIsStale() async throws {
        let task = TaskItem(title: "Here")
        main.insert(task)
        try main.save()
        let record = SyncRecord(type: "TaskItem", name: task.id.uuidString, fields: ["title": .string("Theirs")])
        let stale = try await store.apply([LocalWrite(key: key(task), expected: nil, record: record)])
        XCTAssertEqual(stale, [key(task)])
        XCTAssertEqual(try saved(task.id)?.title, "Here")
    }

    /// (a) The person's edit, saved between the brain's read and its write: the write is refused for that key (the
    /// key comes back), the edit is intact, and the call's other writes are made.
    func testAnEditSavedBetweenTheReadAndTheWriteComesBackAsStaleAndIsIntact() async throws {
        let task = TaskItem(title: "Before", notes: "old")
        let other = TaskItem(title: "Other")
        main.insert(task)
        main.insert(other)
        try main.save()
        let read = try await store.records()

        task.title = "The person's title"
        try main.save()

        let before = try XCTUnwrap(read.first { $0.key == key(task) })
        var engine = before
        engine["notes"] = .string("the engine's notes")
        let otherBefore = try XCTUnwrap(read.first { $0.key == key(other) })
        var otherAfter = otherBefore
        otherAfter["title"] = .string("Other, changed")
        let stale = try await store.apply([LocalWrite(key: key(task), expected: before, record: engine),
                                           LocalWrite(key: key(other), expected: otherBefore, record: otherAfter)])
        XCTAssertEqual(stale, [key(task)])
        XCTAssertEqual(try saved(task.id)?.title, "The person's title")
        XCTAssertEqual(try saved(task.id)?.notes, "old", "nothing was written for the stale key")
        XCTAssertEqual(try saved(other.id)?.title, "Other, changed")
    }

    /// (b) The person's edit made on the main context and **not saved yet** when the engine writes the same row: the
    /// engine writes through the main context, so it sees the edit; the key comes back stale and nothing is written.
    /// Once the person has saved, the brain decides again on the newer record and writes its field: the person's
    /// field has the person's value, the engine's field the engine's.
    func testAnUnsavedEditOnTheRowTheEngineWritesComesBackStaleAndThenBothFieldsSurvive() async throws {
        main.autosaveEnabled = false  // the edit stays unsaved exactly as long as this test says
        let task = TaskItem(title: "Before", notes: "old")
        main.insert(task)
        try main.save()
        let before = try await record(key(task))

        task.title = "The person's title"  // typed, not saved

        var engine = before
        engine["notes"] = .string("the engine's notes")
        let stale = try await store.apply([LocalWrite(key: key(task), expected: before, record: engine)])
        XCTAssertEqual(stale, [key(task)], "the row is not as the brain read it: the person is editing it")
        XCTAssertEqual(task.notes, "old", "nothing written")
        XCTAssertTrue(main.hasChanges, "the person's edit is still pending")

        try main.save()
        let now = try await record(key(task))
        XCTAssertEqual(now["title"], .string("The person's title"))
        var merged = now
        merged["notes"] = .string("the engine's notes")
        let again = try await store.apply([LocalWrite(key: key(task), expected: now, record: merged)])
        XCTAssertEqual(again, [])
        let stored = try XCTUnwrap(try saved(task.id))
        XCTAssertEqual(stored.title, "The person's title", "the person's field")
        XCTAssertEqual(stored.notes, "the engine's notes", "the engine's field")
        XCTAssertEqual(task.notes, "the engine's notes", "and the row the view holds shows it")
    }

    /// (b), the same field: the person's unsaved value and another device's value for one field. The person's is the
    /// later edit; the write comes back stale and the person's value is what the store ends with.
    func testAnUnsavedEditToTheFieldTheEngineWritesKeepsThePersonsValue() async throws {
        main.autosaveEnabled = false
        let task = TaskItem(title: "Before")
        main.insert(task)
        try main.save()
        let before = try await record(key(task))
        task.title = "The person's title"
        var engine = before
        engine["title"] = .string("Another device's title")
        let stale = try await store.apply([LocalWrite(key: key(task), expected: before, record: engine)])
        XCTAssertEqual(stale, [key(task)])
        try main.save()
        XCTAssertEqual(try saved(task.id)?.title, "The person's title")
    }

    /// An unsaved edit of another row is saved with the engine's save (the main context saves whole, as its autosave
    /// would have a moment later): nothing of it is lost.
    func testAnUnsavedEditOfAnotherRowIsSavedWithTheEnginesWrite() async throws {
        main.autosaveEnabled = false
        let mine = TaskItem(title: "Mine")
        let theirs = TaskItem(title: "Theirs")
        main.insert(mine)
        main.insert(theirs)
        try main.save()
        mine.title = "Mine, edited"
        let before = try await record(key(theirs))
        var after = before
        after["title"] = .string("Theirs, from iCloud")
        let stale = try await store.apply([LocalWrite(key: key(theirs), expected: before, record: after)])
        XCTAssertEqual(stale, [])
        XCTAssertEqual(try saved(mine.id)?.title, "Mine, edited")
        XCTAssertEqual(try saved(theirs.id)?.title, "Theirs, from iCloud")
        XCTAssertFalse(main.hasChanges)
    }

    /// Why the engine does not write from a context of its own (`SwiftDataSyncStore.Writer.ownContext`): SwiftData's main
    /// context does not take that save in, and the person's next save of the row writes the main context's whole old
    /// copy back. The person's field keeps the person's value; the engine's field is reverted, with no error. Pinned, so
    /// that a SwiftData that starts merging shows here (this test then fails, and the choice can be looked at again).
    func testAWriteFromAContextOfItsOwnIsRevertedByTheMainContextsNextSave() async throws {
        main.autosaveEnabled = false
        let task = TaskItem(title: "Before", notes: "old")
        main.insert(task)
        try main.save()
        let before = try await record(key(task))
        task.title = "The person's title"

        var engine = before
        engine["notes"] = .string("the engine's notes")
        let ownContext = SwiftDataSyncStore(container: container, writer: .ownContext)
        let stale = try await ownContext.apply([LocalWrite(key: key(task), expected: before, record: engine)])
        XCTAssertEqual(stale, [], "the unsaved edit is not in the store, so a context of its own writes")
        XCTAssertEqual(try saved(task.id)?.notes, "the engine's notes", "saved")
        await drainMainQueue()
        XCTAssertEqual(task.notes, "old", "the main context's row was not told")

        try main.save()
        let stored = try XCTUnwrap(try saved(task.id))
        XCTAssertEqual(stored.title, "The person's title")
        XCTAssertEqual(stored.notes, "old", "the engine's write was reverted by the person's save")
    }

    /// (c) The main context sees what the engine inserted, changed and deleted, without being told: a fetch after it,
    /// and an observation of a row it already holds (what a `@Query` and a view reading the row rely on).
    func testTheMainContextSeesTheEnginesInsertsChangesAndDeletions() async throws {
        let changed = TaskItem(title: "Changed", notes: "old")
        let deleted = TaskItem(title: "Deleted")
        main.insert(changed)
        main.insert(deleted)
        try main.save()
        XCTAssertEqual(changed.notes, "old")  // the main context holds the row, as a view showing it would

        let observed = expectation(description: "the main context's row reports the engine's change")
        withObservationTracking { _ = changed.notes } onChange: { observed.fulfill() }

        var after = try await record(key(changed))
        after["notes"] = .string("the engine's notes")
        let new = SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: ["title": .string("Inserted")])
        _ = try await store.apply([
            LocalWrite(key: key(changed), expected: try await record(key(changed)), record: after),
            LocalWrite(key: key(deleted), expected: try await record(key(deleted)), record: nil),
            LocalWrite(key: new.key, expected: nil, record: new),
        ])
        await fulfillment(of: [observed], timeout: 10)
        XCTAssertEqual(changed.notes, "the engine's notes")

        let titles = try main.fetch(FetchDescriptor<TaskItem>()).map(\.title).sorted()
        XCTAssertEqual(titles, ["Changed", "Inserted"])
    }

    func testAReferenceToAnItemThatIsNotHereIsWrittenAsNone() async throws {
        let missing = UUID().uuidString
        let label = TaskLabel(name: "here")
        main.insert(label)
        try main.save()
        let record = SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: [
            "title": .string("Orphan"), "project": .reference(missing), "parent": .reference(missing),
            "labels": .references([missing, label.id.uuidString]),
        ])
        _ = try await store.apply([LocalWrite(key: record.key, expected: nil, record: record)])
        let back = try await self.record(record.key)
        XCTAssertNil(back["project"])
        XCTAssertNil(back["parent"])
        XCTAssertEqual(back["labels"], .references([label.id.uuidString]))
    }

    func testATaskIsWrittenAfterItsParentAndAGroupBeforeItsTasksWhateverTheOrderGiven() async throws {
        let group = SyncRecord(type: "Project", name: UUID().uuidString, fields: ["name": .string("G")])
        let parent = SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: [
            "title": .string("Parent"), "project": .reference(group.key.name)])
        let child = SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: [
            "title": .string("Child"), "parent": .reference(parent.key.name), "project": .reference(group.key.name)])
        let stale = try await store.apply([child, parent, group].map { LocalWrite(key: $0.key, expected: nil, record: $0) })
        XCTAssertEqual(stale, [])
        let back = try await store.records()
        XCTAssertEqual(back.first { $0.key == child.key }?["parent"], .reference(parent.key.name))
        XCTAssertEqual(back.first { $0.key == parent.key }?["project"], .reference(group.key.name))
    }

    func testDeletingATaskTakesItsSubtasksAndDeletingAGroupLeavesItsTasks() async throws {
        let group = Project(name: "G")
        main.insert(group)
        let parent = TaskItem(title: "Parent", project: group)
        main.insert(parent)
        let sub = TaskItem(title: "Sub", project: group)
        sub.parent = parent
        main.insert(sub)
        try main.save()
        let groupKey = SyncKey(type: "Project", name: group.id.uuidString)
        // The review's finding 1: a deletion removes exactly the rows named. The task alone, with a sub-task under
        // it that no write names: stale, nothing deleted.
        let alone = try await store.apply([LocalWrite(key: key(parent), expected: try await record(key(parent)), record: nil)])
        XCTAssertEqual(alone, [key(parent)], "a sub-task no write names would go with it: stale")
        let still = try await store.records()
        XCTAssertEqual(still.count, 3, "nothing was deleted")
        // A sub-task the person has made and not saved yet protects its parent too.
        let unsaved = TaskItem(title: "Typed a moment ago", project: group)
        unsaved.parent = parent
        main.insert(unsaved)
        let withUnsaved = try await store.apply([
            LocalWrite(key: key(parent), expected: try await record(key(parent)), record: nil),
            LocalWrite(key: key(sub), expected: try await record(key(sub)), record: nil),
        ])
        XCTAssertTrue(withUnsaved.contains(key(parent)), "the unsaved sub-task is not named: the parent stays")
        main.delete(unsaved)
        try main.save()
        XCTAssertNotNil(try saved(parent.id))
        // Named, every one: the task and its sub-task go, and the Group.
        let subStillHere = try saved(sub.id) != nil
        var writes = [
            LocalWrite(key: key(parent), expected: try await record(key(parent)), record: nil),
            LocalWrite(key: groupKey, expected: try await record(groupKey), record: nil),
        ]
        if subStillHere { writes.append(LocalWrite(key: key(sub), expected: try await record(key(sub)), record: nil)) }
        let stale = try await store.apply(writes)
        XCTAssertEqual(stale, [])
        let left = try await store.records()
        XCTAssertEqual(left, [], "the task and the sub-task named with it went, the Group was deleted")

        let h0 = Project(name: "H")
        main.insert(h0)
        let loose = TaskItem(title: "Loose", project: h0)
        main.insert(loose)
        try main.save()
        let h = SyncKey(type: "Project", name: try XCTUnwrap(loose.project).id.uuidString)
        _ = try await store.apply([LocalWrite(key: h, expected: try await record(h), record: nil)])
        let task = try await record(key(loose))
        XCTAssertNil(task["project"], "a Group's tasks stay, with no Group")
    }

    func testAWriteThatFailsToSaveLeavesNothingAndThrows() async throws {
        let task = TaskItem(title: "Before")
        main.insert(task)
        try main.save()
        let before = try await record(key(task))
        var after = before
        after["title"] = .string("After")
        let new = SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: ["title": .string("New")])
        struct Boom: Error {}
        XCTAssertThrowsError(try SwiftDataSyncStore.apply(
            [LocalWrite(key: key(task), expected: before, record: after), LocalWrite(key: new.key, expected: nil, record: new)],
            in: container, beforeSave: { throw Boom() })) { XCTAssertTrue($0 is Boom) }
        let records = try await store.records()
        XCTAssertEqual(records, [before], "neither the change nor the insert is in the store")
    }

    // MARK: - The day anchoring inside the engine's save

    /// `DayAnchoring.SaveHook` runs inside every save on the app's container, the engine's too: a date-only due date
    /// written as this zone's midnight comes back anchored (10:00 UTC on its day) on the next read, and applying the
    /// anchored record again writes nothing.
    func testADayWrittenAsAMidnightComesBackAnchoredAndIsThenStable() async throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        hook = DayAnchoring.SaveHook(container: container, calendar: { newYork }, enabled: true)
        let day = DayAnchor.Day(year: 2026, month: 11, day: 20)
        let midnight = DayAnchor.start(of: day, calendar: newYork)
        let anchored = DayAnchor.anchor(of: day)

        let record = SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: [
            "title": .string("Day"), "dueDate": .date(midnight), "hasDueTime": .bool(false), "deadline": .date(midnight)])
        _ = try await store.apply([LocalWrite(key: record.key, expected: nil, record: record)])
        let back = try await self.record(record.key)
        XCTAssertEqual(back["dueDate"], .date(anchored), "anchored inside the engine's own save")
        XCTAssertEqual(back["deadline"], .date(anchored))
        XCTAssertNotEqual(back, SyncSchema.filled(record), "so the brain finds the anchored day differs and sends it")

        let saves = countEngineSaves()
        let stale = try await store.apply([LocalWrite(key: record.key, expected: back, record: back)])
        XCTAssertEqual(stale, [])
        XCTAssertEqual(saves.value, 0, "the anchored record again writes nothing")
        let again = try await self.record(record.key)
        XCTAssertEqual(again, back)
    }

    // MARK: - Size

    /// 5,000 tasks with labels and Groups (a tenth of them sub-tasks): read whole, written whole into an empty store,
    /// and checked whole again (every write equal: nothing saved). The times go in the report.
    func testFiveThousandTasksWithLabelsAndGroups() async throws {
        var groups: [Project] = []
        for n in 0..<20 {
            let group = Project(name: "Group \(n)", sortOrder: n)
            main.insert(group)
            groups.append(group)
        }
        var labels: [TaskLabel] = []
        for n in 0..<12 {
            let label = TaskLabel(name: "label\(n)")
            main.insert(label)
            labels.append(label)
        }
        var previous: TaskItem?
        for n in 0..<5_000 {
            let task = TaskItem(title: "Task \(n)", notes: "notes \(n)", priority: 1 + n % 4,
                                project: groups[n % groups.count], labels: [labels[n % 12], labels[(n * 7 + 3) % 12]])
            task.dueDate = Date(timeIntervalSince1970: 1_763_000_000 + Double(n) * 3_600)
            if n % 10 == 9, let previous { task.parent = previous }
            main.insert(task)
            previous = task
        }
        try main.save()

        let clock = ContinuousClock()
        var records: [SyncRecord] = []
        let read = try await clock.measure { records = try await store.records() }
        XCTAssertEqual(records.count, 5_000 + 20 + 12)

        let other = ModelContainerFactory.preview()
        let target = SwiftDataSyncStore(container: other)
        let writes = records.map { LocalWrite(key: $0.key, expected: nil, record: $0) }
        let write = try await clock.measure { _ = try await target.apply(writes) }

        var back: [SyncRecord] = []
        let readBack = try await clock.measure { back = try await target.records() }
        XCTAssertEqual(back, records)

        let equal = back.map { LocalWrite(key: $0.key, expected: $0, record: $0) }
        let check = try await clock.measure { _ = try await target.apply(equal) }

        var some: [SyncRecord] = []
        let hinted = Set(records.prefix(200).map(\.key))
        let keyed = try await clock.measure { some = try await target.records(hinted) }
        XCTAssertEqual(some.count, 200)

        print("141 size: records() of 5,032 rows \(read); apply of 5,032 inserts \(write); records() again \(readBack); apply of 5,032 equal records \(check); records(200 keys) \(keyed)")
        XCTAssertLessThan(read, .seconds(30))
        XCTAssertLessThan(write, .seconds(60))
    }

    // MARK: - Where the engine's work runs

    func testTheEnginesWritesAreSavedOnTheMainContext() async throws {
        let saves = Locked<[Bool]>([])
        let container = container!
        let main = main!
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { note in
            guard let context = note.object as? ModelContext, context.container === container,
                  context.author == SwiftDataSyncStore.author else { return }
            let onMain = Thread.isMainThread && context == main
            saves.mutate { $0.append(onMain) }
        })
        let record = SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: ["title": .string("x")])
        _ = try await store.apply([LocalWrite(key: record.key, expected: nil, record: record)])
        XCTAssertEqual(saves.value, [true])
        XCTAssertNil(main.author, "the author is the engine's for its own save only")
    }

    /// A save on the main context that fails takes back the engine's own changes without `rollback()`: the person's
    /// unsaved edit of another row is still there, and saved later, nothing of the engine's goes with it.
    func testAFailedSaveOnTheMainContextTakesBackOnlyTheEnginesChanges() async throws {
        main.autosaveEnabled = false
        let mine = TaskItem(title: "Mine")
        let theirs = TaskItem(title: "Theirs")
        main.insert(mine)
        main.insert(theirs)
        try main.save()
        mine.title = "Mine, edited"
        let before = try await record(key(theirs))
        var after = before
        after["title"] = .string("Theirs, from iCloud")
        let new = SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: ["title": .string("New")])
        struct Boom: Error {}
        XCTAssertThrowsError(try SwiftDataSyncStore.apply(
            [LocalWrite(key: key(theirs), expected: before, record: after), LocalWrite(key: new.key, expected: nil, record: new)],
            on: main, shared: true, beforeSave: { throw Boom() })) { XCTAssertTrue($0 is Boom) }
        XCTAssertEqual(mine.title, "Mine, edited", "the person's edit is kept")
        XCTAssertEqual(theirs.title, "Theirs", "the engine's change taken back")
        try main.save()
        let records = try await store.records()
        XCTAssertEqual(records.map { $0["title"] }.compactMap { $0 }.sorted { "\($0)" < "\($1)" },
                       [.string("Mine, edited"), .string("Theirs")])
    }

    // MARK: - SyncSaveHints

    private func collectHints() -> Locked<[SyncSaveHint]> {
        let hints = Locked<[SyncSaveHint]>([])
        let container = container!
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { note in
            let hint = SyncSaveHints.hint(for: note, container: container)
            hints.mutate { $0.append(hint) }
        })
        return hints
    }

    func testAHintNamesTheRowsASaveInsertedOrChanged() throws {
        let hints = collectHints()
        let task = TaskItem(title: "a")
        main.insert(task)
        try main.save()
        task.title = "b"
        let label = TaskLabel(name: "l")
        main.insert(label)
        try main.save()
        let profile = Profile()
        main.insert(profile)
        try main.save()
        XCTAssertEqual(hints.value, [
            .keys([key(task)]),
            .keys([key(task), SyncKey(type: "TaskLabel", name: label.id.uuidString)]),
            .keys([SyncKey(type: "Profile", name: "profile")]),
        ])
    }

    func testAHintIsEverythingWhenASaveDeleted() throws {
        let task = TaskItem(title: "a")
        main.insert(task)
        try main.save()
        let hints = collectHints()
        main.delete(task)
        try main.save()
        XCTAssertEqual(hints.value, [.everything])
        XCTAssertNil(hints.value.first?.keys)
    }

    func testAnotherContainersSaveIsNothing() throws {
        let hints = collectHints()
        let other = ModelContainerFactory.preview()
        other.mainContext.insert(TaskItem(title: "elsewhere"))
        try other.mainContext.save()
        let tips = try ModelContainer(for: Schema([ForeignTipRecord.self]), configurations: [
            ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        tips.mainContext.insert(ForeignTipRecord())
        try tips.mainContext.save()
        XCTAssertEqual(hints.value, [.unrelated, .unrelated])
    }

    func testAHintFromAUserInfoWithNoContextOrAnUnknownShapeIsEverythingOrNothing() {
        let task = TaskItem(title: "a")
        main.insert(task)
        try? main.save()
        let id = task.persistentModelID
        XCTAssertEqual(SyncSaveHints.hint(userInfo: ["inserted": [id], "updated": [PersistentIdentifier](), "deleted": [PersistentIdentifier]()],
                                          context: nil), .everything, "a row that can't be named")
        XCTAssertEqual(SyncSaveHints.hint(userInfo: ["inserted": "?", "updated": [PersistentIdentifier](), "deleted": [PersistentIdentifier]()],
                                          context: main), .everything, "a shape never seen")
        XCTAssertEqual(SyncSaveHints.hint(userInfo: ["inserted": [PersistentIdentifier](), "updated": [PersistentIdentifier](),
                                                     "deleted": [PersistentIdentifier]()], context: main), .unrelated)
        XCTAssertEqual(SyncSaveHints.hint(userInfo: ["inserted": Set([id]), "updated": [PersistentIdentifier](), "deleted": [PersistentIdentifier]()],
                                          context: main), .keys([key(task)]), "a set, as the doc comment says, reads too")
    }

    /// The engine's own save tells the brain nothing (it would only be told to look at what it just wrote), while
    /// every other listener of `didSave` (reminders, widgets, Spotlight) still hears it; another container's save is
    /// nothing either.
    func testTheEnginesOwnSaveIsNoHintButOtherListenersStillHearIt() async throws {
        let handed = Locked<[Set<SyncKey>?]>([])
        let observer = SyncSaveHintObserver(container: container) { keys in handed.mutate { $0.append(keys) } }
        defer { observer.stop() }
        let heard = Locked(0)
        let main = main!
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: main, queue: nil) { _ in
            heard.mutate { $0 += 1 }
        })
        let record = SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: ["title": .string("x")])
        _ = try await store.apply([LocalWrite(key: record.key, expected: nil, record: record)])
        let other = ModelContainerFactory.preview()
        other.mainContext.insert(TaskItem(title: "elsewhere"))
        try other.mainContext.save()
        XCTAssertEqual(handed.value.count, 0, "nothing handed to the brain")
        XCTAssertEqual(heard.value, 1, "the main context's didSave was posted")
        XCTAssertNil(SwiftDataSyncStore.savingOnMainContext, "the flag is cleared after the save")

        // The person's own save afterwards is a hint again.
        let task = try XCTUnwrap(try main.fetch(FetchDescriptor<TaskItem>()).first)
        task.title = "edited"
        try main.save()
        XCTAssertEqual(handed.value, [[record.key]])
    }

    /// The person's pending edits that go with the engine's save are still hinted: their rows' keys, without the rows
    /// the engine wrote; a pending deletion of the person's makes the hint everything.
    func testThePersonsPendingRowsInTheEnginesSaveAreStillHinted() async throws {
        main.autosaveEnabled = false
        let mine = TaskItem(title: "Mine")
        let theirs = TaskItem(title: "Theirs")
        let doomed = TaskItem(title: "Doomed")
        main.insert(mine)
        main.insert(theirs)
        main.insert(doomed)
        try main.save()
        let handed = Locked<[Set<SyncKey>?]>([])
        let observer = SyncSaveHintObserver(container: container) { keys in handed.mutate { $0.append(keys) } }
        defer { observer.stop() }

        mine.title = "Mine, edited"
        let label = TaskLabel(name: "new label of mine")
        main.insert(label)
        let before = try await record(key(theirs))
        var after = before
        after["title"] = .string("Theirs, from iCloud")
        _ = try await store.apply([LocalWrite(key: key(theirs), expected: before, record: after)])
        XCTAssertEqual(handed.value, [[key(mine), SyncKey(type: "TaskLabel", name: label.id.uuidString)]],
                       "the person's rows, not the engine's")

        main.delete(doomed)
        let now = try await record(key(theirs))
        var again = now
        again["title"] = .string("Theirs, again")
        _ = try await store.apply([LocalWrite(key: key(theirs), expected: now, record: again)])
        XCTAssertEqual(handed.value.count, 2)
        XCTAssertEqual(handed.value.last, .some(nil), "a deletion of the person's went with it: everything")
    }

    func testASaveFromAContextOfItsOwnIsNoHint() async throws {
        let hints = collectHints()
        let ownContext = SwiftDataSyncStore(container: container, writer: .ownContext)
        let record = SyncRecord(type: "TaskItem", name: UUID().uuidString, fields: ["title": .string("x")])
        _ = try await ownContext.apply([LocalWrite(key: record.key, expected: nil, record: record)])
        XCTAssertEqual(hints.value, [.unrelated])
    }

    // MARK: - The expected check

    /// `expected` is compared as the contract says (`RecordMerge.same`): a record that leaves out its required fields
    /// stands for their values and is the same as the row; a field that differs is not.
    func testExpectedIsComparedAsTheContractsSameness() async throws {
        let task = TaskItem(title: "")
        main.insert(task)
        try main.save()
        let sparse = SyncRecord(key: key(task), fields: ["createdAt": .date(task.createdAt), "updatedAt": .date(task.updatedAt)])
        var after = try await record(key(task))
        after["title"] = .string("written")
        let stale = try await store.apply([LocalWrite(key: key(task), expected: sparse, record: after)])
        XCTAssertEqual(stale, [], "required fields left out stand for their values")
        var wrong = sparse
        wrong["priority"] = .int(1)
        let refused = try await store.apply([LocalWrite(key: key(task), expected: wrong, record: after)])
        XCTAssertEqual(refused, [key(task)])
    }

    // MARK: - A fetched batch on the main actor

    /// What an apply of a fetched batch costs the main thread (the whole apply runs there): 200 and 500 new tasks with
    /// a Group, two labels each and a tenth of them sub-tasks, into a store that already has the Groups and labels.
    func testTheMainThreadTimeOfAnApplyOf200And500Inserts() async throws {
        var line: [String] = []
        for count in [200, 500] {
            let target = ModelContainerFactory.preview()
            var groups: [String] = []
            var labels: [String] = []
            for n in 0..<20 {
                let group = Project(name: "G\(n)")
                target.mainContext.insert(group)
                groups.append(group.id.uuidString)
            }
            for n in 0..<12 {
                let label = TaskLabel(name: "l\(n)")
                target.mainContext.insert(label)
                labels.append(label.id.uuidString)
            }
            try target.mainContext.save()
            var records: [SyncRecord] = []
            var previous: String?
            for n in 0..<count {
                let name = UUID().uuidString
                var fields: [String: SyncValue] = [
                    "title": .string("Task \(n)"), "notes": .string("notes \(n)"), "priority": .int(Int64(1 + n % 4)),
                    "dueDate": .millis(1_763_000_000_000 + Int64(n) * 3_600_000), "project": .reference(groups[n % 20]),
                    "labels": .references([labels[n % 12], labels[(n * 7 + 3) % 12]]),
                    "createdAt": .millis(1_763_000_000_000), "updatedAt": .millis(1_763_000_000_000),
                ]
                if n % 10 == 9, let previous { fields["parent"] = .reference(previous) }
                records.append(SyncRecord(type: "TaskItem", name: name, fields: fields))
                previous = name
            }
            let store = SwiftDataSyncStore(container: target)
            let writes = records.map { LocalWrite(key: $0.key, expected: nil, record: $0) }
            let elapsed = try await ContinuousClock().measure { _ = try await store.apply(writes) }
            let back = try await store.records(Set(records.map(\.key)))
            XCTAssertEqual(back.count, count)
            line.append("\(count) inserts \(elapsed)")
        }
        print("141 batch on the main actor: " + line.joined(separator: "; "))
    }
}

/// The same tests on a store file, opened as the app opens its own without CloudKit (`ModelContainerFactory.open`):
/// what SwiftData does between two contexts may differ between a file and memory.
final class SwiftDataSyncStoreFileTests: SwiftDataSyncStoreTests {
    override func makeContainer(in folder: URL) throws -> ModelContainer? {
        let opened = ModelContainerFactory.open(schema: HITListSchema.schema, url: folder.appending(path: "HITList.store"),
                                                useCloudKit: false)
        XCTAssertEqual(opened.outcome, .localOnly)
        return opened.container
    }
}

/// A value shared with an observer that runs on another thread.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value { lock.withLock { stored } }

    func mutate(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}
