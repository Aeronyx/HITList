import XCTest
@testable import HITListCore

// `RecordMerge` by property (`dev/SYNC-ENGINE.md` section 9.1): records of every type made by a seeded generator,
// and small worlds of two devices and an iCloud that edit, delete, make again and sync in random orders on one clock.
// Every failure prints the seed of its case; `SYNC_PROPERTY_SEED=<n> swift test --filter RecordMergePropertyTests`
// runs from another master seed.

/// SplitMix64: small, fast, and the same numbers on every machine for a seed.
struct SyncRandom: RandomNumberGenerator {
    private(set) var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }
    mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }
}

/// Records of every synced type, with values drawn from small pools so that sides often agree by chance.
struct SyncRecordGenerator {
    var rng: SyncRandom

    static let strings = ["", "a", "b", "Milk", "Oat milk ✓"]
    static let blobs = [Data([1]), Data([2, 2]), Data([3, 3, 3])]
    static let names = ["R1", "R2", "R3"]
    static let labels = ["L1", "L2", "L3", "L4"]

    static func key(_ type: SyncType) -> SyncKey {
        SyncKey(type: type.name, name: type.singleton ?? "6B1F3E2A-0000-4000-8000-0000000000AA")
    }

    /// The fields a person changes: not `updatedAt`, `createdAt` or a clock (those are stamped).
    static func content(_ type: SyncType) -> [SyncField] {
        let clocks = RecordMerge.clockKeys(type)
        return type.fields.filter {
            $0.key != SyncSchema.updatedAt && $0.key != "createdAt" && !clocks.contains($0.key)
        }
    }

    mutating func value(_ field: SyncField) -> SyncValue? {
        if field.required == nil, rng.chance(0.3) { return nil }
        switch field.kind {
        case .string: return .string(rng.pick(Self.strings))
        case .int: return .int(Int64(rng.int(0...4)))
        case .bool: return .bool(rng.chance(0.5))
        case .date: return MergeFixture.ms(Int64(rng.int(0...3)) * 1000)
        case .data: return .data(rng.pick(Self.blobs))
        case .reference: return .reference(rng.pick(Self.names))
        case .references:
            var set: [String] = []
            for label in Self.labels where rng.chance(0.4) { set.append(label) }
            return set.isEmpty ? nil : .references(set)
        }
    }

    /// A new item as a device saves it at `t`.
    mutating func record(_ type: SyncType, at t: Int64) -> SyncRecord {
        var record = SyncRecord(key: Self.key(type))
        for field in Self.content(type) {
            record[field.key] = value(field)
            if case .clock(let clock) = field.merge, rng.chance(0.7) { record[clock] = MergeFixture.ms(t) }
        }
        record["createdAt"] = MergeFixture.ms(t)
        record[SyncSchema.updatedAt] = MergeFixture.ms(t)
        return SyncSchema.filled(record)
    }

    /// A person's change at `t`: one to three fields; a field with a clock stamps its clock; `touch` moves
    /// `updatedAt` (some of the app's writes do not: the day anchoring, a board's clock moving its switches).
    mutating func edit(_ record: SyncRecord, at t: Int64, touch: Bool) -> SyncRecord {
        let fields = Self.content(SyncSchema.type(record.key.type)!)
        var out = record
        for _ in 0..<rng.int(1...3) {
            let field = rng.pick(fields)
            out[field.key] = value(field)
            if case .clock(let clock) = field.merge { out[clock] = MergeFixture.ms(t) }
        }
        if touch { out[SyncSchema.updatedAt] = MergeFixture.ms(t) }
        return SyncSchema.filled(out)
    }

    /// Any record of `type` with stamps anywhere in 0...40: no clock agrees with any other.
    mutating func arbitrary(_ type: SyncType) -> SyncRecord {
        var record = self.record(type, at: Int64(rng.int(0...40)))
        record[SyncSchema.updatedAt] = rng.chance(0.05) ? nil : MergeFixture.ms(Int64(rng.int(0...40)))
        for clock in RecordMerge.clockKeys(type) {
            record[clock] = rng.chance(0.3) ? nil : MergeFixture.ms(Int64(rng.int(0...40)))
        }
        return record
    }

