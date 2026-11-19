import Foundation
import XCTest
@testable import HITListCore

/// The move from the mirror, as the brain sees it (round 34; written by the review that tried to lose a tester's
/// tasks, brief 171, and kept as the proof of what the move does). A device "moves" when its brain first starts with
/// an empty ledger on the store the mirror left. Changes a device makes while it is still on the mirror are made on
/// its store with its brain not running, and a deletion there is `lose` (the mirror's deletions are never written
/// down for the engine). What these hold: a copy as old as the move, merged later, brings back nothing deleted on
/// the engine since and keeps every change made since, which is why the move always merges and never takes a fresh
/// copy; and the limits a person can meet in the gap between two of their devices moving (a deletion made on the
/// device still on the mirror comes back; an item changed on both keeps the later copy whole).
final class SyncCoreMoveFromTheMirrorTests: XCTestCase {
    final class World {
        let cloud = TinyCloud()
        let clock = TestClock()
        func device(_ records: [SyncRecord]) -> TinyDevice { TinyDevice(records, cloud: cloud, clock: clock) }
        func settle(_ devices: [TinyDevice]) async throws {
            for _ in 0..<12 {
                let before = await cloud.saves
                for d in devices { try await d.core.syncNow() }
                for d in devices { try await d.core.syncNow() }
                if await cloud.saves == before { return }
            }
            XCTFail("never fell quiet")
        }
    }

    static var start: [SyncRecord] {
        [project("P", "Home"), task("A", "Pay rent", project: "P"), task("B", "Milk"), task("C", "Call mum"),
         task("D", "Dentist"), task("E", "Old idea")]
    }

    /// R3's premise ("a store with nothing of its own ... merged, [stale items and everything deleted since] would come
    /// back on every device"): a device that merges a copy as old as the move, with no ledger, against an engine that
    /// has since deleted and edited. M6 and M5 settle it: nothing deleted comes back, every edit stands.
    func testAStaleCopyOfTheMoveMergedLaterBringsNothingBack() async throws {
        let w = World()
        let first = w.device(Self.start)
        await first.core.start()
        try await w.settle([first])
        // A week on the engine.
        w.clock.advance(86_400)
        await first.store.delete(taskKey("E"))
        await first.store.edit(taskKey("B"), ["title": .string("Oat milk"), "updatedAt": .date(w.clock.now)])
        await first.core.localChanged(nil)
        try await w.settle([first])
        // A device installed fresh: the mirror's frozen zone downloaded (the copy as of the move), then an ordinary merge.
        let fresh = w.device(Self.start)
        await fresh.core.start()
        try await w.settle([first, fresh])
        let e1 = await first.store.record(taskKey("E")), e2 = await fresh.store.record(taskKey("E"))
        XCTAssertNil(e1, "deleted on the engine: stays deleted")
        XCTAssertNil(e2, "deleted on the engine: gone on the fresh device too")
        let b = await fresh.store.record(taskKey("B"))
        XCTAssertEqual(b?["title"], .string("Oat milk"), "the engine's edit stands over the stale copy")
    }

