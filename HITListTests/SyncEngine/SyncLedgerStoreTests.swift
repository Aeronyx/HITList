import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Round 28, brief 141: `SyncLedgerStore`, the sync engine's memory in a store of its own.
final class SyncLedgerStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "SyncLedgerStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func key(_ n: Int) -> SyncKey { SyncKey(type: "TaskItem", name: String(format: "00000000-0000-0000-0000-%012d", n)) }

    private func entry(_ n: Int) -> LedgerEntry {
        let base = SyncRecord(key: key(n), fields: ["title": .string("Task \(n)"), "updatedAt": .millis(1_763_000_000_000 + Int64(n)),
                                                    "labels": .references(["b", "a"]), "avatarData": .digest("ab\(n)")])
        return LedgerEntry(key: key(n), base: base, system: Data("token \(n)".utf8),
                           deletedHereAt: n % 3 == 0 ? Date(timeIntervalSince1970: 1_763_000_000.25) : nil)
    }

    private func cloud(_ n: Int) -> CloudRecord {
        CloudRecord(record: SyncRecord(key: key(n), fields: ["parent": .reference("p\(n)"), "data": .data(Data([1, 2, UInt8(n % 256)]))]),
                    system: Data("system \(n)".utf8))
    }

    // MARK: - Where it lives

    func testTheLedgerSitsBesideItsStoreUnderItsOwnName() {
        let group = URL(filePath: "/group")
        XCTAssertEqual(SyncLedgerStore.url(forStoreAt: group.appending(path: "HITList.store")).path, "/group/HITList.ledger")
        XCTAssertEqual(SyncLedgerStore.url(forStoreAt: group.appending(path: "HITList-s141.store")).path, "/group/HITList-s141.ledger",
                       "a side store has a ledger of its own")
        XCTAssertNil(SyncLedgerStore.forAppStore(storeURL: group.appending(path: "HITList.store"), storeInMemory: true).url,
                     "an app store in memory has its ledger in memory")
        XCTAssertNil(SyncLedgerStore.forAppStore(storeURL: nil, storeInMemory: false).url)
    }

    func testTheLedgersSchemaIsItsOwnAndNotSynced() throws {
        let ledger = SyncLedgerStore.open(at: folder.appending(path: "HITList.ledger"))
        let names = Set(SyncLedgerStore.schema.entities.map(\.name))
        XCTAssertTrue(names.isDisjoint(with: Set(HITListSchema.schema.entities.map(\.name))))
        XCTAssertTrue(names.isDisjoint(with: Set(HITListSchema.models.map { "\($0)" })))
        for configuration in ledger.container.configurations {
            XCTAssertNil(configuration.cloudKitContainerIdentifier, "never mirrored to CloudKit")
        }
    }

    // MARK: - What it keeps

    func testEntriesDeferredRecordsAndFactsAreKept() async throws {
        let ledger = SyncLedgerStore.inMemory()
        var write = LedgerWrite()
        write.upsert = [entry(1), entry(2), LedgerEntry(key: key(3))]
        write.deferUpsert = [cloud(7)]
        write.facts = [LedgerFact.firstFetchDone: Data([1]), LedgerFact.account: Data("acct".utf8)]
        try await ledger.write(write)

        let entries = try await ledger.entries()
        XCTAssertEqual(entries, [entry(1), entry(2), LedgerEntry(key: key(3))])
        let deferred = try await ledger.deferred()
        XCTAssertEqual(deferred, [cloud(7)])
        let fetched = try await ledger.fact(LedgerFact.firstFetchDone)
        XCTAssertEqual(fetched, Data([1]))

        // Replaced by key; removed; a nil fact forgotten; a key upserted and removed in one write is removed.
        var next = LedgerWrite()
        var changed = entry(1)
        changed.deletedHereAt = Date(timeIntervalSince1970: 5)
        next.upsert = [changed, entry(4)]
        next.remove = [key(2), key(4)]
        next.deferRemove = [key(7)]
        next.deferUpsert = [cloud(8)]
        next.facts = [LedgerFact.account: nil]
        try await ledger.write(next)
        let after = try await ledger.entries()
        XCTAssertEqual(after, [changed, LedgerEntry(key: key(3))])
        let deferredAfter = try await ledger.deferred()
        XCTAssertEqual(deferredAfter, [cloud(8)])
        let account = try await ledger.fact(LedgerFact.account)
        XCTAssertNil(account)
        let first = try await ledger.fact(LedgerFact.firstFetchDone)
        XCTAssertEqual(first, Data([1]))
    }

    /// `write` is one transaction: a write that fails half way (its entries made, its deferred records and facts not
    /// yet) leaves nothing of itself, and what was there before is untouched.
    /// The sync review's finding 6: a row this build cannot read (a newer build's, after a tester went back; a
    /// damaged one) is forgotten and the rest is read, instead of the engine stopping at every launch for good.
    func testARowThatCannotBeReadIsForgottenAndTheRestIsRead() async throws {
        let ledger = SyncLedgerStore.inMemory()
        var write = LedgerWrite()
        write.upsert = [entry(1), entry(2)]
        write.deferUpsert = [cloud(7), cloud(8)]
        try await ledger.write(write)
        try await ledger.spoilForTests(entry: key(1), deferred: key(7))

        let entries = try await ledger.entries()
        XCTAssertEqual(entries, [entry(2)], "the unreadable entry is gone, the other is read")
        let deferred = try await ledger.deferred()
        XCTAssertEqual(deferred, [cloud(8)])
        let unreadable = await ledger.unreadable
        XCTAssertEqual(unreadable.count, 2, "said, for the sync log")
        // The forgotten entry's record must come again from iCloud (an item not here is settled only when its
        // record arrives): the brain's own fact asks for everything again at its next start.
        let refetch = try await ledger.fact(SyncLedgerStore.refetchFact)
        XCTAssertEqual(refetch, Data([1]))
        // Forgotten for good: the next read is clean, and the key can be written again.
        let again = try await ledger.entries()
        XCTAssertEqual(again, [entry(2)])
        var back = LedgerWrite()
        back.upsert = [entry(1)]
        try await ledger.write(back)
        let whole = try await ledger.entries()
        XCTAssertEqual(whole, [entry(1), entry(2)])
    }

    func testAWriteThatFailsHalfWayLeavesNothing() async throws {
        let ledger = SyncLedgerStore.open(at: folder.appending(path: "HITList.ledger"))
        var first = LedgerWrite()
        first.upsert = [entry(1)]
        first.facts = [LedgerFact.firstFetchDone: Data([1])]
        try await ledger.write(first)

        await ledger.failNextWriteHalfWayThrough()
        var broken = LedgerWrite()
        var changed = entry(1)
        changed.system = Data("newer".utf8)
        broken.upsert = [changed, entry(2)]
        broken.remove = []
        broken.deferUpsert = [cloud(3)]
        broken.facts = [LedgerFact.firstFetchDone: nil, LedgerFact.transport: Data("bookmark".utf8)]
        do {
            try await ledger.write(broken)
            XCTFail("the write must throw")
        } catch is SyncLedgerStore.HalfWayFailure {}

        let entries = try await ledger.entries()
        XCTAssertEqual(entries, [entry(1)], "neither the change nor the new entry")
        let deferred = try await ledger.deferred()
        XCTAssertEqual(deferred, [])
        let done = try await ledger.fact(LedgerFact.firstFetchDone)
        XCTAssertEqual(done, Data([1]))
        let state = await ledger.loadTransportState()
        XCTAssertNil(state)

        // And the next write is whole again.
        try await ledger.write(broken)
        let whole = try await ledger.entries()
        XCTAssertEqual(whole, [changed, entry(2)])
    }

    func testResetForgetsEverythingTheTransportsStateAmongIt() async throws {
        let ledger = SyncLedgerStore.inMemory()
        var write = LedgerWrite()
        write.upsert = [entry(1)]
        write.deferUpsert = [cloud(1)]
        write.facts = [LedgerFact.hold: Data("x".utf8)]
        try await ledger.write(write)
        await ledger.saveTransportState(Data("bookmark".utf8))
        try await ledger.reset()
        let entries = try await ledger.entries()
        let deferred = try await ledger.deferred()
        let hold = try await ledger.fact(LedgerFact.hold)
        let state = await ledger.loadTransportState()
        XCTAssertEqual(entries, [])
        XCTAssertEqual(deferred, [])
        XCTAssertNil(hold)
        XCTAssertNil(state)
    }

    /// The transport's state is on disk when `saveTransportState` returns: a ledger opened afresh on the same file
    /// reads it, with the entries written before it.
    func testTheTransportsStateIsOnDiskWhenItsSaveReturns() async throws {
        let url = folder.appending(path: "HITList.ledger")
        do {
            let ledger = SyncLedgerStore.open(at: url)
            var write = LedgerWrite()
            write.upsert = [entry(1)]
            try await ledger.write(write)
            await ledger.saveTransportState(Data("bookmark 1".utf8))
            await ledger.saveTransportState(Data("bookmark 2".utf8))
        }
        let reopened = SyncLedgerStore.open(at: url)
        XCTAssertNil(reopened.movedAside)
        let state = await reopened.loadTransportState()
        XCTAssertEqual(state, Data("bookmark 2".utf8))
        let entries = try await reopened.entries()
        XCTAssertEqual(entries, [entry(1)])
        await reopened.saveTransportState(nil)
        let cleared = await reopened.loadTransportState()
        XCTAssertNil(cleared)
    }

    /// A ledger file that cannot be opened is moved aside, never deleted, and an empty ledger is used in its place.
    func testAnUnreadableLedgerFileIsMovedAsideAndAnEmptyLedgerIsUsed() async throws {
        let url = folder.appending(path: "HITList.ledger")
        let garbage = Data(repeating: 0x5A, count: 8_192)
        try garbage.write(to: url)
        let ledger = SyncLedgerStore.open(at: url)
        let aside = try XCTUnwrap(ledger.movedAside, "moved aside")
        XCTAssertEqual(try Data(contentsOf: aside), garbage, "kept as it was")
        XCTAssertTrue(aside.lastPathComponent.hasPrefix("HITList.ledger.unreadable-"))
        XCTAssertEqual(ledger.url, url, "a new ledger file in its place")

        let entries = try await ledger.entries()
        XCTAssertEqual(entries, [])
        var write = LedgerWrite()
        write.upsert = [entry(1)]
        try await ledger.write(write)
        let after = try await ledger.entries()
        XCTAssertEqual(after, [entry(1)])
    }

    // MARK: - Which store file

    /// A store file's identity is its Core Data store UUID: what a saved row's `PersistentIdentifier` names, kept
    /// when the file is reopened, new when Reset local cache moves the file aside and an empty store is made.
    func testAStoreFilesIdentityIsItsStoreUUIDAndANewFileHasANewOne() throws {
        let url = folder.appending(path: "HITList.store")
        XCTAssertNil(SyncLedgerStore.storeIdentity(at: url), "no file, no identity")
        var first: String?
        do {
            let opened = ModelContainerFactory.open(schema: HITListSchema.schema, url: url, useCloudKit: false)
            let context = ModelContext(opened.container)
            let task = TaskItem(title: "t")
            context.insert(task)
            try context.save()
            first = SyncLedgerStore.storeIdentity(at: url)
            XCTAssertNotNil(first)
            XCTAssertEqual(task.persistentModelID.storeIdentifier, first, "the UUID a row's identifier carries")
        }
        do {
            _ = ModelContainerFactory.open(schema: HITListSchema.schema, url: url, useCloudKit: false)
            XCTAssertEqual(SyncLedgerStore.storeIdentity(at: url), first, "the same file keeps it")
        }
        XCTAssertNotNil(try ModelContainerFactory.trashStore(at: url, into: folder.appending(path: "Trash")))
        _ = ModelContainerFactory.open(schema: HITListSchema.schema, url: url, useCloudKit: false)
        let second = try XCTUnwrap(SyncLedgerStore.storeIdentity(at: url))
        XCTAssertNotEqual(second, first, "a new store file is another store")
    }

    func testALedgerWrittenForAnotherStoreIsForgottenWhenBound() async throws {
        let ledger = SyncLedgerStore.inMemory()
        let first = try await ledger.bind(toStore: "A")
        XCTAssertFalse(first, "an empty ledger is simply bound")
        var write = LedgerWrite()
        write.upsert = [entry(1)]
        write.facts = [LedgerFact.firstFetchDone: Data([1])]
        try await ledger.write(write)
        await ledger.saveTransportState(Data("bookmark".utf8))

        let same = try await ledger.bind(toStore: "A")
        XCTAssertFalse(same)
        let kept = try await ledger.entries()
        XCTAssertEqual(kept, [entry(1)])

        let other = try await ledger.bind(toStore: "B")
        XCTAssertTrue(other, "reset: the transport must be reset too")
        let entries = try await ledger.entries()
        let done = try await ledger.fact(LedgerFact.firstFetchDone)
        let state = await ledger.loadTransportState()
        let bound = try await ledger.fact(SyncLedgerStore.storeFact)
        XCTAssertEqual(entries, [])
        XCTAssertNil(done)
        XCTAssertNil(state)
        XCTAssertEqual(bound, Data("B".utf8))

        // A ledger with something in it and no store named (written before binding existed) is forgotten too.
        let unbound = SyncLedgerStore.inMemory()
        try await unbound.write(write)
        let reset = try await unbound.bind(toStore: "A")
        XCTAssertTrue(reset)
    }

    // MARK: - Size

    func testFiveThousandEntriesWrittenAndReadBack() async throws {
        let ledger = SyncLedgerStore.open(at: folder.appending(path: "HITList.ledger"))
        var write = LedgerWrite()
        write.upsert = (0..<5_000).map(entry)
        let clock = ContinuousClock()
        let written = try await clock.measure { try await ledger.write(write) }
        var entries: [LedgerEntry] = []
        let read = try await clock.measure { entries = try await ledger.entries() }
        XCTAssertEqual(entries.count, 5_000)
        XCTAssertEqual(entries, write.upsert.sorted { $0.key < $1.key })

        var again = LedgerWrite()
        again.upsert = (0..<5_000).map { n -> LedgerEntry in
            var e = entry(n)
            e.system = Data("next \(n)".utf8)
            return e
        }
        let rewritten = try await clock.measure { try await ledger.write(again) }
        var one = LedgerWrite()
        one.upsert = [entry(42)]
        let single = try await clock.measure { try await ledger.write(one) }
        print("141 ledger: 5,000 entries written \(written), read \(read), all 5,000 replaced \(rewritten), one replaced among 5,000 \(single)")
        XCTAssertLessThan(written, .seconds(30))
        XCTAssertLessThan(read, .seconds(30))
    }
}