    mutating func arbitrarySide(_ type: SyncType) -> SyncRecord? {
        switch rng.int(0...3) {
        case 0: return nil
        case 1: return .marker(Self.key(type), deletedAt: MergeFixture.at(Int64(rng.int(0...40))))
        default: return arbitrary(type)
        }
    }
}

/// Two (or more) devices and iCloud on one clock: what a device does, and a sync as `SyncCore` will make it (merge,
/// write the device, send the result if it differs from iCloud's, the base becomes iCloud's). Every merge is checked
/// for the properties that hold one merge at a time; the caller checks the end.
struct SyncWorld {
    struct Device {
        var local: SyncRecord?
        var base: SyncRecord?
        var deletedHereAt: Int64?
        var lastHeld: SyncRecord?
    }

    var cloud: SyncRecord?
    var devices: [Device]
    var now: Int64 = 0
    /// The latest deletion of the item on any device, and the latest edit or making again.
    var lastDeletion: Int64?
    var lastLife: Int64?
    /// A deletion was made while another device held the item made again and not yet sent (see
    /// `testLimitAMakeAgainNotYetSentOutlivesALaterDeletionElsewhere`).
    var revivalRace = false
    /// What happened, in order; words only when a test fails (building strings at every step is most of the time a
    /// debug build spends here).
    enum Step { case edit(Int64, Int, Bool), delete(Int64, Int), makeAgain(Int64, Int), sync(Int64, Int, String, Bool) }
    var steps: [Step] = []
    var trace: [String] {
        steps.map { step in
            switch step {
            case .edit(let t, let i, let touch): return "\(t) dev\(i) edit\(touch ? "" : " (no stamp)")"
            case .delete(let t, let i): return "\(t) dev\(i) delete"
            case .makeAgain(let t, let i): return "\(t) dev\(i) make again"
            case .sync(let t, let i, let rule, let changed): return "\(t) dev\(i) sync \(rule)\(changed ? "" : " (quiet)")"
            }
        }
    }
    var problems: [String] = []
    var merges = 0

    init(cloud: SyncRecord?, devices: [Device]) {
        self.cloud = cloud
        self.devices = devices
    }

    // MARK: What a person does

    mutating func edit(_ i: Int, _ gen: inout SyncRecordGenerator, touch: Bool) {
        guard let local = devices[i].local else { return }
        let edited = gen.edit(local, at: now, touch: touch)
        devices[i].local = edited
        devices[i].lastHeld = edited
        lastLife = now
        steps.append(.edit(now, i, touch))
    }

    mutating func delete(_ i: Int) {
        guard let local = devices[i].local else { return }
        devices[i].lastHeld = local
        devices[i].local = nil
        // `SyncCore` notices on the save's hint, at once: the time the marker will carry. Only a deletion of an item
        // this device last agreed iCloud holds leaves a marker of its own; one of an item made here (or made again
        // here) and not yet sent leaves nothing behind, and is not counted as a deletion below.
        if devices[i].base?.isDeleted == false {
            devices[i].deletedHereAt = now
            lastDeletion = now
            // Another device holds the item made again and not yet sent (M12 lets it stand whatever its dates).
            for (j, other) in devices.enumerated() where j != i && other.base?.isDeleted == true && other.local != nil {
                revivalRace = true
            }
        } else {
            devices[i].deletedHereAt = nil
        }
        steps.append(.delete(now, i))
    }

    /// An undo or an import: the item back with every field and date it had.
    mutating func makeAgain(_ i: Int) {
        guard devices[i].local == nil, let held = devices[i].lastHeld else { return }
        devices[i].local = held
        devices[i].deletedHereAt = nil
        lastLife = now
        steps.append(.makeAgain(now, i))
    }

