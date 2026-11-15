import Foundation
import XCTest
@testable import HITListCore

/// How the brain learns of a deletion on this device (`dev/SYNC-ENGINE.md` section 4, since 2026-11-15): **only from
/// the store, which writes a deletion down as it happens** (`SyncLocalStore.deletions`). An item that is merely not
/// on the device is missing, never deleted: its ledger entry is forgotten, every record is asked for again, and
/// iCloud's comes back (M14). So a store that reads empty, loses rows or is put back from a copy cannot delete
/// anything in iCloud, and there is no guard, no number and no question to the person.
final class SyncCoreDeletionTests: XCTestCase {
    func names(_ count: Int) -> [String] { (0..<count).map { String(format: "T%04d", $0) } }

    func synced(_ count: Int) async -> Device {
        let records = names(count).map { task($0, $0) }
        return await Device(records).started(fetching: records.map { cloud($0) } + [meta()])
    }

    func markersToGo(_ device: Device) async -> Int {
        let entries = (try? await device.ledger.entries()) ?? []
        return entries.filter { $0.deletedHereAt != nil }.count
    }

    // MARK: A deletion the store wrote down goes

    func testADeletionByThePersonIsNotedAndItsMarkerWaits() async {
        let device = await synced(3)
        await device.store.delete(taskKey("T0001"))
        await device.core.localChanged([taskKey("T0001")])
        let entry = await device.entry(taskKey("T0001"))
        XCTAssertNotNil(entry?.deletedHereAt, "written down in the ledger")
        let told = try? await device.store.deletions()
        XCTAssertEqual(told, [], "and the store was told it need not say it again")
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("T0001"))])
        let outgoing = await device.core.recordToSend(taskKey("T0001"))
        XCTAssertEqual(outgoing?.record.isDeleted, true, "what goes is the marker")
    }

    /// The old guard held "many gone at once" for the person to confirm. Deleting everything is now simply every
    /// deletion the person made.
    func testDeletingEverythingIsNotAQuestion() async {
        let device = await synced(300)
        for name in names(300) { await device.store.delete(taskKey(name)) }
        await device.core.localChanged(Set(names(300).map(taskKey)))
        let status = await device.status()
        XCTAssertNil(status.hold)
        XCTAssertEqual(status.waiting, 300)
    }

    func testATaskDeletedWithItsSubTasksSendsAMarkerForEach() async {
        let records = [task("P", "parent"), task("C1", "one", parent: "P"), task("C2", "two", parent: "P")]
        let device = await Device(records).started(fetching: records.map { cloud($0) } + [meta()])
        await device.store.delete(taskKey("P"))
        await device.core.localChanged([taskKey("P")])
        let waiting = await device.status().waiting
        XCTAssertEqual(waiting, 3, "the task and the two sub-tasks that went with it")
    }

    // MARK: Absence is not a deletion

    func testAnItemThatIsMerelyGoneIsNotDeletedInICloud() async {
        let device = await synced(3)
        await device.store.lose(taskKey("T0001"))
        await device.core.localChanged(nil)
        let status = await device.status()
        XCTAssertNil(status.hold)
        XCTAssertEqual(status.waiting, 0, "nothing to send: nobody deleted it")
        let marked = await markersToGo(device)
        XCTAssertEqual(marked, 0)
        let entry = await device.entry(taskKey("T0001"))
        XCTAssertNil(entry, "its entry is forgotten, so iCloud's record arrives as new")
        let resets = await device.transport.resets
        XCTAssertEqual(resets, 1, "and every record is asked for again")
        let outgoing = await device.core.recordToSend(taskKey("T0001"))
        XCTAssertNil(outgoing)
    }

    func testAMissingItemComesBackWhenICloudsRecordArrives() async {
        let device = await synced(3)
        await device.store.lose(taskKey("T0001"))
        await device.core.localChanged(nil)
        await device.deliverFetch(names(3).map { cloud(task($0, $0)) } + [meta()])
        let back = await device.item(taskKey("T0001"))
        XCTAssertNotNil(back, "restored from iCloud")
        let status = await device.status()
        XCTAssertEqual(status.waiting, 0)
        XCTAssertTrue(status.isSynced)
    }

    /// The case the old guard existed for: the app on an empty store. Nothing is deleted anywhere, nobody is asked,
    /// and everything comes back.
    func testAStoreThatReadsEmptySendsNothingAndGetsEverythingBack() async {
        let device = await synced(40)
        await device.store.loseEverything()
        await device.core.localChanged(nil)
        let status = await device.status()
        XCTAssertNil(status.hold)
        XCTAssertEqual(status.waiting, 0)
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
        await device.deliverFetch(names(40).map { cloud(task($0, $0)) } + [meta()])
        let here = await device.store.count
        XCTAssertEqual(here, 40)
    }

    /// A fetch that meets an item gone here with no deletion written down: iCloud's record is written back (M14),
    /// not answered with a marker.
    func testAFetchedChangeToAMissingItemRestoresIt() async {
        let device = await synced(2)
        await device.store.lose(taskKey("T0000"))
        await device.deliverFetch([cloud(task("T0000", "renamed elsewhere", updated: 50), "c2")])
        let back = await device.item(taskKey("T0000"))
        XCTAssertEqual(back?["title"], .string("renamed elsewhere"))
        let pending = await device.pending()
        XCTAssertEqual(pending, [], "nothing goes back")
    }

    /// An item iCloud holds that this device cannot put back (a record a broken build made, which the store has no
    /// row for) does not have everything fetched again at every compare: once, until the item has been seen here.
    func testAnItemThatCannotBePutBackIsAskedForAgainOnlyOnce() async {
        let records = names(3).map { task($0, $0) }
        let memory = MemoryLocalStore(records)
        let store = UnwritableStore(memory)
        let transport = ScriptedTransport()
        let core = SyncCore(store: store, ledger: MemoryLedger(), transport: transport, host: nil)
        await core.start()
        func fetchEverything() async {
            await transport.deliver(.willFetch)
            await transport.deliver(.fetched(changed: records.map { cloud($0) } + [meta()], removed: []))
            await transport.deliver(.didFetch(error: nil))
        }
        await fetchEverything()
        await memory.lose(taskKey("T0001"))
        await store.refuse(taskKey("T0001"))
        await core.localChanged(nil)
        var resets = await transport.resets
        XCTAssertEqual(resets, 1, "missing: every record is asked for again")
        // It arrives and cannot be written; the next compares find it missing again.
        await fetchEverything()
        await core.localChanged(nil)
        await core.localChanged(nil)
        resets = await transport.resets
        XCTAssertEqual(resets, 1, "not asked for a second time")
        let status = await core.status
        XCTAssertNil(status.hold)
        XCTAssertEqual(status.waiting, 0, "and never deleted in iCloud")
        // Once the store can hold it, it comes back, and a later loss is asked for again.
        await store.refuse(nil)
        await fetchEverything()
        let back = await memory.record(taskKey("T0001"))
        XCTAssertNotNil(back)
        await memory.lose(taskKey("T0001"))
        await core.localChanged(nil)
        resets = await transport.resets
        XCTAssertEqual(resets, 2)
    }

    // MARK: The note is kept through holds, crashes and a first sync

    func testADeletionMadeWhileHeldIsKeptForWhenTheHoldLifts() async throws {
        let device = await synced(3)
        await device.transport.deliver(.fetched(changed: [meta(SyncSchema.formatVersion + 1, "m2")], removed: []))
        let held = await device.status().hold
        XCTAssertEqual(held, .needsUpdate)
        await device.store.delete(taskKey("T0002"))
        await device.core.localChanged([taskKey("T0002")])
        let entry = await device.entry(taskKey("T0002"))
        XCTAssertNotNil(entry?.deletedHereAt, "noted although nothing is compared or sent while held")
    }

    /// The store keeps a deletion until the brain has written it down: a ledger write that fails leaves it to be
    /// told again.
    func testADeletionWhoseNoteCouldNotBeWrittenIsToldAgain() async throws {
        let device = await synced(3)
        await device.store.delete(taskKey("T0000"))
        await device.ledger.failNext()
        await device.core.localChanged([taskKey("T0000")])
        let still = try await device.store.deletions()
        XCTAssertEqual(still, [taskKey("T0000")], "the store still holds it")
        await device.core.resume()
        let entry = await device.entry(taskKey("T0000"))
        XCTAssertNotNil(entry?.deletedHereAt)
    }

    /// An item made here, sent, and deleted before any answer came (the answer was lost): the deletion is kept with
    /// no base, and when iCloud's record arrives it is answered with a marker instead of coming back.
    func testADeletionBeforeTheTwoEverAgreedIsKeptUntilAFetchShowsWhatICloudHolds() async {
        let device = await Device().started(fetching: [meta()])
        await device.store.put(task("N", "new here", updated: 10))
        await device.core.localChanged([taskKey("N")])
        await device.store.delete(taskKey("N"))
        device.clock.advance(100)
        await device.core.localChanged([taskKey("N")])
        let kept = await device.entry(taskKey("N"))
        XCTAssertNil(kept?.base)
        XCTAssertNotNil(kept?.deletedHereAt)
        // iCloud did take the save: the record arrives.
        await device.deliverFetch([cloud(task("N", "new here", updated: 10), "c1")])
        let here = await device.item(taskKey("N"))
        XCTAssertNil(here, "it does not come back")
        let outgoing = await device.core.recordToSend(taskKey("N"))
        XCTAssertEqual(outgoing?.record.isDeleted, true, "its marker goes")
    }

    /// The same when iCloud never took it: the next fetch that ends drops the note.
    func testADeletionOfAnItemICloudNeverHeldIsDroppedByTheNextFetch() async {
        let device = await Device().started(fetching: [meta()])
        await device.store.put(task("N", "new here"))
        await device.store.delete(taskKey("N"))
        await device.core.localChanged([taskKey("N")])
        await device.deliverFetch([])
        let kept = await device.entry(taskKey("N"))
        XCTAssertNil(kept)
    }

    /// Deleted and made again before the brain looked: the item is here, so there is nothing to note.
    func testAnItemDeletedAndMadeAgainIsNotADeletion() async {
        let device = await synced(2)
        await device.store.delete(taskKey("T0000"))
        await device.store.put(task("T0000", "made again", updated: 20))
        await device.core.localChanged([taskKey("T0000")])
        let entry = await device.entry(taskKey("T0000"))
        XCTAssertNil(entry?.deletedHereAt)
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("T0000"))], "it goes as the changed item it is")
    }
}

/// A store that silently writes nothing for one key (as the app's store does for a record that names no row).
actor UnwritableStore: SyncLocalStore {
    let inner: MemoryLocalStore
    private var refused: SyncKey?
    init(_ inner: MemoryLocalStore) { self.inner = inner }
    func refuse(_ key: SyncKey?) { refused = key }
    func records() async throws -> [SyncRecord] { try await inner.records() }
    func records(_ keys: Set<SyncKey>) async throws -> [SyncRecord] { try await inner.records(keys) }
    func deletions() async throws -> Set<SyncKey> { try await inner.deletions() }
    func forget(deletions: Set<SyncKey>) async throws { try await inner.forget(deletions: deletions) }
    func apply(_ writes: [LocalWrite]) async throws -> Set<SyncKey> {
        try await inner.apply(writes.filter { $0.key != refused })
    }
}
