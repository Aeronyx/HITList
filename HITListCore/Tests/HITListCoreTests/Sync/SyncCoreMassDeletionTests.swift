import Foundation
import XCTest
@testable import HITListCore

/// The guard against a store that reads wrong (`SyncHold.massDeletion`): a whole compare that finds no item here that
/// iCloud holds alive while it holds some, or at least 10 items gone that are also more than half of what iCloud holds
/// (50 and "nothing here" until review finding 2, 2026-11-15), notices
/// nothing, sends nothing, reads nothing, and holds until the person confirms or the items are back.
final class SyncCoreMassDeletionTests: XCTestCase {
    func names(_ count: Int) -> [String] { (0..<count).map { String(format: "T%04d", $0) } }

    func synced(_ count: Int) async -> Device {
        let records = names(count).map { task($0, $0) }
        return await Device(records).started(fetching: records.map { cloud($0) } + [meta()])
    }

    func delete(_ count: Int, on device: Device) async -> Set<SyncKey> {
        let keys = Set(names(count).map(taskKey))
        for key in keys { await device.store.delete(key) }
        return keys
    }

    func noticed(_ device: Device) async -> Int {
        let entries = (try? await device.ledger.entries()) ?? []
        return entries.filter { $0.deletedHereAt != nil }.count
    }