    // MARK: A sync

    /// Returns whether anything was written or sent.
    @discardableResult
    mutating func sync(_ i: Int) -> Bool {
        let device = devices[i]
        let input = MergeInput(base: device.base, local: device.local,
                               deletedHereAt: device.deletedHereAt.map(MergeFixture.at),
                               server: cloud, now: MergeFixture.at(now))
        let outcome = RecordMerge.merge(input)
        merges += 1
        check(input, outcome, device: i)

        var changed = false
        if !RecordMerge.same(outcome.device, device.local) {
            devices[i].local = outcome.device
            if let written = outcome.device { devices[i].lastHeld = written }
            changed = true
        }
        if !RecordMerge.same(outcome.merged, cloud) {
            if outcome.merged == nil { problems.append("dev\(i): a nil result over iCloud's \(String(describing: cloud))") }
            cloud = outcome.merged
            changed = true
        }
        devices[i].base = RecordMerge.normal(cloud)?.comparable
        devices[i].deletedHereAt = nil
        steps.append(.sync(now, i, outcome.rule.rawValue, changed))
        return changed
    }

    /// Syncs each device in turn until a whole round changes nothing; returns the rounds that changed something.
    mutating func settle(order: [Int], limit: Int = 6) -> Int {
        for round in 0..<limit {
            var changed = false
            for i in order {
                now += 1
                if sync(i) { changed = true }
            }
            if !changed { return round }
        }
        problems.append("not settled after \(limit) rounds")
        return limit
    }

    // MARK: Properties of one merge

    private mutating func check(_ input: MergeInput, _ outcome: MergeOutcome, device i: Int) {
        // Merging twice changes nothing: with the result as the base and on both sides, the result is itself.
        let merged = RecordMerge.normal(outcome.merged)
        let local = RecordMerge.normal(input.local), server = RecordMerge.normal(input.server)
        let again = RecordMerge.merge(MergeInput(base: merged?.comparable, local: outcome.device,
                                                 server: outcome.merged, now: input.now))
        if RecordMerge.normal(again.merged) != merged {
            problems.append("dev\(i): merging \(outcome.rule.rawValue)'s result again gave \(String(describing: again.merged))")
        }

        // The result's `updatedAt` is never earlier than either side's (M12 against a marker is the design's own
        // exception: made again here, whatever its dates).
        if let stamp = merged?.updatedAt {
            for side in [local, server] {
                guard let side, let sideStamp = side.updatedAt else { continue }
                if outcome.rule == .cameBackHere, side.isDeleted { continue }
                if stamp < sideStamp {
                    problems.append("dev\(i): \(outcome.rule.rawValue) ended at \(stamp.timeIntervalSince1970) before a side's \(sideStamp.timeIntervalSince1970)")
                }
            }
        }

        // A field only one side changed since the base keeps that side's value (M7).
        if outcome.rule == .threeWay, let base = RecordMerge.normal(input.base), let local, let server,
           let merged, let type = SyncSchema.type(base.key.type) {
            for field in type.fields {
                let b = base[field.key]?.comparable, l = local[field.key]?.comparable
                let s = server[field.key]?.comparable, m = merged[field.key]?.comparable
                if l != b, s == b, m != l { problems.append("dev\(i): \(field.key) changed only here was lost") }
                if s != b, l == b, m != s { problems.append("dev\(i): \(field.key) changed only there was lost") }
            }
        }
    }

    /// What a device holds for iCloud's record: the item, or nothing.
    static func held(_ record: SyncRecord?) -> SyncRecord? {
        guard let record = RecordMerge.normal(record), !record.isDeleted else { return nil }
        return record
    }
}

final class RecordMergePropertyTests: XCTestCase {
    private static let masterSeed: UInt64 = {
        if let text = ProcessInfo.processInfo.environment["SYNC_PROPERTY_SEED"], let seed = UInt64(text) { return seed }
        return 0x4849_544C_6973_7428 // "HITList("
    }()