    /// Person 3, the Mac nine days later: the phone moved; the Mac kept working on the mirror. What each side did in
    /// the window, and what both end with.
    func testTheSecondDeviceNineDaysLater() async throws {
        let w = World()
        let phone = w.device(Self.start)
        await phone.core.start()
        try await w.settle([phone])
        // Day 1 to 9, the phone on the engine.
        w.clock.advance(1 * 86_400)
        await phone.store.edit(taskKey("B"), ["title": .string("Oat milk"), "updatedAt": .date(w.clock.now)])
        await phone.store.delete(taskKey("A"))
        await phone.core.localChanged(nil)
        try await w.settle([phone])
        // The Mac on the mirror the same days (its brain not running; its deletions not written down).
        let mac = w.device(Self.start)
        w.clock.advance(1 * 86_400)
        await mac.store.edit(taskKey("B"), ["notes": .string("2 litres"), "updatedAt": .date(w.clock.now)])
        await mac.store.edit(taskKey("D"), ["isCompleted": .bool(true), "completedAt": .date(w.clock.now), "updatedAt": .date(w.clock.now)])
        await mac.store.put(task("S", "Bring the lease", updated: 2 * 86_400, parent: "A"))
        await mac.store.lose(taskKey("C"))
        await mac.store.put(task("N", "New on the Mac", updated: 2 * 86_400))
        // Day 9: the Mac updates and moves.
        w.clock.advance(7 * 86_400)
        await mac.core.start()
        try await w.settle([phone, mac])
        let b = await phone.store.record(taskKey("B"))
        print("RT171 B on the phone after both:", b?["title"] as Any, b?["notes"] as Any)
        let c = await phone.store.record(taskKey("C"))
        print("RT171 C (deleted on the Mac in the window):", c == nil ? "gone" : "back")
        let a = await phone.store.record(taskKey("A")), s = await phone.store.record(taskKey("S"))
        print("RT171 A (deleted on the phone):", a == nil ? "gone" : "back", " S (made under A on the Mac):", s == nil ? "gone" : "kept, parent \(String(describing: s?["parent"]))")
        let sMac = await mac.store.record(taskKey("S"))
        print("RT171 S on the Mac:", sMac == nil ? "gone" : "kept")
        let n = await phone.store.record(taskKey("N")), d = await phone.store.record(taskKey("D"))
        print("RT171 N:", n == nil ? "missing" : "there", " D completed:", d?["isCompleted"] as Any)
        XCTAssertNotNil(s, "a sub-task made on the Mac under a task the phone deleted survives")
        XCTAssertEqual(d?["isCompleted"], .bool(true))
        XCTAssertNotNil(n)
    }

    /// Person 2 (one device) and the hidden records: what the mirror's zone holds and the device never took is not in
    /// what the device sends. Shown here as the engine's view: the device's store lacks F, so iCloud's engine zone never
    /// has it. (Nothing in core can see the mirror's zone: this pins only that the engine adds nothing of its own.)
    func testWhatTheDeviceLacksNeverReachesTheEngine() async throws {
        let w = World()
        var lacking = Self.start
        lacking.removeAll { $0.key == taskKey("E") }
        let phone = w.device(lacking)
        await phone.core.start()
        try await w.settle([phone])
        let held = await w.cloud.alive().map(\.key)
        XCTAssertFalse(held.contains(taskKey("E")))
    }

    /// The proposed fix for window deletions: a deletion taken down on the mirror (before the move) and noted by the
    /// brain at its first start. It holds, but the brain stamps it with the time it noted it, not when it was made: an
    /// edit made elsewhere after the deletion and before the move is then lost to it.
    func testADeletionTakenDownBeforeTheMove() async throws {
        let w = World()
        let phone = w.device(Self.start)
        await phone.core.start()
        try await w.settle([phone])
        let mac = w.device(Self.start)
        w.clock.advance(86_400)
        await mac.store.delete(taskKey("C")) // day 1, on the mirror, written down
        await mac.store.delete(taskKey("D")) // day 1, on the mirror, written down
        w.clock.advance(3_600)
        await phone.store.edit(taskKey("D"), ["notes": .string("moved to Friday"), "updatedAt": .date(w.clock.now)]) // after the deletion
        await phone.core.localChanged(nil)
        try await w.settle([phone])
        w.clock.advance(8 * 86_400)
        await mac.core.start()
        try await w.settle([phone, mac])
        let c = await phone.store.record(taskKey("C")), d = await phone.store.record(taskKey("D"))
        XCTAssertNil(c, "taken down before the move: stays deleted")
        print("RT171 D (deleted day 1 on the Mac, edited after on the phone):", d == nil ? "gone, the later edit lost" : "kept")
    }
}
