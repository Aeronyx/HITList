import Foundation
import XCTest
@testable import HITListCore

/// What an independent review of the brain found (round 28), each pinned by a test.
final class SyncCoreReviewTests: XCTestCase {
    func synced(_ records: [SyncRecord], account: String = "alice") async -> Device {
        let device = Device(records)
        await device.transport.setStartEvents([.account(.signedIn(current: account))])
        return await device.started(fetching: records.map { cloud($0) } + [meta()])
    }

    /// Another device deleted a task and then moved its sub-task out; this device learns of the deletion in one
    /// batch and of the move in a later one. The store takes the sub-task with the task: that is iCloud's deletion,
    /// not the person's, and it carries that deletion's time, so the later move wins (M8) and nothing is lost.
    func testASubTaskTakenWithATaskDeletedInICloudCarriesThatDeletionsTime() async {
        let device = await synced([task("P", "Parent"), task("X", "Sub", parent: "P"), project("Q", "Other")])
        device.clock.advance(1_000)
        await device.transport.deliver(.willFetch)
        await device.transport.deliver(.fetched(changed: [cloud(.marker(taskKey("P"), deletedAt: epoch.addingTimeInterval(400)), "c2")],
                                                removed: []))
        let gone = await device.item(taskKey("X"))
        XCTAssertNil(gone, "the store took it with its parent")
        let entry = await device.entry(taskKey("X"))
        XCTAssertEqual(entry?.deletedHereAt, epoch.addingTimeInterval(400), "the parent's deletion time, not now")
        var moved = task("X", "Sub", updated: 500)
        moved["parent"] = nil
        await device.transport.deliver(.fetched(changed: [cloud(moved, "c3")], removed: []))
        await device.transport.deliver(.didFetch(error: nil))
        let back = await device.item(taskKey("X"))
        XCTAssertEqual(back?["title"], .string("Sub"), "moved out after the deletion: it comes back here")
        let pending = await device.pending()
        XCTAssertEqual(pending, [], "no marker at 'now' to beat the move")
    }

    func testTheMetaAcceptedLeavesNothingWaiting() async throws {
        let device = Device([])
        await device.core.start()
        await device.deliverFetch([])
        let before = await device.status().waiting
        XCTAssertEqual(before, 1)
        try await device.transport.send()
        let status = await device.status()
        XCTAssertEqual(status.waiting, 0)
        XCTAssertTrue(status.isSynced)
    }