    /// Cases per property: 21,700 in all, under ten seconds in a debug build (a world is a dozen merges and more).
    private static let cases = (twice: 10_000, oneSide: 7_000, converge: 3_500, order: 1_200)

    private func caseSeed(_ salt: UInt64, _ n: Int) -> UInt64 {
        var rng = SyncRandom(seed: Self.masterSeed ^ (salt &* 0x1000_0000_01B3) ^ UInt64(n))
        return rng.next()
    }

    private func report(_ name: String, seed: UInt64, _ world: SyncWorld, _ problems: [String]) {
        XCTFail("""
            \(name): case seed \(seed) (master \(Self.masterSeed))
            problems: \(problems.prefix(5).joined(separator: "; "))
            trace: \(world.trace.joined(separator: " | "))
            iCloud: \(String(describing: world.cloud))
            """)
    }

    // MARK: Merging twice changes nothing; one side's change is kept (arbitrary records, any clocks)

    func testMergingTwiceChangesNothingForAnyInputs() {
        var failures = 0
        for n in 0..<Self.cases.twice where failures < 3 {
            let seed = caseSeed(1, n)
            var gen = SyncRecordGenerator(rng: SyncRandom(seed: seed))
            let type = gen.rng.pick(SyncSchema.types)
            let base = gen.arbitrarySide(type)?.comparable
            let local = gen.rng.chance(0.3) ? nil : gen.arbitrary(type)
            let server = gen.arbitrarySide(type)
            let deletedHereAt = gen.rng.chance(0.5) ? MergeFixture.at(Int64(gen.rng.int(0...40))) : nil
            let first = RecordMerge.merge(MergeInput(base: base, local: local, deletedHereAt: deletedHereAt,
                                                     server: server, now: MergeFixture.at(41)))
            let again = RecordMerge.merge(MergeInput(base: RecordMerge.normal(first.merged)?.comparable,
                                                     local: first.device, server: first.merged,
                                                     now: MergeFixture.at(42)))
            if !RecordMerge.same(again.merged, first.merged) || !RecordMerge.same(again.device, first.device) {
                failures += 1
                XCTFail("case seed \(seed): \(first.rule.rawValue) then \(again.rule.rawValue): \(String(describing: first.merged)) became \(String(describing: again.merged))")
            }
        }
    }

    func testAFieldOnlyOneSideChangedKeepsThatSidesValueForAnyClocks() {
        var failures = 0
        for n in 0..<Self.cases.oneSide where failures < 3 {
            let seed = caseSeed(2, n)
            var gen = SyncRecordGenerator(rng: SyncRandom(seed: seed))
            let type = gen.rng.pick(SyncSchema.types)
            let base = gen.arbitrary(type)
            var local = base, server = base
            for field in SyncRecordGenerator.content(type) {
                if gen.rng.chance(0.3) { local[field.key] = gen.value(field) }
                if gen.rng.chance(0.3) { server[field.key] = gen.value(field) }
            }
            let stamps = RecordMerge.clockKeys(type).union([SyncSchema.updatedAt])
            for stamp in stamps {
                if gen.rng.chance(0.5) { local[stamp] = MergeFixture.ms(Int64(gen.rng.int(0...40))) }
                if gen.rng.chance(0.5) { server[stamp] = MergeFixture.ms(Int64(gen.rng.int(0...40))) }
            }
            let outcome = MergeFixture.merge(base: base, local: local, server: server)
            guard outcome.rule == .threeWay, let merged = outcome.merged,
                  let b = RecordMerge.normal(base), let l = RecordMerge.normal(local),
                  let s = RecordMerge.normal(server) else {
                failures += 1
                XCTFail("case seed \(seed): \(outcome.rule.rawValue), not M7")
                continue
            }
            // Every field but the stamps keeps the one side's change; the stamps end as the later of the two (so a
            // stamp that went back on one side, a backup restored, is not "that side's value").
            for field in SyncRecordGenerator.content(type) {
                let bv = b[field.key]?.comparable, lv = l[field.key]?.comparable
                let sv = s[field.key]?.comparable, mv = merged[field.key]?.comparable
                if (lv != bv && sv == bv && mv != lv) || (sv != bv && lv == bv && mv != sv) {
                    failures += 1
                    XCTFail("case seed \(seed): \(type.name).\(field.key) base \(String(describing: bv)) here \(String(describing: lv)) there \(String(describing: sv)) ended \(String(describing: mv))")
                }
            }
            for stamp in stamps where merged[stamp] != RecordMerge.later(l[stamp], s[stamp]) {
                failures += 1
                XCTFail("case seed \(seed): \(type.name).\(stamp) is not the later of the two")
            }
        }
    }

