import XCTest
@testable import HITListCore

// The brain (`SyncCore`) on the rig (`SyncSimulation`, `FakeCloud`): several devices, random people's actions, every
// fault, and the invariants I1 to I9 checked once everyone has synced (`dev/SYNC-ENGINE.md` section 9).
//
// What runs in `swift test`: every kept seed, and a fixed spread of short runs across the fault sets.
//
// The long runs are a command (release build; the debug build is about seven times slower):
//
//   cd HITListCore && HITLIST_SIM_SEEDS=1000 HITLIST_SIM_STEPS=300 [HITLIST_SIM_FAULTS=everyday] [HITLIST_SIM_FIRST=1] \
//     DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     swift test -c release -Xswiftc -enable-testing --filter SyncCoreSimulationTests/testManySeeds
//
// `HITLIST_SIM_FAULTS` is one of `SyncCoreSimulationTests.faultSets` (everyday, ledger, zone, memory, account, quota,
// refusal, purge, all). It prints, for the report: seeds run, steps, records made, saves accepted, conflicts settled,
// crashes ridden out, and every finding with its seed.
//
// One seed traced:
//
//   HITLIST_SIM_TRACE=<seed> HITLIST_SIM_KEYS=<record-name prefixes or words> [HITLIST_SIM_FAULTS=…] [HITLIST_SIM_STEPS=…] \
//     swift test -c release -Xswiftc -enable-testing --filter SyncCoreSimulationTests/testTrace
//
// prints the script's lines for those keys and every fault, the brain's log lines that name them, and the rig's notes.

/// The app's side of the brain, as the rig's devices have it: the backup always succeeds (unless told to fail), and
/// what the brain says is counted.
final class SimHost: SyncHost, @unchecked Sendable {
    private let lock = NSLock()
    private var backupReasons: [SyncRemovalReason] = []
    private var failing = false

    var backups: [SyncRemovalReason] {
        lock.lock()
        defer { lock.unlock() }
        return backupReasons
    }

    func failBackups(_ fail: Bool) {
        lock.lock()
        failing = fail
        lock.unlock()
    }

    func willRemoveLocalData(reason: SyncRemovalReason) async throws {
        let fail: Bool = lock.withLock {
            backupReasons.append(reason)
            return failing
        }
        if fail { throw SimHostError.backupFailed }
    }

    func didWrite(_ keys: Set<SyncKey>) {}
    func didAccept(_ keys: Set<SyncKey>) {}
    func statusDidChange(_ status: SyncStatus) {}

    enum SimHostError: Error { case backupFailed }
}

/// `SyncCore` as the rig's `SimBrain`. One per launch of a device; the host is held here because the brain holds its
/// host weakly. The person's answers to the brain's questions are the rig's: a device held for a mass deletion is
/// answered "I deleted them" (in the rig every deletion is a person's own), and a purge is answered as `purgeAnswer`
/// says.
struct SyncCoreSimBrain: SimBrain {
    let core: SyncCore
    let host: SimHost
    let purgeAnswer: @Sendable (String) -> PurgeAnswer
    let device: String

    init(_ parts: SimParts, purgeAnswer: @escaping @Sendable (String) -> PurgeAnswer = { _ in .keepAndSendAgain }) {
        host = SimHost()
        device = parts.device
        self.purgeAnswer = purgeAnswer
        // Each line says which device and when (the rig's clock, as the script's lines do).
        let log = parts.log, name = parts.device, clock = parts.clock
        core = SyncCore(store: parts.store, ledger: parts.ledger, transport: parts.transport, host: host,
                        clock: parts.clock.function, log: { log("\(name) @\(clock.millis) \($0)") })
    }

    static let make: SimBrainFactory = { parts in SyncCoreSimBrain(parts) }

    func start() async throws {
        await core.start()
        try await answerQuestions()
    }

    func stop() async { await core.stop() }

    func localChanged(_ keys: Set<SyncKey>?) async throws {
        await core.localChanged(keys)
        try await answerQuestions()
    }

    func syncNow() async throws {
        try await answerQuestions()
        try await core.syncNow()
        try await answerQuestions()
    }

