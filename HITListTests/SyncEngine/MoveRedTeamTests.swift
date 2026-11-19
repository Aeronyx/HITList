import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Round 34, brief 171: what the review that tried to lose a tester's tasks found outside the move's own rules, each
/// with the test of its fix. (The rules' own are in `SyncEngineAutoMoveTests`.)
@MainActor
final class MoveRedTeamTests: XCTestCase {
    private let fm = FileManager.default
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "MoveRedTeamTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
    }

    private let longAgo = Date(timeIntervalSince1970: 1_780_000_000)
    private var lastMonth: Date { longAgo.addingTimeInterval(30 * 86_400) }

    private func filter(_ name: String, _ query: String, id: UUID, made: Date, changed: Date) -> SavedFilter {
        let filter = SavedFilter(name: name, query: query)
        filter.id = id
        filter.createdAt = made
        filter.updatedAt = changed
        return filter
    }

    /// A8: a fresh install seeds its default filters "now". The person's own copy, renamed long ago, arrives with the
    /// same id. Merged by id, the untouched seed must not win, and must not lend its stamp: carried to the engine it
    /// would beat every change made to that filter on another device since.
    func testAnUntouchedSeedNeverWinsOverThePersonsCopyNorLendsItsStamp() throws {
        let seedID = SeedIdentity.uuid(for: "filter.today")
        XCTAssertTrue(Deduplicator.isUntouchedSeed(id: seedID, createdAt: longAgo, updatedAt: longAgo))
        XCTAssertFalse(Deduplicator.isUntouchedSeed(id: seedID, createdAt: longAgo, updatedAt: lastMonth), "a seed someone changed")
        XCTAssertFalse(Deduplicator.isUntouchedSeed(id: UUID(), createdAt: longAgo, updatedAt: longAgo), "not a seed")

        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        for existing in try context.fetch(FetchDescriptor<SavedFilter>()) { context.delete(existing) }
        let now = Date()
        context.insert(filter("Now", "today & p1", id: seedID, made: longAgo, changed: lastMonth)) // the person's, renamed
        context.insert(filter("Today", "today", id: seedID, made: now, changed: now))             // this install's seed
        try context.save()
        _ = try Deduplicator.mergeSharedIDs(in: context)
        let left = try context.fetch(FetchDescriptor<SavedFilter>())
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left.first?.name, "Now", "the person's copy stays")
        XCTAssertEqual(left.first?.updatedAt, lastMonth, "with its own stamp, not the seed's")
    }

    /// The same on the mirror, where rows of one name are merged: the earliest wins as before, and keeps its stamp.
    func testTheMirrorsMergeByNameKeepsThePersonsStampOverAnUntouchedSeeds() throws {
        let seedID = SeedIdentity.uuid(for: "filter.today")
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        for existing in try context.fetch(FetchDescriptor<SavedFilter>()) { context.delete(existing) }
        let now = Date()
        context.insert(filter("Today", "today", id: seedID, made: longAgo, changed: lastMonth))
        context.insert(filter("Today", "today", id: seedID, made: now, changed: now))
        try context.save()
        _ = try Deduplicator.run(in: context, byName: true)
        let left = try context.fetch(FetchDescriptor<SavedFilter>())
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left.first?.updatedAt, lastMonth)
        // Two copies a person changed still take the newer stamp, as before.
        context.insert(filter("Today", "today", id: UUID(), made: longAgo.addingTimeInterval(60), changed: now))
        try context.save()
        _ = try Deduplicator.run(in: context, byName: true)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedFilter>()).first?.updatedAt, now)
    }

    /// A5, taken back (brief 172's finding 1): on the mirror, rows of a task that share an `id` are never merged,
    /// whatever the store went through. Two devices that both came back from the engine with their own file each
    /// hold an item made on the engine twice, as two records of the mirror's; a merge on each kept "its own" of
    /// two equal rows and deleted the other, and the mirror took both deletions to every device.
    func testTheMirrorNeverMergesTasksThatShareAnIDSoTwoDevicesCannotDeleteEachOthersCopy() throws {
        let made = Date(timeIntervalSince1970: 1_800_000_000.123_456)
        let rounded = Date(timeIntervalSince1970: (made.timeIntervalSince1970 * 1000).rounded() / 1000)
        let id = UUID()
        func row(_ record: String, _ stamp: Date) -> TaskItem {
            let task = TaskItem(title: "Item made on the engine")
            task.id = id
            task.notes = record
            task.createdAt = stamp
            task.updatedAt = stamp
            return task
        }
        // Device A made the item (its row X, at full precision) and received E's record Y; device E received the
        // item through the engine (rounded to milliseconds) and then A's record X.
        let onA = ModelContainerFactory.preview(), a = onA.mainContext
        a.insert(row("X", made)); try a.save()
        a.insert(row("Y", rounded)); try a.save()
        let onE = ModelContainerFactory.preview(), e = onE.mainContext
        e.insert(row("Y", rounded)); try e.save()
        e.insert(row("X", rounded)); try e.save()
        // Both stores came back by hand: the key that once switched the merge on.
        AppGroup.defaults.set(true, forKey: SyncEngineAutoMove.stayKey(ModelContainerFactory.storeName))
        defer { AppGroup.defaults.removeObject(forKey: SyncEngineAutoMove.stayKey(ModelContainerFactory.storeName)) }
        _ = try Deduplicator.run(in: a, byName: true)
        _ = try Deduplicator.run(in: e, byName: true)
        let keptOnA = try a.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).map(\.notes).sorted()
        let keptOnE = try e.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).map(\.notes).sorted()
        XCTAssertEqual(keptOnA, ["X", "Y"], "nothing deleted on A")
        XCTAssertEqual(keptOnE, ["X", "Y"], "nothing deleted on E: no record of the item is deleted in iCloud")
        _ = (onA, onE)
    }

    /// Brief 172's finding 3: a default filter nobody changed takes the engine's seed stamp before the engine reads
    /// the store, so the note of a deletion made on the engine since wins over a fresh install's seed. A filter a
    /// person changed, one a person made, and a label keep their stamps; a second pass changes nothing.
    func testADefaultFilterNobodyChangedTakesTheSeedStampBeforeTheEngineStarts() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        for existing in try context.fetch(FetchDescriptor<SavedFilter>()) { context.delete(existing) }
        let now = Date()
        let fresh = filter("Today", "today", id: SeedIdentity.uuid(for: "filter.today"), made: now, changed: now)
        let changed = filter("Soon", "7 days", id: SeedIdentity.uuid(for: "filter.soon"), made: longAgo, changed: lastMonth)
        let own = filter("Mine", "p1", id: UUID(), made: now, changed: now)
        let label = TaskLabel(name: "Board")
        label.id = SeedIdentity.uuid(for: "TaskLabel/flipboard")
        label.createdAt = now
        label.updatedAt = now
        context.insert(fresh); context.insert(changed); context.insert(own); context.insert(label)
        try context.save()

        XCTAssertEqual(try Deduplicator.backdateUntouchedSeeds(in: context), 1)
        XCTAssertEqual(fresh.createdAt, TaskActions.engineSeedDate)
        XCTAssertEqual(fresh.updatedAt, TaskActions.engineSeedDate)
        XCTAssertEqual(changed.updatedAt, lastMonth, "a default a person changed keeps its stamp")
        XCTAssertEqual(own.updatedAt, now, "a filter a person made is not a seed")
        XCTAssertEqual(label.updatedAt, now, "a label is made by something a person did, at the time its stamp says")
        XCTAssertEqual(try Deduplicator.backdateUntouchedSeeds(in: context), 0, "a second pass changes nothing")
    }

    /// C1: the copy kept before the new sync is the previous account's tasks too: it leaves the visible folder with
    /// the daily backups at an account switch, and comes back with them.
    func testTheKeptCopyFollowsItsAccountWithTheDailyBackups() throws {
        func tempDir() throws -> URL {
            let url = fm.temporaryDirectory.appending(path: "t171-\(UUID().uuidString)")
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let documents = try tempDir(), root = try tempDir()
        defer { try? fm.removeItem(at: documents); try? fm.removeItem(at: root) }
        let alice = AccountIdentity.key(recordName: "_alice"), bob = AccountIdentity.key(recordName: "_bob")
        try Data("a".utf8).write(to: documents.appending(path: "HITList-2026-11-01.json"))
        try Data("kept".utf8).write(to: documents.appending(path: "HITList before the new sync 2026-11-01.json"))
        try Data("x".utf8).write(to: documents.appending(path: "notes.txt"))
        let toBob = LocalBackup.setAside(previousAccount: alice, currentAccount: bob, directory: documents, root: root, defaults: defaults)
        XCTAssertEqual(toBob.movedAside, 2)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: documents.path), ["notes.txt"], "nothing of Alice's is left for Bob to open")
        let back = LocalBackup.setAside(previousAccount: bob, currentAccount: alice, directory: documents, root: root, defaults: defaults)
        XCTAssertEqual(back.restored, 2)
        XCTAssertEqual(LocalBackup.keptBeforeTheNewSync(in: documents).count, 1)
    }
}
