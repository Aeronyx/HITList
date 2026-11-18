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
        _ = try Deduplicator.run(in: context, byName: true, mergesSharedIDs: false)
        let left = try context.fetch(FetchDescriptor<SavedFilter>())
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left.first?.updatedAt, lastMonth)
        // Two copies a person changed still take the newer stamp, as before.
        context.insert(filter("Today", "today", id: UUID(), made: longAgo.addingTimeInterval(60), changed: now))
        try context.save()
        _ = try Deduplicator.run(in: context, byName: true, mergesSharedIDs: false)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedFilter>()).first?.updatedAt, now)
    }

    /// A5: a store that came back from HITList's own sync by hand merges rows that share an id on the mirror too
    /// (what it received through the engine may arrive again as another device's records); any other store on the
    /// mirror is left exactly as before.
    func testAStoreThatCameBackMergesRowsThatShareAnID() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let a = TaskItem(title: "Water the plants"), b = TaskItem(title: "Water the plants")
        b.id = a.id
        context.insert(a); context.insert(b)
        try context.save()
        _ = try Deduplicator.run(in: context, byName: true, mergesSharedIDs: false)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.title == "Water the plants" })), 2,
                       "the mirror alone never merged tasks")
        _ = try Deduplicator.run(in: context, byName: true, mergesSharedIDs: true)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.title == "Water the plants" })), 1)
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