    /// What a person answers when the brain asks.
    private func answerQuestions() async throws {
        switch await core.status.hold {
        case .massDeletion?: try await core.confirmDeletions()
        case .zonePurged?: try await core.answer(purgeAnswer(device))
        default: break
        }
    }
}

/// The run's numbers, for the report.
struct SimTally: CustomStringConvertible {
    var seeds = 0
    var steps = 0
    var recordsMade = 0
    var savesAccepted = 0
    var removalsAccepted = 0
    var conflictsSettled = 0
    var crashes = 0
    var failing: [(UInt64, [SyncFinding])] = []

    var description: String {
        "\(seeds) seeds, \(steps) steps, \(recordsMade) records made, \(savesAccepted) saves accepted, "
            + "\(removalsAccepted) removed for good, \(conflictsSettled) conflicts settled, \(crashes) crashes ridden out, "
            + "\(failing.reduce(0) { $0 + $1.1.count }) findings on \(failing.count) seeds"
            + (failing.isEmpty ? "" : " \(failing.map(\.0))")
    }
}

/// Counts the brain's lines that say a conflict was settled (T6), across every device of a run.
final class LineCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var conflicts = 0
    private var kept: [String] = []
    private let keys: [String]

    init(keys: [String] = []) { self.keys = keys }

    func take(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if line.hasSuffix("(T6); settled again") { conflicts += 1 }
        if !keys.isEmpty, keys.contains(where: { line.contains($0) }) { kept.append(line) }
    }

    var conflictCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return conflicts
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return kept
    }
}

final class SyncCoreSimulationTests: XCTestCase {
    // MARK: The fault sets

    /// The fault sets a run draws from, by name (`HITLIST_SIM_FAULTS`). "everyday" are those a correct engine rides out
    /// with every invariant holding; the others add what changes what "correct" means.
    static func config(_ faults: String) -> SimConfig {
        var config = SimConfig()
        switch faults {
        case "ledger": config.faults = SimFaultKind.everyday.union([.ledgerLost]); config.faultPercent = 10
        case "zone": config.faults = SimFaultKind.everyday.union([.zoneDeleted, .zoneReset]); config.faultPercent = 10
        case "memory": config.faults = SimFaultKind.everyday.union([.ledgerLost, .zoneDeleted, .zoneReset])
        case "account": config.faults = SimFaultKind.everyday.union([.accountSwitch, .signOut]); config.faultPercent = 10
        case "quota": config.faults = SimFaultKind.everyday.union([.quotaFull]); config.faultPercent = 10
        case "refusal": config.faults = SimFaultKind.everyday.union([.refusal]); config.faultPercent = 10
        case "conflict": config.faults = SimFaultKind.everyday.union([.sendByItself]); config.faultPercent = 15
        case "all": config.faults = Set(SimFaultKind.allCases); config.faultPercent = 10
        default: break
        }
        return config
    }

    static let faultSets = ["everyday", "conflict", "ledger", "zone", "memory", "account", "quota", "refusal", "all"]

    /// One random run with the brain under test, its numbers added to `tally`.
    static func run(seed: UInt64, steps: Int, faults: String, devices: Int = 3, keys: [String] = [],
                    tally: inout SimTally) async -> SimReport {
        var config = Self.config(faults)
        let counter = LineCounter(keys: keys)
        config.log = { counter.take($0) }
        let sim = SyncSimulation(seed: seed, config: config, brain: SyncCoreSimBrain.make)
        for index in 0..<devices { await sim.addDevice(SyncSimulation.name(index)) }
        await sim.runRandom(steps: steps)
        let findings = await sim.check()
        let report = SimReport(seed: seed, devices: devices, steps: steps, findings: findings, script: await sim.script,
                               notes: await sim.notes)
        tally.seeds += 1
        tally.steps += steps
        tally.recordsMade += Set(await sim.intent.events.compactMap { event -> SyncKey? in
            if case .made = event.change { return event.key } else { return nil }
        }).count
        tally.savesAccepted += await sim.cloud.acceptedSaves
        tally.removalsAccepted += await sim.cloud.acceptedRemovals
        tally.conflictsSettled += counter.conflictCount
        tally.crashes += report.notes.filter { $0.contains("crashed at step") }.count
        if !findings.isEmpty { tally.failing.append((seed, findings)) }
        return report
    }

