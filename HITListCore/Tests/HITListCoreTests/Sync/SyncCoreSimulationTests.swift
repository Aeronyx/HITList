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
