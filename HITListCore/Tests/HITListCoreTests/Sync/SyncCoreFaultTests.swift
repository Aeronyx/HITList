import Foundation
import XCTest
@testable import HITListCore

/// Brief 160: the engine's faults from round 32's reviews (148 on the transport, 147 on the engine on a real store),
/// each pinned by a test written before its fix.
final class SyncCoreFaultTests: XCTestCase {
    func synced(_ records: [SyncRecord]) async -> Device {
        await Device(records).started(fetching: records.map { cloud($0) } + [meta()])
    }

    func holdFact(_ device: Device) async -> SyncHold? {
        guard let data = try? await device.ledger.fact(LedgerFact.hold) else { return nil }
        return try? JSONDecoder().decode(SyncHold.self, from: data)
    }

    static let schemaWords = "Cannot create new field 'titleV2' in production schema"

    // MARK: 1. iCloud refusing the send whole holds; nothing is refused for good (148 finding 1)

    func testICloudNotReadyHoldsWithEverythingWaitingAndNothingRefused() async throws {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk")])
        await device.store.edit(taskKey("B"), ["title": .string("Rye")])
        await device.core.localChanged([taskKey("A"), taskKey("B")])
        await device.transport.setAnswer { records, _ in
            [.sent(saved: [], removed: [], failed: Dictionary(uniqueKeysWithValues: records.map {
                ($0.record.key, SendFailure.notReady(code: 12, message: Self.schemaWords))
            }))]
        }
        try await device.transport.send()
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.iCloudNotReady))
        XCTAssertEqual(status.waiting, 2, "still waiting, and counted")
        XCTAssertEqual(status.refused, [], "nothing refused for good")
        XCTAssertNil(status.refusal)
        XCTAssertFalse(status.isSynced)
        let pending = await device.pending()
        XCTAssertEqual(pending, [], "not put back while held: no loop")
        XCTAssertTrue(device.log.lines.contains { $0.contains(Self.schemaWords) }, "iCloud's own words in the log: \(device.log.lines)")
        let stored = await holdFact(device)
        XCTAssertEqual(stored, .iCloudNotReady, "kept across a relaunch")

        // A fetch still reads meanwhile.
        await device.deliverFetch([cloud(task("C", "Cheese"))])
        let c = await device.item(taskKey("C"))
        XCTAssertNotNil(c)

        // Return to the app: tried again, everything back on the list.
        await device.transport.setAnswer(nil)
        await device.core.localChanged(nil)
        let lifted = await device.status()
        XCTAssertNil(lifted.hold)
        let again = await device.pending()
        XCTAssertEqual(Set(again), [.save(taskKey("A")), .save(taskKey("B"))])
        try await device.transport.send()
        let done = await device.status()
        XCTAssertTrue(done.isSynced, "\(done)")
    }

    func testICloudNotReadyIsTriedAgainByTryAgain() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk")])
        await device.core.localChanged([taskKey("A")])
        await device.transport.setAnswer { _, _ in
            [.sent(saved: [], removed: [], failed: [taskKey("A"): .notReady(code: 10, message: "permission")])]
        }
        try await device.transport.send()
        await device.transport.setAnswer(nil)
        await device.core.resume()
        let status = await device.status()
        XCTAssertNil(status.hold)
        let pending = await device.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
    }

    func testICloudNotReadyIsStillHeldAfterARelaunchAndTheStartTriesAgain() async throws {
        let device = await synced([task("A", "Milk")])
        await device.store.edit(taskKey("A"), ["title": .string("Oat milk")])
        await device.core.localChanged([taskKey("A")])
        await device.transport.setAnswer { _, _ in
            [.sent(saved: [], removed: [], failed: [taskKey("A"): .notReady(code: 12, message: Self.schemaWords)])]
        }
        try await device.transport.send()
        let relaunched = device.relaunched(transport: ScriptedTransport())
        await relaunched.core.start()
        let status = await relaunched.status()
        XCTAssertNil(status.hold)
        let pending = await relaunched.pending()
        XCTAssertEqual(pending, [.save(taskKey("A"))])
    }

    /// The zone's own record honours a refusal like any other: refused for good, it is not put back on the list at
    /// every compare (148 finding 1: `metaFinding` ignored `refused`).
    func testTheZonesMetaRefusedForGoodIsNotSentAgainAtEveryCompare() async throws {
        let device = Device([task("A", "Milk")])
        await device.core.start()
        await device.deliverFetch([])
        await device.transport.setAnswer { records, _ in
            [.sent(saved: [], removed: [], failed: Dictionary(uniqueKeysWithValues: records.map {
                ($0.record.key, SendFailure.rejected(code: 99, message: "no"))
            }))]
        }
        try await device.transport.send()
        await device.core.localChanged(nil)
        let pending = await device.pending()
        XCTAssertFalse(pending.contains(.save(SyncCore.metaKey)), "\(pending)")
        let status = await device.status()
        XCTAssertTrue(status.refused.contains(SyncCore.metaKey))
    }

    /// The zone's own record refused because iCloud is not ready holds like any other record.
    func testTheZonesMetaNotReadyHolds() async throws {
        let device = Device([task("A", "Milk")])
        await device.core.start()
        await device.deliverFetch([])
        await device.transport.setAnswer { records, _ in
            [.sent(saved: [], removed: [], failed: Dictionary(uniqueKeysWithValues: records.map {
                ($0.record.key, SendFailure.notReady(code: 12, message: Self.schemaWords))
            }))]
        }
        try await device.transport.send()
        let status = await device.status()
        XCTAssertEqual(status.state, .held(.iCloudNotReady))
        XCTAssertEqual(status.refused, [])
        XCTAssertEqual(status.waiting, 2, "the task and the zone's record")
    }

    // MARK: 2. A deletion's note is not forgotten while its save is still committing (148 finding 3)

    /// Two quick deletes: the first save has committed (A is gone, its note written); the second save's `willSave`
    /// has written B's note and the save has not committed yet (B is still here). The first save's hint arrives: the
    /// brain notes A and must keep B's note, so that when B's save commits, B is a deletion and not missing (M14).
    func testASecondDeletionStillCommittingKeepsItsNote() async {
        let device = await synced([task("A", "Milk"), task("B", "Bread")])
        await device.store.delete(taskKey("A"))
        await device.store.writeDownDeletion(taskKey("B"))
        await device.core.localChanged([taskKey("A")])
        let told = try? await device.store.deletions()
        XCTAssertEqual(told, [taskKey("B")], "B's note is kept: its row was still here")
        // B's save commits; its hint arrives.
        await device.store.lose(taskKey("B"))
        await device.core.localChanged([taskKey("B")])
        let entry = await device.entry(taskKey("B"))
        XCTAssertNotNil(entry?.deletedHereAt, "B is a deletion written down, not missing")
        let pending = await device.pending()
        XCTAssertEqual(Set(pending), [.save(taskKey("A")), .save(taskKey("B"))])
        let outgoing = await device.core.recordToSend(taskKey("B"))
        XCTAssertEqual(outgoing?.record.isDeleted, true, "B's marker goes")
        let resets = await device.transport.resets
        XCTAssertEqual(resets, 0, "nothing was read as missing")
    }

    /// A note left for a row that is here (a save that failed and was rolled back) is cleared at the launch's whole
    /// compare, and only there.
    func testANoteForARowThatIsHereIsClearedAtTheLaunchsWholeCompare() async {
        let device = await synced([task("A", "Milk")])
        await device.store.writeDownDeletion(taskKey("A"))
        await device.core.localChanged(nil)
        let kept = try? await device.store.deletions()
        XCTAssertEqual(kept, [taskKey("A")], "not at a compare while the app runs: the save may still be committing")
        let relaunched = device.relaunched()
        await relaunched.core.start()
        let cleared = try? await relaunched.store.deletions()
        XCTAssertEqual(cleared, [], "cleared at the launch")
        let entry = await relaunched.entry(taskKey("A"))
        XCTAssertNil(entry?.deletedHereAt)
        let item = await relaunched.item(taskKey("A"))
        XCTAssertNotNil(item)
    }
}