    // MARK: Kept seeds

    struct KeptSeed {
        var seed: UInt64
        var steps = 300
        var faults = "everyday"
        var keys: [String]
        var found: String
    }

    /// Every seed that ever found something, with `SyncCore`: the rig's own (session 140's, `SyncInvariantsTests`) and
    /// this session's.
    static var keptSeeds: [KeptSeed] {
        var seeds = SyncInvariantsTests.keptSeeds.map {
            KeptSeed(seed: $0.seed, steps: $0.steps, faults: $0.faults, keys: $0.keys, found: $0.found)
        }
        seeds += [
            KeptSeed(seed: 39, keys: ["78621E8F", "54468498"],
                     found: "open in wave 1: I9 with the test brain (a task sent without a label while the label was re-sent)"),
            KeptSeed(seed: 34, faults: "memory", keys: ["9DB28ABA", "C4499ED9", "37A1A87E"],
                     found: "open in wave 1: I2 under lost memories, an extra label honoured (the test brain)"),
            // Brief 145's own (62, 4, 16 of the list above also found, with SyncCore, the rig missing a lost memory when
            // unsent deletions were kept as entries with no base).
            KeptSeed(seed: 27, faults: "conflict", keys: ["8200F2DC", "DC462D6C", "02628CC7"],
                     found: "I9 judged an M5 decided in the exposure but sent a step after it (rig)"),
            KeptSeed(seed: 100, faults: "conflict", keys: ["C2352F8C", "5C2A5735"],
                     found: "the same as 27 with conflicts (rig)"),
            KeptSeed(seed: 93, faults: "memory", keys: ["3F49A6D4", "B004951A", "4EEC2C9C"],
                     found: "brain: a person's unsent move to a Group whose deletion arrived was dropped; the base's older Group came back"),
            KeptSeed(seed: 79, faults: "conflict", keys: ["03755E0F", "13B58FC9", "B83108A4"],
                     found: "brain (review finding 1's first fix): a grandchild arriving in the same fetch under a sub-task that goes kept the parent's deletion stale; devices kept a task iCloud held deleted"),
        ]
        return seeds
    }

    func testKeptSeeds() async {
        var tally = SimTally()
        for kept in Self.keptSeeds {
            let report = await Self.run(seed: kept.seed, steps: kept.steps, faults: kept.faults, tally: &tally)
            XCTAssertEqual(report.findings, [], "seed \(kept.seed) (\(kept.faults)), which found: \(kept.found)\n\(report.description)")
        }
        print("SyncCore, kept seeds: \(tally)")
    }

    // MARK: The rig's model, corrected on what SyncCore does