    func assertHeldWithNothingGoing(_ device: Device, _ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.massDeletion(count)), file: file, line: line)
        XCTAssertFalse(status.isSynced, file: file, line: line)
        let marked = await noticed(device)
        XCTAssertEqual(marked, 0, "no deletion noticed", file: file, line: line)
        let pending = await device.pending()
        XCTAssertEqual(pending, [], "nothing added", file: file, line: line)
        let record = await device.core.recordToSend(taskKey("T0000"))
        XCTAssertNil(record, "nothing sent", file: file, line: line)
    }

    func testAnEmptyStoreIsHeld() async {
        let device = await synced(3)
        _ = await delete(3, on: device)
        await device.core.localChanged(nil)
        await assertHeldWithNothingGoing(device, 3)
        let words = await device.status().hold?.words
        XCTAssertEqual(words, "3 items are missing from this device: nothing goes to iCloud until you confirm you deleted them")
    }

    // MARK: The guard's two conditions since 2026-11-15 (review finding 2, the supervisor's numbers: 10 and a half)

    /// Review finding 2: a store that reads empty but for one row (a seeded filter, the profile, a new task) walked
    /// round "empty": with 50 items or fewer every one was deleted everywhere. Now: no item here that the ledger holds
    /// a living base for, while it holds some, holds.
    func testAStoreHoldingOneUnrelatedRowWhileTheLedgerHasThirtyLivingBasesIsHeld() async {
        let device = await synced(30)
        _ = await delete(30, on: device)
        await device.store.put(task("Stray", "a row the ledger never heard of"))
        await device.core.localChanged(nil)
        await assertHeldWithNothingGoing(device, 30)
    }

    func testNineOfTwelveGoneIsNotHeld_underTheCount() async {
        let device = await synced(12)
        _ = await delete(9, on: device)
        await device.core.localChanged(nil)
        let status = await device.status()
        XCTAssertNil(status.hold)
        let marked = await noticed(device)
        XCTAssertEqual(marked, 9)
    }

    func testTenOfTwelveGoneIsHeld() async {
        let device = await synced(12)
        _ = await delete(10, on: device)
        await device.core.localChanged(nil)
        await assertHeldWithNothingGoing(device, 10)
    }

    func testTenOfThirtyGoneIsNotHeld_notMoreThanHalf() async {
        let device = await synced(30)
        _ = await delete(10, on: device)
        await device.core.localChanged(nil)
        let status = await device.status()
        XCTAssertNil(status.hold)
        let marked = await noticed(device)
        XCTAssertEqual(marked, 10)
    }

    func testThirtyOfFortyGoneIsHeld() async {
        let device = await synced(40)
        _ = await delete(30, on: device)
        await device.core.localChanged(nil)
        await assertHeldWithNothingGoing(device, 30)
    }

    func testFiftyOneOfAHundredGoneIsHeld() async {
        let device = await synced(100)
        _ = await delete(51, on: device)
        await device.core.localChanged(nil)
        await assertHeldWithNothingGoing(device, 51)
    }

    func testFiftyOfAHundredGoneIsNotHeld() async {
        let device = await synced(100)
        _ = await delete(50, on: device)
        await device.core.localChanged(nil)
        let status = await device.status()
        XCTAssertNil(status.hold)
        let pending = await device.pending()
        XCTAssertEqual(pending.count, 50)
        XCTAssertEqual(status.waiting, 50)
    }

    func testSixtyOfAThousandGoneIsNotHeld() async {
        let device = await synced(1_000)
        _ = await delete(60, on: device)
        await device.core.localChanged(nil)
        let status = await device.status()
        XCTAssertNil(status.hold, "more than 50, but not more than half")
        let marked = await noticed(device)
        XCTAssertEqual(marked, 60)
    }

    func testAHintThatFindsManyGoneIsMeasuredAgainstEverything() async {
        let small = await synced(100)
        let gone = await delete(51, on: small)
        await small.core.localChanged(gone)
        await assertHeldWithNothingGoing(small, 51)

        // A Group of 60 deleted out of 1,000: the hint falls back to everything, which is under half.
        let large = await synced(1_000)
        let some = await delete(60, on: large)
        await large.core.localChanged(some)
        let status = await large.status()
        XCTAssertNil(status.hold)
        let pending = await large.pending()
        XCTAssertEqual(pending.count, 60)
    }

    func testConfirmingDeletesWithTheMomentTheyWereFound() async throws {
        let device = await synced(100)
        _ = await delete(51, on: device)
        let found = device.clock.now
        await device.core.localChanged(nil)
        device.clock.advance(600)
        try await device.core.confirmDeletions()
        let status = await device.status()
        XCTAssertNil(status.hold)
        let entry = await device.entry(taskKey("T0000"))
        XCTAssertEqual(entry?.deletedHereAt, found, "the moment the compare first found them, not the confirmation")
        let pending = await device.pending()
        XCTAssertEqual(pending.count, 51)
        try await device.transport.send()
        let sent = await device.transport.sentRecords
        XCTAssertTrue(sent.allSatisfy { $0.record == .marker($0.record.key, deletedAt: found) })
        let after = await device.status()
        XCTAssertTrue(after.isSynced)

        do {
            try await device.core.confirmDeletions()
            XCTFail("nothing to confirm")
        } catch {
            XCTAssertEqual(error as? SyncCoreError, .noQuestion)
        }
    }

    func testTheItemsComingBackLiftTheHoldByItself() async {
        let device = await synced(100)
        let records = names(51).map { task($0, $0) }
        _ = await delete(51, on: device)
        await device.core.localChanged(nil)
        for record in records { await device.store.put(record) }
        await device.core.localChanged(nil)
        let status = await device.status()
        XCTAssertNil(status.hold)
        XCTAssertTrue(status.isSynced)
        let pending = await device.pending()
        XCTAssertEqual(pending, [])
        let marked = await noticed(device)
        XCTAssertEqual(marked, 0)
        XCTAssertTrue(device.log.lines.contains { $0.contains("the hold lifts by itself") })
        let seen = try? await device.ledger.fact(SyncCore.massSeenFact)
        XCTAssertNil(seen ?? nil)
    }

    func testARelaunchStaysHeldAndKeepsTheMoment() async throws {
        let device = await synced(100)
        _ = await delete(51, on: device)
        let found = device.clock.now
        await device.core.localChanged(nil)
        device.clock.advance(3_600)
        let relaunched = device.relaunched(transport: ScriptedTransport())
        await relaunched.core.start()
        let status = await relaunched.status()
        XCTAssertEqual(status.state, .held(.massDeletion(51)))
        try await relaunched.core.confirmDeletions()
        let entry = await relaunched.entry(taskKey("T0000"))
        XCTAssertEqual(entry?.deletedHereAt, found)
    }

    func testAFetchWhileHeldChangesNothingHereAndComesAgainAfter() async throws {
        let device = await synced(100)
        _ = await delete(51, on: device)
        await device.core.localChanged(nil)
        await device.deliverFetch([cloud(task("T0099", "Changed elsewhere", updated: 50), "c2")])
        let item = await device.item(taskKey("T0099"))
        XCTAssertEqual(item?["title"], .string("T0099"), "nothing written while held")
        let entry = await device.entry(taskKey("T0099"))
        XCTAssertEqual(entry?.system, token("c1"))
        try await device.core.confirmDeletions()
        let resets = await device.transport.resets
        XCTAssertEqual(resets, 1, "what was let go is fetched again")
    }

    func testAFetchForItemsTheStoreReadsAsGoneIsHeldToo() async {
        let device = await synced(100)
        _ = await delete(60, on: device)
        // No compare yet: a fetch brings new versions of the items the store no longer reads.
        let changed = names(60).map { cloud(task($0, "\($0) changed", updated: 50), "c2") }
        await device.deliverFetch(changed)
        await assertHeldWithNothingGoing(device, 60)
        let refetch = try? await device.ledger.fact(SyncCore.refetchFact)
        XCTAssertNotNil(refetch ?? nil)
    }

    func testRecordToSendNeverNoticesADeletionItself() async {
        let records = [task("A", "Milk"), project("P", "Home")]
        let device = await Device(records).started(fetching: records.map { cloud($0) } + [meta()])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk")])
        await device.core.localChanged([taskKey("A")])
        await device.store.delete(taskKey("A"))
        let record = await device.core.recordToSend(taskKey("A"))
        XCTAssertNil(record, "only the compare notices a deletion")
        await device.core.localChanged([taskKey("A")])
        let marker = await device.core.recordToSend(taskKey("A"))
        XCTAssertEqual(marker?.record.isDeleted, true)
    }

    func testTheLimitsAreTheBrainsOwnToSet() async {
        let records = names(10).map { task($0, $0) }
        let store = MemoryLocalStore(records)
        let transport = ScriptedTransport()
        let core = SyncCore(store: store, ledger: MemoryLedger(), transport: transport, host: nil,
                            limits: .init(massDeletionCount: 2, massDeletionShare: 0.25))
        await core.start()
        await transport.deliver(.willFetch)
        await transport.deliver(.fetched(changed: records.map { cloud($0) } + [meta()], removed: []))
        await transport.deliver(.didFetch(error: nil))
        for name in names(3) { await store.delete(taskKey(name)) }
        await core.localChanged(nil)
        let status = await core.status
        XCTAssertEqual(status.state, .held(.massDeletion(3)))
    }
}