    // MARK: Devices on one clock

    private enum Start: CaseIterable { case synced, madeOnOne, madeOnBoth }

    private func world(_ gen: inout SyncRecordGenerator, type: SyncType, start: Start) -> (SyncWorld, SyncRecord?) {
        let original = gen.record(type, at: 0)
        switch start {
        case .synced:
            let device = SyncWorld.Device(local: original, base: original.comparable, lastHeld: original)
            return (SyncWorld(cloud: original, devices: [device, device]), original)
        case .madeOnOne:
            let device = SyncWorld.Device(local: original, lastHeld: original)
            return (SyncWorld(cloud: nil, devices: [device, SyncWorld.Device()]), nil)
        case .madeOnBoth:
            // The same key made on two devices before either synced: a seeded filter, the profile.
            let other = gen.record(type, at: 0)
            return (SyncWorld(cloud: nil, devices: [SyncWorld.Device(local: original, lastHeld: original),
                                                     SyncWorld.Device(local: other, lastHeld: other)]), nil)
        }
    }

    private func act(_ world: inout SyncWorld, _ gen: inout SyncRecordGenerator, steps: Int, syncs: Bool,
                     touch: Double, ties: Bool) {
        for _ in 0..<steps {
            world.now += Int64(ties ? gen.rng.int(0...2) : gen.rng.int(1...3))
            let i = gen.rng.int(0...(world.devices.count - 1))
            let roll = gen.rng.int(0...99)
            if syncs, roll < 35 {
                world.sync(i)
            } else if roll < 70 {
                if world.devices[i].local == nil, gen.rng.chance(0.5) { world.makeAgain(i) }
                world.edit(i, &gen, touch: gen.rng.chance(touch))
            } else if roll < 88 {
                world.delete(i)
            } else {
                world.makeAgain(i)
            }
        }
    }