    /// Seed 62 (everyday) and 16 (memory): a device whose transport lost its state while a deletion of its own was
    /// still to go forgets its memory but keeps that deletion as an entry with no base (section 7). The rig counted a
    /// lost memory only when the ledger held no entry at all, so edits made up to the device's merge without a memory
    /// were judged by I2 although M5 may keep the other side whole.
    func testTheRigCountsALostMemoryWhenOnlyUnsentDeletionsAreKept() async {
        let sim = SyncSimulation(seed: 1, brain: SyncCoreSimBrain.make)
        await sim.addDevice("A")
        await sim.addDevice("B")
        let t1 = SyncRecord(type: "TaskItem", name: "T1", fields: ["title": .string("one")])
        let t2 = SyncRecord(type: "TaskItem", name: "T2", fields: ["title": .string("two")])
        await sim.play([.act("A", .put(t1)), .act("A", .put(t2)), .sync("A"), .sync("B"), .sync("A"),
                        .fault("B", .network(up: false)), .act("B", .delete(t2.key)),
                        .relaunch("B", keepLedger: true, keepTransportState: false),
                        .fault("B", .network(up: true)), .sync("B")])
        let marker = await sim.cloud.record(t2.key)
        XCTAssertEqual(marker?.record.isDeleted, true, "B kept its unsent deletion across the loss and sent it")
        let amnesia = await sim.intent.amnesia
        XCTAssertTrue(amnesia.contains { $0.device == "B" }, "the rig saw B's memory lost: \(amnesia)")
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    // MARK: Fixes in the brain, each by a script of its own

    static func task(_ name: String, _ title: String, _ more: [String: SyncValue] = [:]) -> SyncRecord {
        SyncRecord(type: "TaskItem", name: name, fields: ["title": .string(title)].merging(more) { _, new in new })
    }

    static func group(_ name: String) -> SyncRecord {
        SyncRecord(type: "Project", name: name, fields: ["name": .string("Group \(name)")])
    }

    /// Two devices that agree on `records`.
    static func twoDevices(_ records: [SyncRecord]) async -> SyncSimulation {
        var config = SimConfig()
        // HITLIST_SIM_DEBUG=1 prints the brains' lines of these scripts.
        if ProcessInfo.processInfo.environment["HITLIST_SIM_DEBUG"] != nil { config.log = { print("BRAIN \($0)") } }
        let sim = SyncSimulation(seed: 1, config: config, brain: SyncCoreSimBrain.make)
        await sim.addDevice("A")
        await sim.addDevice("B")
        await sim.play(records.map { .act("A", .put($0)) } + [.sync("A"), .sync("B"), .sync("A")])
        return sim
    }

    func held(_ sim: SyncSimulation, _ device: String, _ name: String) async -> SyncRecord? {
        await sim.device(device)?.store.record(SyncKey(type: "TaskItem", name: name))
    }

    /// Review finding 1 (146), the supervisor's rule: a sub-task made on B under a task A had deleted stays (it was
    /// made after the deletion); before, the store's cascade took it with its parent and nothing remembered it.
    func testFinding1_aSubTaskMadeUnderATaskDeletedElsewhereStays() async {
        let sim = await Self.twoDevices([Self.task("P", "parent")])
        await sim.play([.advance(milliseconds: 10), .act("A", .delete(SyncKey(type: "TaskItem", name: "P"))), .sync("A"),
                        .advance(milliseconds: 10), .act("B", .put(Self.task("C", "made after", ["parent": .reference("P")]))),
                        .sync("B"), .sync("A"), .sync("B")])
        for device in ["A", "B"] {
            let child = await held(sim, device, "C")
            XCTAssertNotNil(child, "C on \(device)")
            XCTAssertNil(child?["parent"], "C is a task of its own on \(device)")
            let parent = await held(sim, device, "P")
            XCTAssertNil(parent, "P stays deleted on \(device)")
        }
        let inCloud = await sim.cloud.record(SyncKey(type: "TaskItem", name: "C"))
        XCTAssertEqual(inCloud?.record.isDeleted, false)
        XCTAssertEqual(inCloud?.record["parent"], .reference("P"), "iCloud keeps the reference (section 8)")
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    /// Review finding 1: a task moved under P on B after A deleted P stays, on every device (before, it was deleted on
    /// B with P and its marker then deleted it everywhere).
    func testFinding1_aTaskMovedUnderATaskDeletedElsewhereStaysEverywhere() async {
        let sim = await Self.twoDevices([Self.task("P", "parent"), Self.task("C", "moved")])
        await sim.play([.advance(milliseconds: 10), .act("A", .delete(SyncKey(type: "TaskItem", name: "P"))), .sync("A"),
                        .advance(milliseconds: 10), .act("B", .edit(SyncKey(type: "TaskItem", name: "C"), ["parent": .reference("P")])),
                        .sync("B"), .sync("A"), .sync("B")])
        for device in ["A", "B"] {
            let child = await held(sim, device, "C")
            XCTAssertNotNil(child, "C on \(device)")
        }
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    /// Review finding 1: a sub-task B changed after A deleted its parent stays, whichever of the two markers (P's,
    /// and C's own from A's cascade) reaches B first. A sub-task nobody changed goes with its parent.
    func testFinding1_aSubTaskChangedAfterItsParentWasDeletedStays_andAnUnchangedOneGoes() async {
        let sim = await Self.twoDevices([Self.task("P", "parent"), Self.task("C", "child", ["parent": .reference("P")]),
                                         Self.task("U", "unchanged child", ["parent": .reference("P")])])
        await sim.play([.advance(milliseconds: 10), .act("A", .delete(SyncKey(type: "TaskItem", name: "P"))), .sync("A"),
                        .advance(milliseconds: 10), .act("B", .edit(SyncKey(type: "TaskItem", name: "C"), ["title": .string("changed after")])),
                        .sync("B"), .sync("A"), .sync("B")])
        for device in ["A", "B"] {
            let child = await held(sim, device, "C")
            XCTAssertEqual(child?["title"], .string("changed after"), "C on \(device)")
            let unchanged = await held(sim, device, "U")
            XCTAssertNil(unchanged, "U went with P on \(device)")
        }
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    /// Brief 145, memory seed 93: B's person moved a task to Group G2 and, before B sent it, G2's deletion arrived (the
    /// store took the reference off); the task then waited for its old Group G1 (deleted too) from the base, and when
    /// G1 was put back the task went back into it everywhere. A person's own change to the field is sent (section 8):
    /// the task keeps G2 in its whole record, and G1's return does not move it.
    func testAPersonsUnsentMoveToAGroupWhoseDeletionArrivesIsKept_notTheBasesOlderGroup() async {
        let g1 = Self.group("G1"), g2 = Self.group("G2")
        let sim = await Self.twoDevices([g1, g2, Self.task("T", "task", ["project": .reference("G1")])])
        let t = SyncKey(type: "TaskItem", name: "T")
        await sim.play([.advance(milliseconds: 10), .act("A", .delete(g1.key)), .act("A", .delete(g2.key)), .sync("A"),
                        .advance(milliseconds: 10), .act("B", .edit(t, ["project": .reference("G2")])),
                        .sync("B"),
                        .advance(milliseconds: 10), .act("A", .put(g1)), .sync("A"), .sync("B"), .sync("A")])
        for device in ["A", "B"] {
            let task = await held(sim, device, "T")
            XCTAssertNil(task?["project"], "T is in no Group on \(device): G2 is gone and G1 is not where the person put it")
        }
        let inCloud = await sim.cloud.record(t)
        XCTAssertEqual(inCloud?.record["project"], .reference("G2"), "the person's move went to iCloud")
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    // MARK: M5's amendment: a send with no base whose answer was lost (zone seed 270, memory seed 259)

    /// A plays out: A makes T and sends it; iCloud takes it, and A dies before the answer (no base for T on A). B gets
    /// T and changes one field and sends; A changes `field` of T. Then A syncs.
    func lostAnswer(_ field: String, on b: String) async -> SyncSimulation {
        var config = SimConfig()
        if ProcessInfo.processInfo.environment["HITLIST_SIM_DEBUG"] != nil { config.log = { print("BRAIN \($0)") } }
        let sim = SyncSimulation(seed: 1, config: config, brain: SyncCoreSimBrain.make)
        await sim.addDevice("A")
        await sim.addDevice("B")
        let t = SyncKey(type: "TaskItem", name: "T")
        await sim.play([.sync("A"), .sync("B"),
                        .act("A", .put(Self.task("T", "first"))), .fault("A", .crash(.beforeSent)), .sync("A"),
                        .advance(milliseconds: 10), .sync("B"), .act("B", .edit(t, [b: .string("B's")])), .sync("B"),
                        .advance(milliseconds: 10), .act("A", .edit(t, [field: .string("A's")])), .sync("A"), .sync("B")])
        return sim
    }

    /// Before: A's meeting with B's version had no base (M5) and kept the later record whole: B's notes were lost.
    func testALostAnswerLeavesARememberedSend_anEditOnEachSideOfDifferentFieldsBothSurvive() async {
        let sim = await lostAnswer("title", on: "notes")
        for device in ["A", "B"] {
            let t = await held(sim, device, "T")
            XCTAssertEqual(t?["title"], .string("A's"), "A's title on \(device)")
            XCTAssertEqual(t?["notes"], .string("B's"), "B's notes on \(device)")
        }
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
        let fact = try? await sim.device("A")?.ledger.fact(SyncCore.sentFact(SyncKey(type: "TaskItem", name: "T")))
        XCTAssertNil(fact ?? nil, "forgotten once a base landed")
    }

    /// The same field changed on both sides: the later change wins (lastWriter), as with a base.
    func testALostAnswerWithTheSameFieldChangedOnBothSides_theLaterWins() async {
        let sim = await lostAnswer("title", on: "title")
        for device in ["A", "B"] {
            let t = await held(sim, device, "T")
            XCTAssertEqual(t?["title"], .string("A's"), "A changed it last, on \(device)")
        }
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    /// A remembered send that never reached iCloud: a seeded filter (a fixed key) made on both devices, B's in iCloud
    /// first, A's save refused (a conflict) and that answer lost. A remembers its own version, which iCloud never took,
    /// and settles B's against it: iCloud's record wins every field A did not change after its send; a field A changed
    /// after it is A's. Both devices end with the same record.
    func testARememberedSendThatNeverReachedIcloudMeetingAnotherDevicesRecord_converges() async {
        var config = SimConfig()
        if ProcessInfo.processInfo.environment["HITLIST_SIM_DEBUG"] != nil { config.log = { print("BRAIN \($0)") } }
        let sim = SyncSimulation(seed: 1, config: config, brain: SyncCoreSimBrain.make)
        await sim.addDevice("A")
        await sim.addDevice("B")
        let filter = SyncKey(type: "SavedFilter", name: "SEEDED")
        func seeded(_ name: String, _ query: String) -> SyncRecord {
            SyncRecord(key: filter, fields: ["name": .string(name), "query": .string(query)])
        }
        await sim.play([.sync("A"), .sync("B"),
                        .act("B", .put(seeded("Today", "today"))), .sync("B"),
                        .advance(milliseconds: 10), .act("A", .put(seeded("Today (A)", "today | overdue"))),
                        .fault("A", .loseNextResponse), .sendByItself("A"),
                        .advance(milliseconds: 10), .act("A", .edit(filter, ["name": .string("A's later name")])),
                        .sync("A"), .sync("B"), .sync("A")])
        let a = await sim.device("A")?.store.record(filter)
        let b = await sim.device("B")?.store.record(filter)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a?["name"], .string("A's later name"), "changed on A after its send")
        XCTAssertEqual(a?["query"], .string("today"), "iCloud's: A did not change it after the send iCloud never took")
        let findings = await sim.check()
        XCTAssertEqual(findings.filter { $0.invariant != .noLostEdit }, [], "I2 does not judge an item made on two devices")
    }

    /// The remembered record is on disk before the send: the network drops after `recordToSend` answered and before
    /// the save left, the app is quit and launched again; the next send goes, its answer lands, the fact is forgotten.
    func testARememberedSendIsWrittenBeforeTheRecordGoes_andForgottenWhenTheAnswerLands() async {
        let sim = SyncSimulation(seed: 1, brain: SyncCoreSimBrain.make)
        await sim.addDevice("A")
        let t = SyncKey(type: "TaskItem", name: "T")
        await sim.play([.sync("A"), .act("A", .put(Self.task("T", "first"))),
                        .fault("A", .dropNetwork(after: 0)), .sendByItself("A")])
        let fact = try? await sim.device("A")?.ledger.fact(SyncCore.sentFact(t))
        XCTAssertNotNil(fact ?? nil, "written before the record was handed over")
        let inCloud = await sim.cloud.record(t)
        XCTAssertNil(inCloud, "the save never left")
        await sim.play([.relaunch("A"), .fault("A", .network(up: true)), .sync("A")])
        let after = try? await sim.device("A")?.ledger.fact(SyncCore.sentFact(t))
        XCTAssertNil(after ?? nil, "forgotten when the answer landed")
        let sent = await sim.cloud.record(t)
        XCTAssertEqual(sent?.record["title"], .string("first"))
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    // MARK: Beside the surface (the supervisor's three additions): a vouch, "download them again", refusals apart

    /// One device that synced `count` tasks (T00…), its brain called directly (the rig's person does not answer).
    func oneDevice(_ count: Int) async -> (SyncSimulation, SyncCore) {
        let sim = SyncSimulation(seed: 1, brain: SyncCoreSimBrain.make)
        await sim.addDevice("A")
        let puts: [SimStep] = (0..<count).map { .act("A", .put(Self.task(String(format: "T%02d", $0), "task \($0)"))) }
        await sim.play(puts + [.sync("A"), .sync("A")])
        let brain = await sim.device("A")?.brain as? SyncCoreSimBrain
        return (sim, brain!.core)
    }

    func keys(_ range: Range<Int>) -> Set<SyncKey> {
        Set(range.map { SyncKey(type: "TaskItem", name: String(format: "T%02d", $0)) })
    }

    func testVouchedDeletionsDoNotCountTowardTheGuard_undoingAnImport() async throws {
        let (sim, core) = await oneDevice(40)
        let gone = keys(0..<30)
        await core.vouchForDeletions(gone)
        for key in gone { await sim.device("A")?.store.delete(key) }
        await core.localChanged(gone)
        let status = await core.status
        XCTAssertNil(status.hold, "30 of 40, vouched for: ordinary deletions")
        try await core.syncNow()
        let alive = await sim.cloud.records().filter { !$0.record.isDeleted && $0.key.type == "TaskItem" }.count
        XCTAssertEqual(alive, 10)
    }

    func testAVouchCoversOnlyItsKeys_othersStillCount() async {
        let (sim, core) = await oneDevice(30)
        await core.vouchForDeletions(keys(0..<10))
        for key in keys(0..<25) { await sim.device("A")?.store.delete(key) }
        await core.localChanged(nil)
        let hold = await core.status.hold
        XCTAssertEqual(hold, .massDeletion(15), "15 unvouched of the 20 not vouched for")
    }

    func testAVouchLapsesWhenAWholeCompareFindsTheItemsStillHere() async {
        let (sim, core) = await oneDevice(12)
        await core.vouchForDeletions(keys(0..<10))
        await core.localChanged(nil)
        let fact = try? await sim.device("A")?.ledger.fact(SyncCore.vouchedFact)
        XCTAssertNil(fact ?? nil, "lapsed")
        for key in keys(0..<10) { await sim.device("A")?.store.delete(key) }
        await core.localChanged(nil)
        let hold = await core.status.hold
        XCTAssertEqual(hold, .massDeletion(10))
    }

    func testAVouchNeverLiftsAHoldAlreadyStanding() async {
        let (sim, core) = await oneDevice(12)
        for key in keys(0..<10) { await sim.device("A")?.store.delete(key) }
        await core.localChanged(nil)
        await core.vouchForDeletions(keys(0..<10))
        await core.localChanged(nil)
        let hold = await core.status.hold
        XCTAssertEqual(hold, .massDeletion(10))
    }

    func testDownloadThemAgain_theMissingItemsComeBackFromIcloudAndNothingIsDeletedThere() async throws {
        let (sim, core) = await oneDevice(12)
        for key in keys(0..<10) { await sim.device("A")?.store.delete(key) }
        await sim.device("A")?.store.put(Self.task("NEW", "made while the store read wrong"))
        await core.localChanged(nil)
        let held = await core.status.hold
        XCTAssertEqual(held, .massDeletion(10))
        try await core.restoreFromICloud()
        try await core.syncNow()
        let status = await core.status
        XCTAssertNil(status.hold)
        let here = try await sim.device("A")?.store.records().count
        XCTAssertEqual(here, 13, "the 10 back from iCloud, the 2 kept, the new one")
        let alive = await sim.cloud.records().filter { !$0.record.isDeleted && $0.key.type == "TaskItem" }.count
        XCTAssertEqual(alive, 13, "nothing deleted in iCloud; the new one went up")
        do {
            try await core.restoreFromICloud()
            XCTFail("not asking any more")
        } catch {
            XCTAssertEqual(error as? SyncCoreError, .noQuestion)
        }
    }

    func testARefusalIsApartFromErrors_andTheBoltStaysHollow() async {
        let sim = SyncSimulation(seed: 1, brain: SyncCoreSimBrain.make)
        await sim.addDevice("A")
        let key = SyncKey(type: "TaskItem", name: "BIG")
        await sim.play([.sync("A"), .act("A", .put(Self.task("BIG", "too large"))), .cloud(.refuseNextSave(key, .tooLarge)),
                        .sync("A")])
        let core = (await sim.device("A")?.brain as? SyncCoreSimBrain)!.core
        let status = await core.status
        XCTAssertEqual(status.refused, [key])
        XCTAssertNotNil(status.refusal)
        XCTAssertNil(status.lastError, "a refusal for good is not a passing error")
        XCTAssertFalse(status.isSynced)
        let built = SyncStatus(state: .idle, waiting: 0, firstFetchDone: true, lastFetchEnded: nil, lastSendEnded: nil,
                               lastError: nil, refused: [])
        XCTAssertNil(built.refusal, "the initialiser stays source-compatible")
        XCTAssertTrue(built.isSynced)
    }

    // MARK: Long runs, when asked for

    func testManySeeds_whenAskedFor() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let count = environment["HITLIST_SIM_SEEDS"].flatMap(UInt64.init), count > 0 else {
            throw XCTSkip("set HITLIST_SIM_SEEDS to run many seeds")
        }
        let first = environment["HITLIST_SIM_FIRST"].flatMap(UInt64.init) ?? 1
        let steps = environment["HITLIST_SIM_STEPS"].flatMap(Int.init) ?? 300
        let faults = environment["HITLIST_SIM_FAULTS"] ?? "everyday"
        var tally = SimTally()
        for seed in first..<(first + count) {
            let report = await Self.run(seed: seed, steps: steps, faults: faults, tally: &tally)
            if !report.findings.isEmpty { print(report.description) }
        }
        print("SyncCore, \(faults) faults, seeds \(first)…\(first + count - 1) × \(steps) steps: \(tally)")
        XCTAssertEqual(tally.failing.map(\.0), [])
    }

    func testTrace_whenAskedFor() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let seed = environment["HITLIST_SIM_TRACE"].flatMap(UInt64.init) else {
            throw XCTSkip("set HITLIST_SIM_TRACE to a seed")
        }
        let keys = (environment["HITLIST_SIM_KEYS"] ?? "").split(separator: ",").map(String.init)
        let steps = environment["HITLIST_SIM_STEPS"].flatMap(Int.init) ?? 300
        let faults = environment["HITLIST_SIM_FAULTS"] ?? "everyday"
        var config = Self.config(faults)
        let counter = LineCounter(keys: keys.isEmpty ? [""] : keys)
        config.log = { counter.take($0) }
        let sim = SyncSimulation(seed: seed, config: config, brain: SyncCoreSimBrain.make)
        for index in 0..<3 { await sim.addDevice(SyncSimulation.name(index)) }
        await sim.runRandom(steps: steps)
        let findings = await sim.check()
        // The brain's lines under the step they came in (the clock moves only between steps), then the end's.
        func millis(_ line: Substring) -> Int64? {
            guard let at = line.firstIndex(of: "@") else { return nil }
            return Int64(line[line.index(after: at)...].prefix { $0.isNumber })
        }
        var brain = counter.lines[...]
        for line in await sim.script {
            let shown = keys.contains(where: { line.contains($0) }) || line.contains("fault") || line.contains("relaunch")
                || line.contains("iCloud") || line.contains("by itself")
            let at = millis(line[...])
            var said: [String] = []
            while let next = brain.first, let when = millis(next[...]), let at, when <= at {
                said.append(next)
                brain = brain.dropFirst()
            }
            if shown || !said.isEmpty { print("SCRIPT \(line)") }
            for line in said { print("    BRAIN \(line)") }
        }
        for line in brain { print("END BRAIN \(line)") }
        for line in await sim.notes { print("NOTE \(line)") }
        for finding in findings { print("FINDING \(finding)") }
    }
}
