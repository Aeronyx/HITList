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
//     swift test -c release -Xswiftc -enable-testing -Xswiftc -DDEBUG --filter SyncCoreSimulationTests/testManySeeds
//
// (`-DDEBUG`: the rig is compiled into Debug builds only, so that none of it ships.)
// `HITLIST_SIM_FAULTS` is one of `SyncCoreSimulationTests.faultSets` (everyday, conflict, ledger, zone, memory, account,
// quota, refusal, rows, all). It prints, for the report: seeds run, steps, records made, saves accepted, conflicts settled,
// crashes ridden out, and every finding with its seed.
//
// One seed traced:
//
//   HITLIST_SIM_TRACE=<seed> HITLIST_SIM_KEYS=<record-name prefixes or words> [HITLIST_SIM_FAULTS=…] [HITLIST_SIM_STEPS=…] \
//     swift test -c release -Xswiftc -enable-testing -Xswiftc -DDEBUG --filter SyncCoreSimulationTests/testTrace
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
/// host weakly. The person's answer to the brain's one question is the rig's: a purge is answered as `purgeAnswer`
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

    /// The rig's "sync" is the app coming forward: everything is compared (what a write without a hint left is found
    /// here, as in the app: `SyncEngine.cameForward`), then a fetch and a send.
    func syncNow() async throws {
        try await answerQuestions()
        await core.localChanged(nil)
        try await core.syncNow()
        try await answerQuestions()
    }

    /// What a person answers when the brain asks.
    private func answerQuestions() async throws {
        switch await core.status.hold {
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
        // A store that loses rows (nobody deleted them: they must come back and nothing may be deleted in iCloud).
        // Without the transport losing its state in the same run: a reference to a lost row is remembered only in
        // the ledger (section 8), and a ledger forgotten before the row is back forgets it (a written limit).
        case "rows": config.faults = SimFaultKind.everyday.subtracting([.transportStateLost]).union([.rowsLost]); config.faultPercent = 12
        case "all": config.faults = Set(SimFaultKind.allCases); config.faultPercent = 10
        default: break
        }
        return config
    }

    static let faultSets = ["everyday", "conflict", "ledger", "zone", "memory", "account", "quota", "refusal", "rows", "all"]

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
            // Round 32 (brief 150): fixed, a reference the person changed is theirs until it has gone.
            KeptSeed(seed: 210, keys: ["CD432C52", "644580EB", "26BBE64E"],
                     found: "brain: a move to another Group, then that Group deleted here before the change went: the base's older Group came back"),
            KeptSeed(seed: 261, keys: ["BD681474", "F01456DB"],
                     found: "brain: the same as 210, the person's clearing of a moved task read as the store's"),
            KeptSeed(seed: 559, keys: ["17CA86D5", "BF63B19F"],
                     found: "brain: a clearing still to go forgotten by the settle that brought the Group's deletion"),
            KeptSeed(seed: 5, faults: "rows", keys: ["99C931D7", "616F9630"],
                     found: "brain: as 210, with the Group's row lost by the store"),
            KeptSeed(seed: 967, faults: "rows", keys: ["A2F232E9", "399B08E1"],
                     found: "brain: as 210, with the Group's row lost by the store"),
            KeptSeed(seed: 196, faults: "rows", keys: ["9B55AEFC", "5C0AB22F"],
                     found: "brain: a label the person took off, its row then lost, came back on the task (the set's twin of 210)"),
            KeptSeed(seed: 724, faults: "zone", keys: ["E7529A21", "278AB945"],
                     found: "brain: a lost zone forgot what a record waited for; its parent went everywhere by M5"),
            KeptSeed(seed: 362, faults: "account", keys: ["C60FAAF7"],
                     found: "brain: a Group deleted just before a sign-out came back at the sign-in"),
            KeptSeed(seed: 672, faults: "refusal", keys: ["8572DE5D", "5D9B7383"],
                     found: "rig: a memory of records from a fetch that never ended, lost with the transport's state, was not counted"),
            // Round 32, beyond the 400 seeds round 29 ran of these sets.
            KeptSeed(seed: 940, faults: "quota", keys: ["E327C16C", "E0F00BEE"],
                     found: "brain: as 210 (a reference the person changed), fixed with it"),
            KeptSeed(seed: 909, faults: "zone", keys: ["05E217EC"],
                     found: "rig: as 672 (a memory of records from a fetch that never ended), fixed with it"),
            // Round 32 (brief 150): written limits, clean because the rig tells their signature (the `testLimit…` scripts).
            KeptSeed(seed: 174, faults: "rows", keys: ["E783DA98", "9B971E28"],
                     found: "limit: an item brought back on two devices after its deletion comes back as the copy changed last (I9)"),
            KeptSeed(seed: 805, faults: "rows", keys: ["10CF4A3F", "40808A4D"],
                     found: "limit: the same, a change after the deletion on one device and an undo on another"),
            KeptSeed(seed: 59, faults: "quota", keys: ["336385D5", "C15214B2"],
                     found: "limit: the same, the change held by a full iCloud while the undo landed"),
            KeptSeed(seed: 148, faults: "refusal", keys: ["FA958A00", "25302F76"], found: "limit: the same, three devices"),
            KeptSeed(seed: 314, faults: "refusal", keys: ["551710D2", "8446B65F"], found: "limit: the same, a label"),
            KeptSeed(seed: 496, faults: "refusal", keys: ["E0C40984", "D4EEE287"], found: "limit: the same, a parent"),
            KeptSeed(seed: 270, faults: "zone", keys: ["551BFECB"],
                     found: "limit: after a lost zone two copies meet without a base until each device holds one again (I2)"),
            KeptSeed(seed: 653, faults: "zone", keys: ["80CDA054"], found: "limit: the same, a Group"),
            KeptSeed(seed: 856, faults: "zone", keys: ["357DB7D9", "684B3ED0", "9D7DA1BE"], found: "limit: the same, labels, dates, a parent (I2, I9)"),
            KeptSeed(seed: 36, faults: "memory", keys: ["4C680305"], found: "limit: the same, a due date"),
            KeptSeed(seed: 259, faults: "memory", keys: ["8DA01D21"], found: "limit: the same, a Group"),
            // Brief 165 (a sign-out keeps everything). Seed 6 is section 13's: a zone deleted while away, then the
            // sign-out removed an unsent edit. 13 and 26: a deletion made signed out while the zone was lost came back
            // when another device sent the item again, until the sign-in's check kept the deletion.
            KeptSeed(seed: 6, faults: "all", keys: [], found: "brain: the sign-out removed an item with an unsent edit"),
            KeptSeed(seed: 13, faults: "all", keys: ["A9DFB91B"], found: "brain: a deletion made signed out came back (I3)"),
            KeptSeed(seed: 26, faults: "all", keys: ["C2DC5F8B"], found: "brain: the same"),
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

    /// What stays in `swift test` beside the kept seeds: a fixed spread of short runs across the fault sets the brain
    /// rides out today (the long runs are the command at the top of this file). Two devices' saves meeting in iCloud
    /// ("conflict", `sendByItself`) among them, at the supervisor's word.
    static let spread: [(faults: String, seeds: [UInt64])] = [
        ("everyday", [1, 2]), ("conflict", [1, 2]), ("ledger", [1]), ("zone", [1]), ("memory", [1]),
        ("quota", [1]), ("refusal", [1]), ("account", [1, 2]), ("rows", [1, 2, 3]),
    ]

    func testASpreadOfShortRunsAcrossTheFaultSets() async {
        var tally = SimTally()
        for (faults, seeds) in Self.spread {
            for seed in seeds {
                let report = await Self.run(seed: seed, steps: 300, faults: faults, tally: &tally)
                XCTAssertEqual(report.findings, [], "\(faults): \(report.description)")
            }
        }
        print("SyncCore, the spread: \(tally)")
    }

    /// Section 10, as brief 165 changed it: at a sign-out nothing leaves the device, what iCloud never held included;
    /// a sign-in to another account is the switch, every item leaving with the backup; what was synced comes back at
    /// the sign-in to its own account; nothing of one account reaches another (I10).
    func testSignOutAndAnotherAccount_nothingLeavesAtTheSignOut_nothingCrossesAccounts() async {
        let sim = SyncSimulation(seed: 1, brain: SyncCoreSimBrain.make)
        await sim.addDevice("A")
        let t1 = SyncKey(type: "TaskItem", name: "T1"), t2 = SyncKey(type: "TaskItem", name: "T2")
        await sim.play([.sync("A"), .act("A", .put(Self.task("T1", "synced"))), .sync("A"),
                        .fault("A", .network(up: false)), .act("A", .put(Self.task("T2", "never in iCloud"))),
                        .fault("A", .account(nil))])
        let afterSignOut = await sim.device("A")?.store.record(t1)
        let kept = await sim.device("A")?.store.record(t2)
        XCTAssertNotNil(afterSignOut, "what was synced stays on the device")
        XCTAssertNotNil(kept, "an item iCloud never held stays")
        let host = (await sim.device("A")?.brain as? SyncCoreSimBrain)?.host
        XCTAssertEqual(host?.backups ?? [], [], "nothing removed, no backup")
        await sim.play([.fault("A", .account("alice-other")), .fault("A", .network(up: true)), .sync("A"), .sync("A")])
        XCTAssertEqual(host?.backups ?? [], [.accountSwitched], "the switch's backup first")
        let other = await sim.cloud.records(account: "alice-other").map(\.key)
        XCTAssertEqual(other.filter { $0.type == "TaskItem" }, [], "nothing of the first account reached the other")
        await sim.play([.fault("A", .account(FakeCloud.defaultAccount)), .sync("A"), .sync("A")])
        let back = await sim.device("A")?.store.record(t1)
        XCTAssertNotNil(back, "what was synced came back at the sign-in")
        let gone = await sim.device("A")?.store.record(t2)
        XCTAssertNil(gone, "what iCloud never held left with the backup at the switch")
        let alice = await sim.cloud.records().map(\.key)
        XCTAssertEqual(alice.filter { $0.type == "TaskItem" }, [t1], "nothing of the other account reached this one")
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    /// Brief 165: what changes on either side while a device is signed out is not lost at its sign-in to the same
    /// account. A edits T's title and deletes U signed out; B, signed in, edits T's notes and makes V.
    func testASignOutAndBackToTheSameAccountLosesNothingMadeOnEitherSide() async {
        let sim = await Self.twoDevices([Self.task("T", "task"), Self.task("U", "doomed")])
        let t = SyncKey(type: "TaskItem", name: "T"), u = SyncKey(type: "TaskItem", name: "U")
        await sim.play([.fault("A", .account(nil)), .advance(milliseconds: 10),
                        .act("A", .edit(t, ["title": .string("renamed signed out"), "updatedAt": .millis(sim.clock.millis + 10)])),
                        .act("A", .delete(u)), .sync("A"),
                        .act("B", .edit(t, ["notes": .string("noted on B"), "updatedAt": .millis(sim.clock.millis + 20)])),
                        .act("B", .put(Self.task("V", "made on B"))), .sync("B"),
                        .fault("A", .account(FakeCloud.defaultAccount)), .sync("A"), .sync("A"), .sync("B")])
        for device in ["A", "B"] {
            let task = await sim.device(device)?.store.record(t)
            XCTAssertEqual(task?["title"], .string("renamed signed out"), device)
            XCTAssertEqual(task?["notes"], .string("noted on B"), device)
            let doomed = await sim.device(device)?.store.record(u)
            XCTAssertNil(doomed, "deleted while signed out, on \(device)")
            let v = await held(sim, device, "V")
            XCTAssertNotNil(v, device)
        }
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    /// Account seed 362: a Group deleted on A while A could not reach iCloud, then A signed out and back in to the same
    /// account. The sign-out forgot the memory, the unsent deletion with it, and the Group came back at the sign-in.
    /// The deletion is kept across the sign-out and goes at the sign-in.
    func testADeletionNotYetSentSurvivesASignOutAndGoesAtTheSignIn() async {
        let g = Self.group("G")
        let sim = await Self.twoDevices([g, Self.task("T", "task")])
        await sim.play([.fault("A", .network(up: false)), .advance(milliseconds: 10), .act("A", .delete(g.key)),
                        .fault("A", .account(nil)), .fault("A", .account(FakeCloud.defaultAccount)),
                        .fault("A", .network(up: true)), .sync("A"), .sync("A"), .sync("B")])
        for device in ["A", "B"] {
            let group = await sim.device(device)?.store.record(g.key)
            XCTAssertNil(group, "the person deleted G, on \(device)")
            let task = await held(sim, device, "T")
            XCTAssertNotNil(task, "what was synced came back, on \(device)")
        }
        let marker = await sim.cloud.record(g.key)
        XCTAssertEqual(marker?.record.isDeleted, true)
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    /// The same deletion does not follow the device to another account: there it is dropped.
    func testADeletionNotYetSentIsDroppedWhenTheDeviceSignsInToAnotherAccount() async {
        let g = Self.group("G")
        let sim = await Self.twoDevices([g])
        await sim.play([.fault("A", .network(up: false)), .advance(milliseconds: 10), .act("A", .delete(g.key)),
                        .fault("A", .account(nil)), .fault("A", .account("alice-other")),
                        .fault("A", .network(up: true)), .sync("A"), .sync("A")])
        let entry = try? await sim.device("A")?.ledger.entry(g.key)
        XCTAssertNil(entry ?? nil, "nothing of the first account's is kept in the other's memory")
        let other = await sim.cloud.records(account: "alice-other").map(\.key)
        XCTAssertFalse(other.contains(g.key), "no marker of the first account's Group in the other account")
        let alive = await sim.cloud.record(g.key)
        XCTAssertEqual(alive?.record.isDeleted, false, "and the first account's Group is as it was")
    }

    // MARK: The rig's model, corrected on what SyncCore does

    /// Refusal seed 672: a device whose only fetch crashed after records reached it, and which then lost its
    /// transport's state, held bases for those records; its merge without a memory (M5) was not counted, because the
    /// rig counted a memory only after a fetch that ended.
    func testTheRigCountsALostMemoryOfRecordsFromAFetchThatNeverEnded() async {
        let sim = SyncSimulation(seed: 1, brain: SyncCoreSimBrain.make)
        await sim.addDevice("A")
        await sim.addDevice("B")
        await sim.play([.act("A", .put(Self.task("T", "one"))), .sync("A"),
                        .fault("B", .crash(.afterHandling(.fetched))), .sync("B"),
                        .relaunch("B", keepLedger: true, keepTransportState: false), .sync("B")])
        let base = try? await sim.device("B")?.ledger.entry(SyncKey(type: "TaskItem", name: "T"))
        XCTAssertNotNil(base ?? nil, "B settled T again after the loss")
        let amnesia = await sim.intent.amnesia
        XCTAssertTrue(amnesia.contains { $0.device == "B" }, "the rig saw B's memory lost: \(amnesia)")
    }

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

    /// Everyday seeds 166, 210, 261: a person took a task out of its Group (not sent yet), then deleted the Group and put
    /// it back (an undo) before syncing. The base still named the Group, so once it was gone the task waited for it, and
    /// the undo gave the task its Group back everywhere: the person's change lost. The clearing is remembered now.
    func testAPersonsUnsentClearingOfAGroupSurvivesTheGroupsDeletionAndUndo() async {
        let g = Self.group("G")
        let sim = await Self.twoDevices([g, Self.task("T", "task", ["project": .reference("G")])])
        let t = SyncKey(type: "TaskItem", name: "T")
        // Offline, so nothing goes before the undo; the deletion is compared whole (the app's "anything may have
        // changed"), as a sync's fetch would.
        await sim.play([.fault("A", .network(up: false)),
                        .advance(milliseconds: 10), .act("A", .edit(t, ["project": nil])),
                        .advance(milliseconds: 10), .act("A", .delete(g.key), hint: .everything),
                        .advance(milliseconds: 10), .act("A", .put(g), hint: .everything),
                        .fault("A", .network(up: true)), .sync("A"), .sync("B"), .sync("A")])
        for device in ["A", "B"] {
            let task = await held(sim, device, "T")
            XCTAssertNil(task?["project"], "the person took T out of G, on \(device)")
        }
        let inCloud = await sim.cloud.record(t)
        XCTAssertNil(inCloud?.record["project"])
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    // MARK: Round 32 (brief 150): a reference the person changed is theirs until it has gone

    static func label(_ name: String) -> SyncRecord {
        SyncRecord(type: "TaskLabel", name: name, fields: ["name": .string("label \(name)")])
    }

    /// Everyday seeds 210, 261 (and rows 5, 967): offline, a person moved a task from a deleted Group G1 to G2, then
    /// deleted G2, then put G1 back. G2's deletion emptied the field, and the base (still G1) was read as a reference
    /// the store had taken off: the task waited for G1 and went back into it everywhere. A to-one the device holds
    /// with another item than the base names is the person's: the base's reference is no longer waited for.
    func testAMoveToAnotherGroupThenThatGroupsDeletion_doesNotBringTheBasesGroupBack() async {
        let g1 = Self.group("G1"), g2 = Self.group("G2")
        let sim = await Self.twoDevices([g1, g2, Self.task("T", "task", ["project": .reference("G1")])])
        let t = SyncKey(type: "TaskItem", name: "T")
        await sim.play([.fault("A", .network(up: false)),
                        .advance(milliseconds: 10), .act("A", .delete(g1.key)),
                        .advance(milliseconds: 10), .act("A", .edit(t, ["project": .reference("G2")])),
                        .advance(milliseconds: 10), .act("A", .delete(g2.key)),
                        .advance(milliseconds: 10), .act("A", .put(g1)),
                        .fault("A", .network(up: true)), .sync("A"), .sync("B"), .sync("A")])
        for device in ["A", "B"] {
            let task = await held(sim, device, "T")
            XCTAssertNil(task?["project"], "G2 is gone and G1 is not where the person put T, on \(device)")
        }
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    /// Everyday seed 559: B took a task out of its Group (not sent yet); A deleted the Group and changed the task; B's
    /// fetch brought both, and the merge kept B's clearing. The settle then read the waits against iCloud's record
    /// (which still names the Group) and forgot that the field was the person's: the task waited for the Group, and
    /// A's undo put it back. A settle keeps the cleared mark the device held.
    func testAClearingStillToGoSurvivesASettleThatBringsTheGroupsDeletion() async {
        let g = Self.group("G")
        let sim = await Self.twoDevices([g, Self.task("T", "task", ["project": .reference("G")])])
        let t = SyncKey(type: "TaskItem", name: "T")
        await sim.play([.fault("B", .network(up: false)),
                        .advance(milliseconds: 10), .act("B", .edit(t, ["project": nil])),
                        .advance(milliseconds: 10), .act("A", .delete(g.key)), .act("A", .edit(t, ["title": .string("A's")])),
                        .sync("A"),
                        .fault("B", .network(up: true)), .sync("B"),
                        .advance(milliseconds: 10), .act("A", .put(g)), .sync("A"), .sync("B"), .sync("A")])
        for device in ["A", "B"] {
            let task = await held(sim, device, "T")
            XCTAssertNil(task?["project"], "the person on B took T out of G, on \(device)")
            XCTAssertEqual(task?["title"], .string("A's"), "and A's edit stands, on \(device)")
        }
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    /// The same for a set (brief 145 left it open; rows seed 196): a person took a label off a task, then the label was
    /// deleted here (or the store lost its row) before the change went, then it came back. The base still held the
    /// name, so the task waited for it and got it back. A name the person took off while its item was here is noted
    /// (`removedKey`) and never waited for.
    func testALabelTakenOffThenDeletedAndPutBack_staysOff() async {
        let l = Self.label("L")
        let sim = await Self.twoDevices([l, Self.task("T", "task", ["labels": .references(["L"])])])
        let t = SyncKey(type: "TaskItem", name: "T")
        await sim.play([.fault("A", .network(up: false)),
                        .advance(milliseconds: 10), .act("A", .edit(t, ["labels": nil])),
                        .advance(milliseconds: 10), .act("A", .delete(l.key)),
                        .advance(milliseconds: 10), .act("A", .put(l)),
                        .fault("A", .network(up: true)), .sync("A"), .sync("B"), .sync("A")])
        for device in ["A", "B"] {
            let task = await held(sim, device, "T")
            XCTAssertNil(task?["labels"], "the person took L off T, on \(device)")
        }
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    func testALabelTakenOffThenItsRowLost_staysOffWhenTheRowComesBack() async {
        let l = Self.label("L")
        let sim = await Self.twoDevices([l, Self.task("T", "task", ["labels": .references(["L"])])])
        let t = SyncKey(type: "TaskItem", name: "T")
        await sim.play([.fault("A", .network(up: false)),
                        .advance(milliseconds: 10), .act("A", .edit(t, ["labels": nil])),
                        .fault("A", .loseRows([l.key])), .relaunch("A"),
                        .fault("A", .network(up: true)), .sync("A"), .sync("A"), .sync("B"), .sync("A")])
        for device in ["A", "B"] {
            let label = await sim.device(device)?.store.record(l.key)
            XCTAssertNotNil(label, "the label nobody deleted is back, on \(device)")
            let task = await held(sim, device, "T")
            XCTAssertNil(task?["labels"], "the person took L off T, on \(device)")
        }
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    /// Zone seed 724: a record waited for an item that was not on its device (here a label iCloud had refused, so
    /// that it never reached A) when the zone was lost. The forgetting took the wait with it, so A sent its task again
    /// without the label, and the merge without a memory (M5) kept that copy over B's. What a record waits for is the
    /// device's own and is kept across the forgetting.
    func testAReferenceWaitedForSurvivesALostZone() async {
        var config = SimConfig()
        if ProcessInfo.processInfo.environment["HITLIST_SIM_DEBUG"] != nil { config.log = { print("BRAIN \($0)") } }
        let sim = SyncSimulation(seed: 1, config: config, brain: SyncCoreSimBrain.make)
        await sim.addDevice("A")
        await sim.addDevice("B")
        let l = Self.label("L")
        await sim.play([.sync("A"), .sync("B"),
                        .act("B", .put(l)), .act("B", .put(Self.task("T", "task", ["labels": .references(["L"])]))),
                        .cloud(.refuseNextSave(l.key, .tooLarge)), .sync("B"), .sync("A"),
                        .cloud(.deleteZone(.deleted)), .sync("A"),
                        .advance(milliseconds: 10), .act("B", .edit(l.key, ["name": .string("smaller")])),
                        .sync("B"), .sync("A"), .sync("B")])
        for device in ["A", "B"] {
            let task = await held(sim, device, "T")
            XCTAssertEqual(task?["labels"], .references(["L"]), "T keeps its label, on \(device)")
        }
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
    }

    // MARK: Written limits (round 32, brief 150): each fails if the behaviour changes either way

    /// Rows seeds 174, 805, quota 59, refusal 148, 314, 496. A deleted T; B and C, apart, each changed it after the
    /// deletion reached them (C gave it a Group, B a new title later). Both copies come back over the marker, and when
    /// they meet they have nothing in common but the marker: the copy changed last stands whole (M12 against a live
    /// record, as M5), and C's Group goes. The rig excuses exactly this (`SimIntent.revivedApart`).
    func testLimit_anItemBroughtBackOnTwoDevicesAfterItsDeletion_comesBackAsTheCopyChangedLast() async {
        var config = SimConfig()
        if ProcessInfo.processInfo.environment["HITLIST_SIM_DEBUG"] != nil { config.log = { print("BRAIN \($0)") } }
        let sim = SyncSimulation(seed: 1, config: config, brain: SyncCoreSimBrain.make)
        for name in ["A", "B", "C"] { await sim.addDevice(name) }
        let g = Self.group("G")
        let t = SyncKey(type: "TaskItem", name: "T")
        await sim.play([.act("A", .put(g)), .act("A", .put(Self.task("T", "first"))), .sync("A"), .sync("B"), .sync("C"),
                        .advance(milliseconds: 10), .act("A", .delete(t)), .sync("A"),
                        // B and C learn of the deletion; neither has sent anything yet.
                        .fault("B", .network(up: false)), .fault("C", .network(up: false)),
                        .advance(milliseconds: 10), .act("C", .edit(t, ["project": .reference("G")])),
                        .advance(milliseconds: 10), .act("B", .edit(t, ["title": .string("B's")])),
                        .fault("B", .network(up: true)), .fault("B", .dropNetwork(after: 1)), .sync("B"),
                        .fault("C", .network(up: true)), .sync("C"),
                        .fault("B", .network(up: true)), .sync("B"), .sync("C"), .sync("A")])
        for device in ["A", "B", "C"] {
            let task = await held(sim, device, "T")
            XCTAssertEqual(task?["title"], .string("B's"), "B's copy, changed last, stands whole on \(device)")
            XCTAssertNil(task?["project"], "C's Group went with C's copy, on \(device)")
        }
        let drops = await sim.intent.drops.map(\.drop).filter { $0.key == t && $0.field == "project" }
        XCTAssertEqual(drops.map(\.device), ["B"], "B's whole copy took C's Group away in iCloud")
        let findings = await sim.check()
        XCTAssertEqual(findings, [], "the rig knows this signature")
    }

    /// The rig's excuse for it is no wider than the signature: a reference dropped on an item only one device brought
    /// back, or one never deleted, is still a finding.
    func testLimit_theRevivalExcuseNeedsTwoDevicesBringingTheItemBack() {
        var intent = SimIntent()
        let t = SyncKey(type: "TaskItem", name: "T")
        let made = SyncRecord(key: t, fields: ["title": .string("first")])
        intent.record(step: 1, device: "A", before: [:], after: [t: made])
        XCTAssertFalse(intent.revivedApart(t, by: "B", by: 10), "never deleted")
        intent.record(step: 2, device: "A", before: [t: made], after: [:])
        var changed = made
        changed.fields["title"] = .string("B's")
        intent.record(step: 3, device: "B", before: [t: made], after: [t: changed])
        XCTAssertFalse(intent.revivedApart(t, by: "B", by: 10), "only B brought it back")
        var other = made
        other.fields["notes"] = .string("C's")
        intent.record(step: 4, device: "C", before: [t: made], after: [t: other])
        XCTAssertTrue(intent.revivedApart(t, by: "B", by: 10))
        XCTAssertFalse(intent.revivedApart(t, by: "B", by: 3), "not yet: C had not brought it back")
        XCTAssertFalse(intent.revivedApart(t, by: "A", by: 10), "A did not bring it back")
    }

    /// Zone seeds 270, 653, 856, memory 36, 259. The zone is lost; both devices hear of it and send everything again,
    /// but B's copy of T does not land (here iCloud refuses it), so B holds T with no base while A's copy is in
    /// iCloud. A changes T's title; B changes its notes later. B meets A's copy without a base (M5): the copy changed
    /// last stands whole, and A's title goes, although both devices had finished a whole fetch since the loss. Once
    /// both hold a base from the new zone, a change is judged again (and kept).
    func testLimit_afterALostZoneTwoCopiesMeetWithoutABase_theCopyChangedLastStands() async {
        let sim = await Self.twoDevices([Self.task("T", "first")])
        let t = SyncKey(type: "TaskItem", name: "T")
        await sim.play([.cloud(.deleteZone(.deleted)), .cloud(.refuseNextSave(t, .tooLarge)), .sync("B"), .sync("A"),
                        .advance(milliseconds: 10), .act("A", .edit(t, ["title": .string("A's")])), .sync("A"),
                        .advance(milliseconds: 10), .act("B", .edit(t, ["notes": .string("B's")])),
                        .sync("B"), .sync("A"), .sync("B")])
        for device in ["A", "B"] {
            let task = await held(sim, device, "T")
            XCTAssertEqual(task?["title"], .string("first"), "A's title went with A's copy, on \(device)")
            XCTAssertEqual(task?["notes"], .string("B's"), "B's copy, changed last, stands whole on \(device)")
        }
        let intent = await sim.intent
        let edits = intent.events.filter { $0.key == t && $0.change != .deleted && $0.step > 1 }.map(\.step)
        XCTAssertEqual(edits.count, 2)
        XCTAssertTrue(edits.allSatisfy { intent.zoneExposed(t, at: $0) }, "both made while a device held T with no base")
        XCTAssertTrue(edits.allSatisfy { $0 > intent.exposedThrough }, "after every lost memory had ended: only the zone's window excuses them")
        // Both hold a base from the new zone now: a change is judged again, and kept.
        await sim.play([.advance(milliseconds: 10), .act("A", .edit(t, ["title": .string("A's again")])), .sync("A"), .sync("B")])
        let later = await sim.intent.events.last { $0.key == t }?.step ?? 0
        let exposed = await sim.intent.zoneExposed(t, at: later)
        XCTAssertFalse(exposed, "the exposure ended when both had a base again")
        let findings = await sim.check()
        XCTAssertEqual(findings, [], "the rig knows this signature")
        let task = await held(sim, "B", "T")
        XCTAssertEqual(task?["title"], .string("A's again"))
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

    // MARK: Only what was deleted is deleted (2026-11-15), and refusals apart

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

    func testABulkDeletionByThePersonSimplyGoes_undoingAnImport() async throws {
        let (sim, core) = await oneDevice(40)
        let gone = keys(0..<30)
        for key in gone { await sim.device("A")?.store.delete(key) }
        await core.localChanged(gone)
        let status = await core.status
        XCTAssertNil(status.hold, "30 of 40 deleted by the person: nobody is asked")
        XCTAssertEqual(status.waiting, 30)
        try await core.syncNow()
        let alive = await sim.cloud.records().filter { !$0.record.isDeleted && $0.key.type == "TaskItem" }.count
        XCTAssertEqual(alive, 10)
    }

    func testAStoreThatLosesItemsDeletesNothing_theyComeBackFromIcloud() async throws {
        let (sim, core) = await oneDevice(12)
        for key in keys(0..<10) { await sim.device("A")?.store.lose(key) }
        await sim.device("A")?.store.put(Self.task("NEW", "made while the store read wrong"))
        await core.localChanged(nil)
        let status = await core.status
        XCTAssertNil(status.hold, "nothing to ask: nobody deleted anything")
        XCTAssertEqual(status.waiting, 1, "only the new task waits; no marker for an item that is merely not here")
        try await core.syncNow()
        try await core.syncNow()
        let here = try await sim.device("A")?.store.records().count
        XCTAssertEqual(here, 13, "the 10 back from iCloud, the 2 kept, the new one")
        let all = await sim.cloud.records().filter { $0.key.type == "TaskItem" }
        XCTAssertEqual(all.filter { !$0.record.isDeleted }.count, 13, "nothing deleted in iCloud; the new one went up")
        XCTAssertEqual(all.filter { $0.record.isDeleted }.count, 0, "and no marker was ever sent")
    }

    func testAStoreThatReadsEmptyDeletesNothing() async throws {
        let (sim, core) = await oneDevice(12)
        await sim.device("A")?.store.loseEverything()
        await core.localChanged(nil)
        let status = await core.status
        XCTAssertNil(status.hold)
        XCTAssertEqual(status.waiting, 0, "an empty store has nothing to send, least of all deletions")
        try await core.syncNow()
        let here = try await sim.device("A")?.store.records().count
        XCTAssertEqual(here, 12, "everything is back")
        let markers = await sim.cloud.records().filter { $0.record.isDeleted }.count
        XCTAssertEqual(markers, 0)
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
