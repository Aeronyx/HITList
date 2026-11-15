import Foundation
import XCTest
@testable import HITListCore

/// Two brains on two stores, wired to one tiny iCloud of these tests' own: just enough of the transport's rules
/// (T2, T3, T4, T6, T7, T8, T10 as one batch) to see that two devices end with the same items and then fall quiet.
/// The many-device simulation with every failure is `FakeCloud`'s (session 140) and wave 2's.
final class SyncCoreTwoDeviceTests: XCTestCase {
    struct Pair {
        let cloud = TinyCloud()
        let clock = TestClock()
        let one: TinyDevice
        let two: TinyDevice

        init(_ first: [SyncRecord] = [], _ second: [SyncRecord] = []) {
            one = TinyDevice(first, cloud: cloud, clock: clock)
            two = TinyDevice(second, cloud: cloud, clock: clock)
        }

        func start() async {
            await one.core.start()
            await two.core.start()
        }

        /// Both devices sync, one after the other, until a whole round sends nothing.
        func settle(file: StaticString = #filePath, line: UInt = #line) async throws {
            for _ in 0..<10 {
                let before = await cloud.saves
                try await one.core.syncNow()
                try await two.core.syncNow()
                try await one.core.syncNow()
                if await cloud.saves == before { return }
            }
            XCTFail("never fell quiet", file: file, line: line)
        }

        /// I1: both devices hold the same items, and iCloud holds exactly those.
        func assertSame(_ context: String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
            let a = try await one.store.records().map { RecordMerge.normal($0)!.comparable }
            let b = try await two.store.records().map { RecordMerge.normal($0)!.comparable }
            let there = await cloud.alive().map { RecordMerge.normal($0)!.comparable }
            XCTAssertEqual(Set(a), Set(b), "the two devices \(context)", file: file, line: line)
            XCTAssertEqual(Set(a), Set(there), "a device and iCloud \(context)", file: file, line: line)
            XCTAssertEqual(a.count, Set(a).count, file: file, line: line)
            let s1 = await one.core.status, s2 = await two.core.status
            XCTAssertTrue(s1.isSynced, "\(s1) \(context)", file: file, line: line)
            XCTAssertTrue(s2.isSynced, "\(s2) \(context)", file: file, line: line)
        }

        /// I7: another round sends nothing.
        func assertQuiet(file: StaticString = #filePath, line: UInt = #line) async throws {
            let before = await cloud.saves
            try await one.core.syncNow()
            try await two.core.syncNow()
            let after = await cloud.saves
            XCTAssertEqual(after, before, "no ping-pong", file: file, line: line)
        }
    }

    func testTwoDevicesEditingApartEndTheSame() async throws {
        let pair = Pair([project("P", "Home"), task("T", "Milk", project: "P"), task("S", "Sub", parent: "T")])
        await pair.start()
        try await pair.settle()
        try await pair.assertSame("after the first device moved over")

        pair.clock.advance(10)
        await pair.one.store.edit(taskKey("T"), ["title": .string("Oat milk"), "updatedAt": .date(pair.clock.now)])
        await pair.one.store.put(label("L", "Errand"))
        await pair.one.store.edit(taskKey("T"), ["labels": .references(["L"])])
        await pair.one.core.localChanged(nil)
        pair.clock.advance(10)
        await pair.two.store.edit(taskKey("T"), ["notes": .string("2%"), "updatedAt": .date(pair.clock.now)])
        await pair.two.store.put(label("M", "Shop"))
        await pair.two.store.edit(taskKey("T"), ["labels": .references(["M"])])
        await pair.two.store.delete(taskKey("S"))
        await pair.two.core.localChanged(nil)

        try await pair.settle()
        try await pair.assertSame("after both edited")
        let t = await pair.one.store.record(taskKey("T"))
        XCTAssertEqual(t?["title"], .string("Oat milk"))
        XCTAssertEqual(t?["notes"], .string("2%"))
        XCTAssertEqual(t?["labels"], .references(["L", "M"]))
        let s = await pair.one.store.record(taskKey("S"))
        XCTAssertNil(s, "deleted on one, untouched on the other: gone everywhere")
        try await pair.assertQuiet()
    }

    func testADeletionAgainstALaterEditElsewhere() async throws {
        // A project stays: a real store is never empty (and an empty one is held as a mass deletion).
        let pair = Pair([task("T", "Milk"), task("S", "Sub", parent: "T"), project("P", "Home")])
        await pair.start()
        try await pair.settle()
        pair.clock.advance(10)
        await pair.one.store.delete(taskKey("T"))
        await pair.one.core.localChanged(nil)
        pair.clock.advance(10)
        await pair.two.store.edit(taskKey("T"), ["title": .string("Still wanted"), "updatedAt": .date(pair.clock.now)])
        await pair.two.core.localChanged(nil)
        try await pair.settle()
        try await pair.assertSame()
        let t = await pair.one.store.record(taskKey("T"))
        XCTAssertEqual(t?["title"], .string("Still wanted"), "changed after the deletion: it comes back (M8)")
        let s = await pair.two.store.record(taskKey("S"))
        XCTAssertNil(s, "the sub-task nobody changed stays deleted (I3)")
        try await pair.assertQuiet()
    }

