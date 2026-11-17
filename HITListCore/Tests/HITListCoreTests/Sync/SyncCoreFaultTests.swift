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
}