    /// Two devices converge: whatever each did and in whatever order they synced, once both have settled against
    /// what iCloud then holds they hold the same record, iCloud holds it, another round sends nothing, and a third
    /// device with no base at all (holding nothing, or the record as it first was) ends with it too. A deletion
    /// nobody edited or made again after stays a deletion, on every one of them, except where another device held
    /// the item made again and not yet sent at the time (`testLimitAMakeAgainNotYetSentOutlivesALaterDeletionElsewhere`).
    func testTwoDevicesConvergeAndDeletionsStay() {
        var failures = 0
        var rounds = [Int](repeating: 0, count: 7)
        var merges = 0, deletionsChecked = 0, races = 0
        for n in 0..<Self.cases.converge where failures < 3 {
            let seed = caseSeed(3, n)
            var gen = SyncRecordGenerator(rng: SyncRandom(seed: seed))
            let type = gen.rng.pick(SyncSchema.types)
            let start = gen.rng.pick(Start.allCases)
            var (world, original) = world(&gen, type: type, start: start)
            act(&world, &gen, steps: gen.rng.int(0...10), syncs: true, touch: 0.85, ties: gen.rng.chance(0.3))
            let order = gen.rng.chance(0.5) ? [0, 1] : [1, 0]
            rounds[world.settle(order: order)] += 1
            merges += world.merges

            var problems = world.problems
            let held = SyncWorld.held(world.cloud)
            for (i, device) in world.devices.enumerated() where !RecordMerge.same(device.local, held) {
                problems.append("dev\(i) holds \(String(describing: device.local))")
            }
            var third: [(String, SyncRecord?)] = [("nothing", nil)]
            if let original { third.append(("the first version", original)) }
            for (what, local) in third {
                let outcome = RecordMerge.merge(MergeInput(base: nil, local: local, server: world.cloud,
                                                           now: MergeFixture.at(world.now + 1)))
                if !RecordMerge.same(outcome.device, held) || !RecordMerge.same(outcome.merged, world.cloud) {
                    problems.append("a third device holding \(what) ended with \(String(describing: outcome.merged))")
                }
            }
            if start != .madeOnBoth, let deleted = world.lastDeletion, deleted > (world.lastLife ?? .min) {
                if world.revivalRace {
                    races += 1
                } else {
                    deletionsChecked += 1
                    if held != nil { problems.append("deleted at \(deleted), nobody edited after, but it is back") }
                }
            }
            if !problems.isEmpty {
                failures += 1
                report("converge", seed: seed, world, problems)
            }
        }
        print("RecordMergePropertyTests converge: \(merges) merges; worlds settled after 0...6 rounds: \(rounds); "
              + "deletions that stayed: \(deletionsChecked); left out for a make-again not yet sent: \(races)")
    }

    /// The design's stronger claim (section 9.1): the result is the same whatever order two devices learn of
    /// things. From a settled start, both devices change the record apart, then reach iCloud A first or B first.
    /// Holds when every change moves `updatedAt` and no two stamps are equal; `testTheOrderDecidesATie` pins
    /// where it does not.
    func testTheResultIsTheSameWhicheverDeviceReachesICloudFirst() {
        var failures = 0
        for n in 0..<Self.cases.order where failures < 3 {
            let seed = caseSeed(4, n)
            var gen = SyncRecordGenerator(rng: SyncRandom(seed: seed))
            let type = gen.rng.pick(SyncSchema.types)
            var (world, _) = world(&gen, type: type, start: .synced)
            act(&world, &gen, steps: gen.rng.int(0...6), syncs: true, touch: 1, ties: false)
            world.settle(order: [0, 1])
            act(&world, &gen, steps: gen.rng.int(1...6), syncs: false, touch: 1, ties: false)
            var ab = world, ba = world
            ab.settle(order: [0, 1])
            ba.settle(order: [1, 0])
            var problems = ab.problems + ba.problems
            if !RecordMerge.same(ab.cloud, ba.cloud) {
                problems.append("A first: \(String(describing: ab.cloud)); B first: \(String(describing: ba.cloud))")
            }
            if !problems.isEmpty {
                failures += 1
                report("order", seed: seed, world, problems)
            }
        }
    }

    // MARK: Where a property does not hold as stated: the exact cases, pinned

    /// Where the order does decide: both sides changed one field and their records carry the same `updatedAt`
    /// (the same millisecond, or two changes that did not move it). "A tie goes to iCloud" gives the field to
    /// whichever device reached iCloud first. Both devices still end the same.
    func testTheOrderDecidesATie() {
        let base = MergeFixture.task(["title": .string("Milk")], updated: 10)
        let a = MergeFixture.task(["title": .string("Oat milk")], updated: 20)
        let b = MergeFixture.task(["title": .string("Soy milk")], updated: 20)
        func final(first: SyncRecord, second: SyncRecord) -> SyncRecord? {
            var world = SyncWorld(cloud: base, devices: [
                SyncWorld.Device(local: first, base: base.comparable),
                SyncWorld.Device(local: second, base: base.comparable),
            ])
            world.settle(order: [0, 1])
            XCTAssertTrue(world.problems.isEmpty, "\(world.problems)")
            XCTAssertTrue(RecordMerge.same(world.devices[0].local, world.devices[1].local))
            return world.cloud
        }
        XCTAssertEqual(final(first: a, second: b)?["title"], .string("Oat milk"))
        XCTAssertEqual(final(first: b, second: a)?["title"], .string("Soy milk"))
    }