    func testARandomWalkOfTwoDevices() async throws {
        let seed = UInt64(Date().timeIntervalSince1970 * 1000) % 1_000_000
        try await walk(seed: seed, steps: 300)
    }

    func testRandomWalksWithFixedSeeds() async throws {
        for seed: UInt64 in [1, 2, 3, 42, 2026] { try await walk(seed: seed, steps: 200) }
    }

    /// Many more walks on request: `HITLIST_SYNC_WALKS=500 swift test --filter SyncCoreTwoDeviceTests`.
    func testManyWalksOnRequest() async throws {
        let count = Int(ProcessInfo.processInfo.environment["HITLIST_SYNC_WALKS"] ?? "") ?? 0
        for seed in 0..<UInt64(count) { try await walk(seed: 10_000 + seed, steps: 300, quiet: true) }
    }

    func walk(seed: UInt64, steps: Int, quiet: Bool = false) async throws {
        if !quiet { print("SyncCoreTwoDeviceTests walk seed \(seed)") }
        defer { if quiet, testRun?.failureCount ?? 0 > 0 { print("SyncCoreTwoDeviceTests failing walk seed \(seed)") } }
        var random = SeededRandom(seed)
        let pair = Pair([project("P0", "Home")])
        await pair.start()
        try await pair.settle()
        var made = 0
        var deleted: [SyncKey: SyncRecord] = [:]
        for _ in 0..<steps {
            pair.clock.advance(1)
            let device = random.next(2) == 0 ? pair.one : pair.two
            let tasks = try await device.store.records().filter { $0.key.type == "TaskItem" }
            let projects = try await device.store.records().filter { $0.key.type == "Project" }
            let now = SyncValue.date(pair.clock.now)
            var touched: SyncKey?
            switch random.next(10) {
            case 0, 1, 2:
                made += 1
                var record = task("T\(made)", "Task \(made)")
                record["updatedAt"] = now
                if let parent = tasks.randomElement(using: &random), random.next(3) == 0 { record["parent"] = .reference(parent.key.name) }
                if let proj = projects.randomElement(using: &random), random.next(2) == 0 { record["project"] = .reference(proj.key.name) }
                await device.store.put(record)
                touched = record.key
            case 3, 4:
                if let t = tasks.randomElement(using: &random) {
                    await device.store.edit(t.key, ["title": .string("Edited \(random.next(1000))"), "updatedAt": now])
                    touched = t.key
                }
            case 5:
                if let t = tasks.randomElement(using: &random) {
                    await device.store.edit(t.key, ["notes": .string("n\(random.next(1000))"), "updatedAt": now])
                    touched = t.key
                }
            case 6:
                if let t = tasks.randomElement(using: &random) {
                    deleted[t.key] = t
                    await device.store.delete(t.key)
                    touched = t.key
                }
            case 7:
                if let (key, record) = deleted.randomElement(using: &random), random.next(2) == 0 {
                    // An undo: the item put back, its `updatedAt` moved as the app does.
                    var back = record
                    back["updatedAt"] = now
                    back["parent"] = nil
                    await device.store.put(back)
                    deleted[key] = nil
                    touched = key
                } else if random.next(4) == 0 {
                    made += 1
                    await device.store.put(project("P\(made)", "Project \(made)", updated: 0))
                    touched = projectKey("P\(made)")
                }
            case 8:
                try await device.core.syncNow()
            default:
                if random.next(3) == 0 {
                    let other = device === pair.one ? pair.two : pair.one
                    try await other.core.syncNow()
                }
            }
            if let touched { await device.core.localChanged(random.next(4) == 0 ? nil : [touched]) }
        }
        try await pair.settle()
        try await pair.assertSame("seed \(seed)")
        try await pair.assertQuiet()
        if !quiet {
            let count = await pair.one.store.count
            print("SyncCoreTwoDeviceTests walk seed \(seed): \(made) made, \(count) items on each device at the end")
        }
    }
}

// MARK: - The tiny iCloud