    func testARefusalRemembersTheVersionRefusedSoANewerChangeGoes() async {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["notes": .string(String(repeating: "x", count: 50))])
        await device.core.localChanged([taskKey("A")])
        let refusedVersion = await device.core.recordToSend(taskKey("A"))
        XCTAssertNotNil(refusedVersion)
        // The person shortens the note while the big one is on its way; iCloud refuses the big one.
        await device.store.edit(taskKey("A"), ["notes": .string("short")])
        await device.transport.deliver(.sent(saved: [], removed: [], failed: [taskKey("A"): .tooLarge]))
        await device.core.localChanged([taskKey("A")])
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))], "the newer version goes")
    }

    func testAFailedBackupOnASwitchIsTriedAgainOnResume() async throws {
        let device = await synced([task("A", "Milk")], account: "alice")
        device.host.backupError = TestHost.BackupFailed()
        await device.transport.deliver(.account(.switched(previous: "alice", current: "bob")))
        let held = await device.status()
        XCTAssertEqual(held.state, .held(.noAccount))
        let a = await device.item(taskKey("A"))
        XCTAssertNotNil(a, "nothing removed")
        device.host.backupError = nil
        await device.core.resume()
        XCTAssertEqual(device.host.backups, [.accountSwitched, .accountSwitched])
        let removed = await device.item(taskKey("A"))
        XCTAssertNil(removed)
        let owner = try await device.ledger.fact(LedgerFact.account)
        XCTAssertEqual(owner, Data("bob".utf8))
        let status = await device.status()
        XCTAssertNil(status.hold)
    }

    func testAFailedBackupOnASwitchIsTriedAgainAtTheNextStart() async throws {
        let device = await synced([task("A", "Milk")], account: "alice")
        device.host.backupError = TestHost.BackupFailed()
        await device.transport.deliver(.account(.switched(previous: "alice", current: "bob")))
        let relaunched = device.relaunched(transport: ScriptedTransport())
        relaunched.host.backupError = nil
        await relaunched.core.start()
        XCTAssertEqual(relaunched.host.backups, [.accountSwitched])
        let status = await relaunched.status()
        XCTAssertNil(status.hold)
        let owner = try await relaunched.ledger.fact(LedgerFact.account)
        XCTAssertEqual(owner, Data("bob".utf8))
    }

    func testASignInTheLedgerCouldNotTakeIsTakenOnResume() async throws {
        let device = await synced([task("A", "Milk")])
        await device.transport.deliver(.account(.signedOut(previous: "alice")))
        await device.ledger.failNext()
        await device.transport.deliver(.account(.signedIn(current: "alice")))
        let failed = await device.status()
        guard case .failed? = failed.hold else { return XCTFail("\(failed)") }
        await device.core.resume()
        let status = await device.status()
        XCTAssertNil(status.hold, "signed in, not held for an account")
        let stored = try await device.ledger.fact(LedgerFact.hold)
        XCTAssertNil(stored)
    }

    func testAFailureOverAStoredHoldLiftsBackToThatHold() async {
        let device = await synced([task("A", "Milk")])
        await device.transport.deliver(.zoneLost(.purged))
        // A failure lands while the purge's question stands.
        await device.ledger.failNext()
        await device.transport.deliver(.account(.signedIn(current: "alice")))
        let failed = await device.status()
        guard case .failed? = failed.hold else { return XCTFail("\(failed)") }
        await device.core.resume()
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.zonePurged), "still asking")
    }

    /// A device whose clock runs behind still deletes what it held: the deletion is never stamped before the
    /// version it deletes.
    func testADeletionIsNeverStampedBeforeTheVersionItDeletes() async throws {
        let device = await synced([task("A", "Milk", updated: 600), task("B", "Bread")])
        // This device's clock reads epoch: ten minutes behind the version it holds.
        await device.store.delete(taskKey("A"))
        await device.core.localChanged([taskKey("A")])
        let entry = await device.entry(taskKey("A"))
        XCTAssertEqual(entry?.deletedHereAt, epoch.addingTimeInterval(600))
        let record = await device.core.recordToSend(taskKey("A"))
        XCTAssertEqual(record?.record, .marker(taskKey("A"), deletedAt: epoch.addingTimeInterval(600)))
    }

    /// A fetch that meets an item gone before any compare noticed it: the deletion's time is on disk before the
    /// merge reads it, so the marker is the same however many times it is asked for, across a relaunch too.
    func testADeletionMetByAFetchIsOnDiskBeforeItIsSettledOrSent() async throws {
        let device = await synced([task("A", "Milk"), task("B", "Bread"), task("C", "Cheese")])
        device.clock.advance(1_000)
        await device.store.delete(taskKey("A"))   // no compare yet
        await device.deliverFetch([cloud(task("A", "Milk", updated: 10), "c2")])
        let entry = await device.entry(taskKey("A"))
        XCTAssertEqual(entry?.deletedHereAt, epoch.addingTimeInterval(1_000), "written before the merge")
        XCTAssertEqual(entry?.system, token("c2"))
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
        let first = await device.core.recordToSend(taskKey("A"))
        device.clock.advance(60)
        let second = await device.core.recordToSend(taskKey("A"))
        XCTAssertEqual(first?.record, second?.record)
        let relaunched = device.relaunched(transport: ScriptedTransport())
        await relaunched.transport.setStartEvents([])
        await relaunched.core.start()
        let third = await relaunched.core.recordToSend(taskKey("A"))
        XCTAssertEqual(third?.record, first?.record)
        XCTAssertEqual(first?.record, .marker(taskKey("A"), deletedAt: epoch.addingTimeInterval(1_000)))
    }

    func testANewerFormatIsWorkedOutAgainFromTheMetaAtStart() async throws {
        let device = await synced([task("A", "Milk")])
        // The newer meta reached the ledger, and the hold's fact did not (a crash in between).
        var write = LedgerWrite()
        write.upsert = [LedgerEntry(key: SyncCore.metaKey, base: meta(SyncSchema.formatVersion + 1).record, system: token("m9"))]
        try await device.ledger.write(write)
        let relaunched = device.relaunched(transport: ScriptedTransport())
        await relaunched.core.start()
        let status = await relaunched.status()
        XCTAssertEqual(status.state, .held(.needsUpdate))
    }
}