    /// M12 lets an item made again here stand "whatever its dates", because a make-again (an undo, an import)
    /// keeps the item's old `updatedAt`. So when another device deletes the item after it was made again here but
    /// before this device has sent it, the make-again wins and the later deletion is undone (seed
    /// 12641660605823510791 of the first run). Pinned as the design has it; the fix needs the make-again's own
    /// moment (the report proposes stamping it).
    func testLimitAMakeAgainNotYetSentOutlivesALaterDeletionElsewhere() {
        let original = MergeFixture.task(["title": .string("Milk")], updated: 0)
        var world = SyncWorld(cloud: original, devices: [
            SyncWorld.Device(local: original, base: original.comparable, lastHeld: original),
            SyncWorld.Device(local: original, base: original.comparable, lastHeld: original),
        ])
        world.now = 1; world.delete(1)
        world.now = 3; world.sync(1)                  // M8: iCloud holds a marker at 1
        world.now = 5; world.makeAgain(1)             // undone on device 1, not sent yet
        world.now = 6; world.delete(0)                // deleted on device 0 after the undo
        world.now = 7; world.sync(0)                  // M10: a marker at 6
        world.now = 8; world.sync(1)                  // M12: made again here, whatever its dates
        world.settle(order: [0, 1])
        XCTAssertTrue(world.problems.isEmpty, "\(world.problems)")
        XCTAssertEqual(world.lastDeletion, 6)
        XCTAssertNotNil(SyncWorld.held(world.cloud), "the deletion at 6, after the undo at 5, is undone")
        XCTAssertTrue(RecordMerge.same(world.devices[0].local, world.devices[1].local))
    }

    /// A deletion leaves a marker only when this device last agreed that iCloud holds the item (`deletedHereAt` is
    /// kept only then). Made again here and deleted again before it was sent, it leaves the older marker, and an
    /// edit made elsewhere between the two deletions brings the item back (seeds 17017184225812039803 and
    /// 16457938305430570284 of the first run). Likewise an item made on two devices with one key (a seeded filter,
    /// the profile) and deleted on one before it ever reached iCloud comes back from the other.
    func testLimitADeletionOfAnItemNotYetSentLeavesNoMarker() {
        let original = MergeFixture.task(["title": .string("Milk")], updated: 0)
        var world = SyncWorld(cloud: original, devices: [
            SyncWorld.Device(local: original, base: original.comparable, lastHeld: original),
            SyncWorld.Device(local: original, base: original.comparable, lastHeld: original),
        ])
        var gen = SyncRecordGenerator(rng: SyncRandom(seed: 1))
        world.now = 3; world.delete(0)
        world.now = 8; world.sync(0)                  // a marker at 3
        world.now = 10; world.edit(1, &gen, touch: true)
        world.now = 15; world.makeAgain(0)
        world.now = 18; world.delete(0)               // gone again here: the base is the marker at 3
        world.settle(order: [1, 0])
        XCTAssertTrue(world.problems.isEmpty, "\(world.problems)")
        XCTAssertNotNil(SyncWorld.held(world.cloud), "the edit at 10 outlives the deletion at 18")

        let seeded = MergeFixture.task(["title": .string("Focus")], updated: 0)
        var twins = SyncWorld(cloud: nil, devices: [SyncWorld.Device(local: seeded, lastHeld: seeded),
                                                    SyncWorld.Device(local: seeded, lastHeld: seeded)])
        twins.now = 2; twins.delete(0)
        twins.settle(order: [0, 1])
        XCTAssertNotNil(SyncWorld.held(twins.cloud), "deleted before it ever reached iCloud: the other's copy wins")
    }
}