/// Records by key with a version tag each, and the order they changed in. Saves are checked against the tag the
/// device last saw (T6, T7); a save writes every field the type lists and leaves any other key alone (T4).
actor TinyCloud {
    private var records: [SyncKey: (record: SyncRecord, tag: Int)] = [:]
    private var log: [(seq: Int, key: SyncKey)] = []
    private var seq = 0
    private var tags = 0
    private(set) var saves = 0

    enum Answer { case saved(CloudRecord), failed(SendFailure) }

    func alive() -> [SyncRecord] {
        records.values.map(\.record).filter { !$0.isDeleted && $0.key.type != SyncSchema.metaType }
    }

    func changes(since bookmark: Int) -> (changed: [CloudRecord], removed: [SyncKey], bookmark: Int) {
        let keys = Set(log.filter { $0.seq > bookmark }.map(\.key))
        var changed: [CloudRecord] = []
        var removed: [SyncKey] = []
        for key in keys.sorted().reversed() {
            if let held = records[key] { changed.append(CloudRecord(record: held.record, system: Self.token(held.tag))) } else { removed.append(key) }
        }
        return (changed, removed, seq)
    }

    func save(_ outgoing: OutgoingRecord) -> Answer {
        let key = outgoing.record.key
        let seen = outgoing.system.flatMap { Int(String(decoding: $0, as: UTF8.self)) }
        if let held = records[key] {
            guard seen == held.tag else { return .failed(.conflict(server: CloudRecord(record: held.record, system: Self.token(held.tag)))) }
        } else if seen != nil {
            return .failed(.unknownItem)
        }
        var stored = records[key]?.record ?? SyncRecord(key: key)
        if let type = SyncSchema.type(key.type) {
            for field in type.fields { stored.fields[field.key] = outgoing.record.fields[field.key] }
            stored.fields[SyncSchema.deletedAt] = outgoing.record.fields[SyncSchema.deletedAt]
        } else {
            stored = outgoing.record
        }
        tags += 1
        seq += 1
        saves += 1
        records[key] = (stored, tags)
        log.append((seq, key))
        return .saved(CloudRecord(record: stored, system: Self.token(tags)))
    }

    func delete(_ key: SyncKey) {
        guard records.removeValue(forKey: key) != nil else { return }
        seq += 1
        log.append((seq, key))
    }

    static func token(_ tag: Int) -> Data { Data(String(tag).utf8) }
}

/// One device's road to the tiny iCloud.
actor TinyTransport: SyncTransport {
    let cloud: TinyCloud
    private var delegate: (any SyncTransportDelegate)?
    private var list: [PendingChange] = []
    private var bookmark = 0

    init(_ cloud: TinyCloud) { self.cloud = cloud }

    func start(delegate: any SyncTransportDelegate) async { self.delegate = delegate }
    func stop() async { delegate = nil }
    func pending() async -> [PendingChange] { list }

    func add(_ changes: [PendingChange]) async {
        for change in changes where !list.contains(change) {
            list.removeAll { $0.key == change.key }
            list.append(change)
        }
    }

    func remove(_ changes: [PendingChange]) async { list.removeAll { changes.contains($0) } }

    func fetch() async throws {
        guard let delegate else { return }
        await delegate.handle(.willFetch)
        let found = await cloud.changes(since: bookmark)
        await delegate.handle(.fetched(changed: found.changed, removed: found.removed))
        bookmark = found.bookmark
        await delegate.handle(.didFetch(error: nil))
    }

    func send() async throws {
        guard let delegate else { return }
        await delegate.handle(.willSend)
        var saved: [CloudRecord] = []
        var removed: [SyncKey] = []
        var failed: [SyncKey: SendFailure] = [:]
        for change in list {
            switch change {
            case .save(let key):
                guard let outgoing = await delegate.recordToSend(key) else {
                    list.removeAll { $0 == change }
                    continue
                }
                switch await cloud.save(outgoing) {
                case .saved(let record): saved.append(record)
                case .failed(let failure): failed[key] = failure
                }
            case .delete(let key):
                await cloud.delete(key)
                removed.append(key)
            }
        }
        // The answered changes leave the list before the brain hears of them (T4).
        let answered = Set(saved.map { PendingChange.save($0.key) } + removed.map { .delete($0) })
        list.removeAll { answered.contains($0) || failed[$0.key] != nil }
        await delegate.handle(.sent(saved: saved, removed: removed, failed: failed))
        await delegate.handle(.didSend(error: nil))
    }

    func reset() async {
        list = []
        bookmark = 0
    }
}

final class TinyDevice: Sendable {
    let store: MemoryLocalStore
    let core: SyncCore

    init(_ records: [SyncRecord], cloud: TinyCloud, clock: TestClock) {
        store = MemoryLocalStore(records)
        core = SyncCore(store: store, ledger: MemoryLedger(), transport: TinyTransport(cloud), host: nil,
                        clock: { clock.now })
    }
}

/// A small seeded generator (SplitMix64), so a failing walk can be run again from its printed seed.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func next(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
}
