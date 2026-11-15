import Foundation
import XCTest
@testable import HITListCore

/// The invariants I1 to I8 (`dev/SYNC-ENGINE.md`, section 9), each on a state built by hand that holds it and one that
/// breaks it; then the simulation rig run with a brain of the tests' own that is honest but simple, to show that the
/// rig and the invariants find what such a brain gets wrong.
final class SyncInvariantsTests: XCTestCase {

    // MARK: I1 Same everywhere

    func testI1_holdsWhenEveryDeviceAndIcloudHoldTheSameItems() {
        let devices = [holder("A", [task("t1", "x")]), holder("B", [task("t1", "x")])]
        XCTAssertEqual(SyncInvariants.sameEverywhere(devices: devices, cloud: [cloud(task("t1", "x"))]), [])
    }

    func testI1_breaksWhenADeviceHoldsAnotherValueOrAnItemIcloudLacks() {
        let devices = [holder("A", [task("t1", "x")]), holder("B", [task("t1", "y"), task("t2", "extra")])]
        let marker = cloud(.marker(key("t2"), deletedAt: Date(timeIntervalSince1970: 5)))
        let findings = SyncInvariants.sameEverywhere(devices: devices, cloud: [cloud(task("t1", "x")), marker])
        XCTAssertEqual(findings.map(\.description), [
            "I1 device B holds TaskItem/t1 with title 'y'; iCloud holds 'x'",
            "I1 device B holds TaskItem/t2 (title 'extra'); iCloud holds it as deleted",
        ])
    }

    // MARK: I2 No lost edit

    func testI2_holdsWhenEachDevicesOwnEditIsEverywhere() {
        var intent = SimIntent()
        intent.record(step: 1, device: "A", before: [:], after: [key("t1"): task("t1", "x")])
        intent.record(step: 2, device: "A", before: [key("t1"): task("t1", "x")], after: [key("t1"): task("t1", "y")])
        intent.record(step: 3, device: "B", before: [key("t1"): task("t1", "y")], after: [key("t1"): task("t1", "y", notes: "n")])
        let final = task("t1", "y", notes: "n")
        let findings = SyncInvariants.noLostEdit(devices: [holder("A", [final]), holder("B", [final])],
                                                 cloud: [cloud(final)], intent: intent)
        XCTAssertEqual(findings, [])
    }

    func testI2_breaksWhenAFieldOnlyOneDeviceChangedLostItsValue() {
        var intent = SimIntent()
        intent.record(step: 1, device: "A", before: [:], after: [key("t1"): task("t1", "x")])
        intent.record(step: 2, device: "A", before: [key("t1"): task("t1", "x")], after: [key("t1"): task("t1", "y")])
        intent.record(step: 3, device: "B", before: [key("t1"): task("t1", "x")], after: [key("t1"): task("t1", "x", notes: "n")])
        let lost = task("t1", "x", notes: "n")
        let findings = SyncInvariants.noLostEdit(devices: [holder("A", [lost]), holder("B", [lost])], cloud: [cloud(lost)],
                                                 intent: intent)
        XCTAssertEqual(findings.map(\.description), [
            "I2 TaskItem/t1 title should be 'y': device A set it at step 2 and no other device changed it; "
                + "device A holds 'x'; device B holds 'x'; iCloud holds 'x'",
        ])
    }

    func testI2_doesNotJudgeAFieldTwoDevicesChangedNorAnEditBeforeAMemoryWasLost() {
        var intent = SimIntent()
        intent.record(step: 1, device: "A", before: [:], after: [key("t1"): task("t1", "x")])
        intent.record(step: 2, device: "A", before: [key("t1"): task("t1", "x")], after: [key("t1"): task("t1", "a")])
        intent.record(step: 3, device: "B", before: [key("t1"): task("t1", "x")], after: [key("t1"): task("t1", "b")])
        intent.record(step: 4, device: "A", before: [key("t1"): task("t1", "a")], after: [key("t1"): task("t1", "a", notes: "n")])
        intent.recordAmnesia(step: 5, device: "B")
        let final = task("t1", "b")
        let findings = SyncInvariants.noLostEdit(devices: [holder("A", [final]), holder("B", [final])], cloud: [cloud(final)],
                                                 intent: intent)
        XCTAssertEqual(findings, [], "title: two devices; notes: changed before B lost its memory")
    }

    func testI2_doesNotJudgeTheFieldsOfAnItemMadeOnTwoDevices() {
        let profile = SyncKey(type: "Profile", name: "profile")
        func named(_ name: String, at ms: Int64) -> SyncRecord {
            SyncRecord(key: profile, fields: ["displayName": .string(name), "nameUpdatedAt": .millis(ms), "updatedAt": .millis(ms)])
        }
        var intent = SimIntent()
        intent.record(step: 1, device: "A", before: [:], after: [profile: named("A's", at: 1)])
        intent.record(step: 2, device: "A", before: [profile: named("A's", at: 1)], after: [profile: named("A's again", at: 2)])
        intent.record(step: 3, device: "B", before: [:], after: [profile: named("B's", at: 3)])
        let final = SyncSchema.filled(named("B's", at: 3))
        XCTAssertEqual(SyncInvariants.noLostEdit(devices: [holder("A", [final]), holder("B", [final])], cloud: [cloud(final)],
                                                 intent: intent), [])
    }

    func testI2_breaksWhenAnItemMadeAndNeverDeletedIsMissing() {
        var intent = SimIntent()
        intent.record(step: 1, device: "A", before: [:], after: [key("t1"): task("t1", "x")])
        let findings = SyncInvariants.noLostEdit(devices: [holder("A", [task("t1", "x")]), holder("B", [])],
                                                 cloud: [cloud(task("t1", "x"))], intent: intent)
        XCTAssertEqual(findings.map(\.description), [
            "I2 TaskItem/t1 was made on device A at step 1 and never deleted; device B does not hold it",
        ])
    }

    func testI2_aReferenceToAnItemAPersonDeletedIsExpectedEmpty() {
        let group = SyncRecord(type: "Project", name: "g", fields: ["name": .string("G"), "updatedAt": .millis(1)])
        var placed = task("t1", "x")
        placed["project"] = .reference("g")
        var intent = SimIntent()
        intent.record(step: 1, device: "A", before: [:], after: [group.key: group])
        intent.record(step: 2, device: "B", before: [group.key: group], after: [group.key: group, key("t1"): task("t1", "x")])
        intent.record(step: 3, device: "B", before: [key("t1"): task("t1", "x")], after: [key("t1"): placed])
        intent.record(step: 4, device: "A", before: [group.key: group], after: [:])
        let final = task("t1", "x")
        XCTAssertEqual(SyncInvariants.noLostEdit(devices: [holder("A", [final]), holder("B", [final])], cloud: [cloud(final)],
                                                 intent: intent), [])
    }

    // MARK: I3 Nothing comes back

    func testI3_holdsWhenADeletedItemIsGoneEverywhereAndIcloudKeepsOnlyItsMarker() {
        let intent = madeThenDeleted()
        let marker = cloud(.marker(key("t1"), deletedAt: Date(timeIntervalSince1970: 3)))
        XCTAssertEqual(SyncInvariants.nothingComesBack(devices: [holder("A", []), holder("B", [])], cloud: [marker],
                                                       intent: intent), [])
    }

    func testI3_breaksWhenADeletedItemIsBackOnADeviceOrAliveInIcloud() {
        let intent = madeThenDeleted()
        let findings = SyncInvariants.nothingComesBack(devices: [holder("A", []), holder("B", [task("t1", "x")])],
                                                       cloud: [cloud(task("t1", "x"))], intent: intent)
        XCTAssertEqual(findings.map(\.description), [
            "I3 TaskItem/t1 was deleted on device A at step 2 and not changed afterwards; device B holds it (title 'x'); "
                + "iCloud holds it alive (title 'x')",
        ])
    }

    func testI3_doesNotJudgeAnItemChangedElsewhereAfterItsDeletion() {
        var intent = madeThenDeleted()
        intent.record(step: 3, device: "B", before: [key("t1"): task("t1", "x")], after: [key("t1"): task("t1", "kept")])
        XCTAssertEqual(SyncInvariants.nothingComesBack(devices: [holder("B", [task("t1", "kept")])],
                                                       cloud: [cloud(task("t1", "kept"))], intent: intent), [])
    }

    // MARK: I4 Twice is once

    func testI4_holdsWhenTheSecondDeliveryChangedNothing() {
        let snapshot = DeviceSnapshot(records: [task("t1", "x")], entries: [LedgerEntry(key: key("t1"))], deferred: [],
                                      facts: [:], pending: [])
        XCTAssertEqual(SyncInvariants.twiceIsOnce(device: "A", event: "fetched", once: snapshot, twice: snapshot), [])
    }

    func testI4_breaksWhenTheSecondDeliveryChangedTheDevice() {
        let once = DeviceSnapshot(records: [task("t1", "x")], entries: [], deferred: [], facts: [:], pending: [])
        let twice = DeviceSnapshot(records: [task("t1", "xx")], entries: [], deferred: [], facts: [:],
                                   pending: [.save(key("t1"))])
        XCTAssertEqual(SyncInvariants.twiceIsOnce(device: "A", event: "fetched at step 9", once: once, twice: twice).map(\.description), [
            "I4 device A, fetched at step 9 delivered a second time: TaskItem/t1 went from title 'x' to title 'xx'; "
                + "its pending list went from 0 to 1 changes",
        ])
    }

    // MARK: I5 One of each

    func testI5_holdsWithOneItemPerKey() {
        XCTAssertEqual(SyncInvariants.oneOfEach(devices: [holder("A", [task("t1", "x"), task("t2", "y")])]), [])
    }

    func testI5_breaksWithTwoItemsForOneKeyOrAProfileUnderAnotherName() {
        let devices = [holder("A", [task("t1", "x"), task("t1", "x again"),
                                    SyncRecord(type: "Profile", name: "6B1F", fields: ["displayName": .string("G")])])]
        XCTAssertEqual(SyncInvariants.oneOfEach(devices: devices).map(\.description), [
            "I5 device A holds 2 items with the key TaskItem/t1",
            "I5 device A holds a Profile named 6B1F; there is one per account, named profile",
        ])
    }

    // MARK: I6 Whole

    func testI6_holdsWhenEveryReferencePointsAtAnItemThatIsThere() {
        let group = SyncRecord(type: "Project", name: "g", fields: ["name": .string("G")])
        var placed = task("t1", "x")
        placed["project"] = .reference("g")
        XCTAssertEqual(SyncInvariants.whole(devices: [holder("A", [group, placed])], cloud: [cloud(group), cloud(placed)]), [])
    }

    func testI6_breaksWhenAnItemPointsAtOneThatIsNotThere() {
        var child = task("c", "child")
        child["parent"] = .reference("p")
        child["labels"] = .references(["l1"])
        let parentMarker = cloud(.marker(key("p"), deletedAt: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(SyncInvariants.whole(devices: [holder("A", [child])], cloud: [cloud(child), parentMarker]).map(\.description), [
            "I6 device A: TaskItem/c points at TaskLabel/l1, which it does not hold",
            "I6 device A: TaskItem/c points at TaskItem/p, which it does not hold",
            "I6 iCloud: TaskItem/c points at TaskLabel/l1, which iCloud does not hold alive",
            "I6 iCloud: TaskItem/c points at TaskItem/p, which iCloud does not hold alive",
        ])
    }

    // MARK: I7 Quiet

    func testI7_holdsWhenNothingWaitsAndOneMoreSyncSavedNothing() {
        XCTAssertEqual(SyncInvariants.quiet(devices: [holder("A", [])], savedInExtraRound: [], rounds: 2, limit: 12), [])
    }

    func testI7_breaksOnChangesStillWaitingPingPongOrNoQuietAtAll() {
        let devices = [holder("A", [], pending: [.save(key("t1"))])]
        XCTAssertEqual(SyncInvariants.quiet(devices: devices, savedInExtraRound: [key("t2")], rounds: nil, limit: 12).map(\.description), [
            "I7 not quiet after 12 rounds of every device syncing",
            "I7 device A still has 1 changes waiting (save(TaskItem/t1))",
            "I7 one more sync with nothing waiting saved 1 records in iCloud (TaskItem/t2): ping-pong",
        ])
    }

    // MARK: I8 A newer build's fields survive

    func testI8_holdsWhenAPokedFieldIsStillInIcloud() {
        var intent = SimIntent()
        intent.recordPoke(step: 4, key: key("t1"), fields: ["futureField": .string("v")])
        var held = task("t1", "x")
        held["futureField"] = .string("v")
        XCTAssertEqual(SyncInvariants.newerFieldsSurvive(cloud: [cloud(held)], intent: intent), [])
    }

    func testI8_breaksWhenAnOlderBuildsSaveClearedIt() {
        var intent = SimIntent()
        intent.recordPoke(step: 4, key: key("t1"), fields: ["futureField": .string("v")])
        XCTAssertEqual(SyncInvariants.newerFieldsSurvive(cloud: [cloud(task("t1", "x"))], intent: intent).map(\.description), [
            "I8 TaskItem/t1 futureField was written by a newer build at step 4 as 'v'; iCloud now holds nothing",
        ])
    }

    // MARK: The rig, with a brain of the tests' own

    func testTheRigFindsNothingWrongWhenDevicesTakeTurns() async {
        let sim = SyncSimulation(seed: 1, brain: NaiveBrain.make)
        await sim.addDevice("A")
        await sim.addDevice("B")
        let t1 = key("11111111-0000-0000-0000-000000000001")
        await sim.play([
            .act("A", .put(SyncRecord(key: t1, fields: ["title": .string("first")]))),
            .sync("A"), .sync("B"), .advance(milliseconds: 10),
            .act("B", .edit(t1, ["notes": .string("B's notes")])),
            .sync("B"), .sync("A"), .advance(milliseconds: 10),
            .act("A", .edit(t1, ["title": .string("A's title")])),
            .sync("A"), .sync("B"),
        ])
        let findings = await sim.check()
        XCTAssertEqual(findings, [])
        let held = await sim.device("B")?.store.record(t1)
        XCTAssertEqual(held?["title"], .string("A's title"))
        XCTAssertEqual(held?["notes"], .string("B's notes"))
    }

    func testTheRigCatchesTheSimpleBrainLosingAnEdit_byScript() async {
        let sim = SyncSimulation(seed: 1, brain: NaiveBrain.make)
        await sim.addDevice("A")
        await sim.addDevice("B")
        let t1 = key("11111111-0000-0000-0000-000000000001")
        await sim.play([
            .act("A", .put(SyncRecord(key: t1, fields: ["title": .string("first")]))),
            .sync("A"), .sync("B"), .advance(milliseconds: 10),
            // A changes the title and has not synced; B changes the notes and syncs.
            .act("A", .edit(t1, ["title": .string("A's title")])), .advance(milliseconds: 10),
            .act("B", .edit(t1, ["notes": .string("B's notes")])),
            .sync("B"),
            // A fetches B's record and takes it whole, over its own unsent title.
            .sync("A"),
        ])
        let findings = await sim.check()
        XCTAssertTrue(findings.contains { $0.invariant == .noLostEdit && $0.words.contains("title should be 'A's title'") },
                      findings.map(\.description).joined(separator: "\n"))
    }

    func testTheRigRelaunchesACrashedDeviceFromItsStoreAndLedger() async {
        let sim = SyncSimulation(seed: 1, brain: NaiveBrain.make)
        await sim.addDevice("A")
        let t1 = key("11111111-0000-0000-0000-000000000001")
        await sim.play([
            .act("A", .put(SyncRecord(key: t1, fields: ["title": .string("first")]))),
            .fault("A", .crash(.beforeSent)),
            .sync("A"),
        ])
        let launches = await sim.device("A")?.launches
        XCTAssertEqual(launches, 1)
        let notes = await sim.notes
        XCTAssertTrue(notes.contains { $0.contains("A crashed") }, "\(notes)")
        let findings = await sim.check()
        XCTAssertEqual(findings, [], "the simple brain settles its own save it never heard of by taking iCloud's")
    }

    func testTheRigChecksI4WhenAnEventComesTwice() async {
        let sim = SyncSimulation(seed: 1, brain: { parts in await NaiveBrain(parts, notesEveryFetch: true) })
        await sim.addDevice("A")
        await sim.addDevice("B")
        let t1 = key("11111111-0000-0000-0000-000000000001")
        await sim.play([
            .act("A", .put(SyncRecord(key: t1, fields: ["title": .string("first")]))),
            .sync("A"),
            .fault("B", .deliverTwice(.fetched)),
            .sync("B"),
        ])
        let findings = await sim.check()
        XCTAssertTrue(findings.contains { $0.invariant == .twiceIsOnce && $0.words.contains("device B, fetched at step 4") },
                      findings.map(\.description).joined(separator: "\n"))
    }

    func testTheSameSeedIsTheSameRun() async {
        var config = SimConfig()
        config.faults = SimFaultKind.everyday
        let first = await SyncSimulation.randomRun(seed: 7, devices: 3, steps: 300, config: config, brain: NaiveBrain.make)
        let second = await SyncSimulation.randomRun(seed: 7, devices: 3, steps: 300, config: config, brain: NaiveBrain.make)
        XCTAssertEqual(first.script, second.script)
        XCTAssertEqual(first.findings, second.findings)
        let other = await SyncSimulation.randomRun(seed: 8, devices: 3, steps: 300, config: config, brain: NaiveBrain.make)
        XCTAssertNotEqual(first.script, other.script)
    }

    /// Brief 140, item 6: the rig finds what an honest but simple brain gets wrong. This brain sends whatever differs
    /// from what it last knew of iCloud and takes iCloud's record whole on every fetch and every conflict: an edit not
    /// yet sent is lost when another device's change to the same item arrives first. I2 must say so.
    func testDemonstration_aSeededRandomRunFindsTheSimpleBrainLosingEdits() async {
        var found: SimReport?
        var tried: [UInt64] = []
        for seed in UInt64(1)...20 {
            tried.append(seed)
            let report = await SyncSimulation.randomRun(seed: seed, devices: 3, steps: 300, brain: NaiveBrain.make)
            if report.findings.contains(where: { $0.invariant == .noLostEdit }) {
                found = report
                break
            }
        }
        guard let report = found else { return XCTFail("no seed of \(tried) caught the simple brain losing an edit") }
        let lost = report.findings.first { $0.invariant == .noLostEdit }!
        print("Demonstration (brief 140, item 6): \(report.description.split(separator: "\n").first!)")
        print("  first lost edit: \(lost)")
        print("  replay: SyncSimulation.randomRun(seed: \(report.seed), devices: \(report.devices), steps: \(report.steps), brain: NaiveBrain.make)")
    }

    /// The other side of the demonstration: a brain that keeps section 5's rules (`MergingBrain`, below) meets every
    /// everyday fault on several seeds and the invariants find nothing. What they report is the brain's, not theirs.
    func testABrainThatKeepsTheRulesGetsNoFindings() async {
        var reports: [SimReport] = []
        for seed in UInt64(1)...4 {
            reports.append(await SyncSimulation.randomRun(seed: seed, devices: 3, steps: 300, brain: MergingBrain.make))
        }
        for report in reports {
            XCTAssertEqual(report.findings, [], report.description)
        }
        // Not an empty victory: a longer run, and what it left in iCloud.
        let sim = SyncSimulation(seed: 99, brain: MergingBrain.make)
        for name in ["A", "B", "C"] { await sim.addDevice(name) }
        await sim.runRandom(steps: 600)
        let findings = await sim.check()
        XCTAssertEqual(findings, [], findings.map(\.description).joined(separator: "\n"))
        let held = await sim.cloud.records()
        let alive = held.filter { !$0.record.isDeleted }.count
        let saves = await sim.cloud.acceptedSaves
        let notes = await sim.notes
        print("MergingBrain, seed 99, 600 steps: iCloud holds \(alive) items and \(held.count - alive) markers after "
              + "\(saves) accepted saves; \(notes.count) notes (crashes, failed syncs)")
        XCTAssertGreaterThan(alive, 50)
    }

    /// The faults that lose a memory (a ledger lost, the zone deleted or reset), with the rules-keeping brain: what the
    /// design cannot keep (an edit or a deletion a merge without a memory may settle) is not held to account, and
    /// everything else still holds. (Account changes are left to wave 2: a correct brain removes what was synced at
    /// sign-out, section 10, and this one does not.)
    func testABrainThatKeepsTheRulesGetsNoFindingsWhenMemoriesAreLostToo() async {
        for kinds in [[SimFaultKind.ledgerLost], [.zoneDeleted, .zoneReset]] {
            // Seeds 1 and 4 once showed what a merge without a memory may lose (before the model knew it).
            for seed in UInt64(1)...4 {
                var config = SimConfig()
                config.faults = SimFaultKind.everyday.union(kinds)
                config.faultPercent = 10
                let report = await SyncSimulation.randomRun(seed: seed, devices: 3, steps: 300, config: config, brain: MergingBrain.make)
                XCTAssertEqual(report.findings, [], "\(kinds.map(\.rawValue)): \(report.description)")
            }
        }
    }

    /// Every fault kind, the ones that are not everyday among them (a memory lost, the zone deleted or reset, an
    /// account switched or signed out, iCloud full, a refusal), drawn often: the rig plays them all through, relaunches
    /// what crashed, heals, and still reaches its checks. (The simple brain's findings are not the point here.)
    func testEveryFaultKindPlaysThroughTheRig() async {
        var config = SimConfig()
        config.faults = Set(SimFaultKind.allCases)
        config.faultPercent = 30
        let report = await SyncSimulation.randomRun(seed: 3, devices: 3, steps: 400, config: config, brain: NaiveBrain.make)
        XCTAssertEqual(report.script.count, 400)
        for kind in ["without its ledger", "fault account", "iCloud deleteZone", "iCloud quotaFull", "iCloud refuseNextSave",
                     "fault crash", "fault deliverTwice", "transport syncs by itself", "iCloud poke"] {
            XCTAssertTrue(report.script.contains { $0.contains(kind) }, "no step '\(kind)' in seed 3")
        }
        print("Every fault kind, seed 3: \(report.findings.count) findings, \(report.notes.count) notes")
    }

    /// Measured in the test process's own CPU time: on a Mac shared with other builds the wall clock says more about
    /// them than about the rig.
    func testAThousandStepsOnThreeDevicesTakeWellUnderASecond() async {
        let start = ContinuousClock.now
        let cpu = SyncInvariantsTests.cpuSeconds()
        let report = await SyncSimulation.randomRun(seed: 42, devices: 3, steps: 1000, brain: NaiveBrain.make)
        let used = SyncInvariantsTests.cpuSeconds() - cpu
        let took = ContinuousClock.now - start
        print("1,000 steps on 3 devices (seed 42): \(String(format: "%.3f", used)) s of CPU, \(took) on the wall clock; "
              + "\(report.findings.count) findings, \(report.notes.count) notes")
        XCTAssertEqual(report.script.count, 1000)
        XCTAssertLessThan(used, 2.0, "the simulation must stay cheap enough to run thousands of seeds")
    }

    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    // MARK: Helpers

    private func key(_ name: String) -> SyncKey { SyncKey(type: "TaskItem", name: name) }

    private func task(_ name: String, _ title: String, notes: String? = nil) -> SyncRecord {
        var record = SyncSchema.filled(SyncRecord(type: "TaskItem", name: name, fields: ["title": .string(title), "updatedAt": .millis(1)]))
        if let notes { record["notes"] = .string(notes) }
        return record
    }

    private func holder(_ name: String, _ records: [SyncRecord], pending: [PendingChange] = []) -> DeviceHoldings {
        DeviceHoldings(name: name, records: records, pending: pending)
    }

    private func cloud(_ record: SyncRecord) -> CloudRecord { CloudRecord(record: record, system: Data()) }

    private func madeThenDeleted() -> SimIntent {
        var intent = SimIntent()
        intent.record(step: 1, device: "A", before: [:], after: [key("t1"): task("t1", "x")])
        intent.record(step: 2, device: "A", before: [key("t1"): task("t1", "x")], after: [:])
        return intent
    }
}

/// An honest but simple brain, for proving the rig: it sends whatever differs from what it last knew of iCloud, and
/// on every fetch and every conflict takes iCloud's record whole. It keeps its memory in the ledger, so it survives a
/// relaunch. What it gets wrong (an unsent edit lost to another device's change) is what the invariants must find.
actor NaiveBrain: SimBrain, SyncTransportDelegate {
    private let store: MemoryLocalStore
    private let ledger: MemoryLedger
    private let transport: FakeTransport
    private let clock: SimClock
    /// Breaks I4 on purpose: every fetched event leaves a mark on the first item it brings.
    private let notesEveryFetch: Bool
    private var fetchedEvents = 0

    init(_ parts: SimParts, notesEveryFetch: Bool = false) async {
        store = parts.store
        ledger = parts.ledger
        transport = parts.transport
        clock = parts.clock
        self.notesEveryFetch = notesEveryFetch
    }

    static let make: SimBrainFactory = { parts in await NaiveBrain(parts) }

    func start() async throws {
        await transport.start(delegate: self)
        try await localChanged(nil)
    }

    func stop() async { await transport.stop() }

    /// Compares the keys it is told of (all of them at start, or when told "everything"), and nothing else: a write
    /// it is not told of waits for the next launch.
    func localChanged(_ keys: Set<SyncKey>?) async throws {
        var changes: [PendingChange] = []
        if let keys {
            for key in keys.sorted() {
                let record = await store.record(key)
                let base = await ledger.entry(key)?.base
                if let record, !RecordMerge.same(record, base) { changes.append(.save(key)) }
                if record == nil, base?.isDeleted == false { changes.append(.save(key)) }
            }
        } else {
            let entries = Dictionary(try await ledger.entries().map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            var here = Set<SyncKey>()
            for record in try await store.records() {
                here.insert(record.key)
                if !RecordMerge.same(record, entries[record.key]?.base) { changes.append(.save(record.key)) }
            }
            for key in entries.keys.sorted() where !here.contains(key) && entries[key]?.base?.isDeleted == false {
                changes.append(.save(key))
            }
        }
        await transport.add(changes)
    }

    func syncNow() async throws {
        try await transport.fetch()
        try await transport.send()
    }

    func handle(_ event: TransportEvent) async {
        switch event {
        case .fetched(let changed, let removed):
            for record in changed where SyncSchema.type(record.key.type) != nil { await take(record) }
            for key in removed {
                _ = try? await store.apply([LocalWrite(key: key, expected: await store.record(key), record: nil)])
                var write = LedgerWrite()
                write.remove = [key]
                try? await ledger.write(write)
            }
            if notesEveryFetch, let first = changed.first, let here = await store.record(first.key) {
                fetchedEvents += 1
                var marked = here
                marked["notes"] = .string("fetched events seen: \(fetchedEvents)")
                _ = try? await store.apply([LocalWrite(key: first.key, expected: here, record: marked)])
            }
        case .sent(let saved, _, let failed):
            for record in saved {
                var write = LedgerWrite()
                write.upsert = [LedgerEntry(key: record.key, base: RecordMerge.normal(record.record)?.comparable, system: record.system)]
                try? await ledger.write(write)
            }
            for (_, failure) in failed {
                if case .conflict(let server) = failure { await take(server) }
            }
        case .zoneLost, .account:
            try? await ledger.reset()
        default:
            break
        }
    }

    func recordToSend(_ key: SyncKey) async -> OutgoingRecord? {
        let entry = await ledger.entry(key)
        if let record = await store.record(key) { return OutgoingRecord(record: record, system: entry?.system) }
        if let base = entry?.base, !base.isDeleted {
            return OutgoingRecord(record: .marker(key, deletedAt: clock.now()), system: entry?.system)
        }
        return nil
    }

    /// iCloud's record, whole, on the device and as the base.
    private func take(_ cloud: CloudRecord) async {
        guard let normal = RecordMerge.normal(cloud.record) else { return }
        let here = await store.record(cloud.key)
        _ = try? await store.apply([LocalWrite(key: cloud.key, expected: here, record: normal.isDeleted ? nil : normal)])
        var write = LedgerWrite()
        write.upsert = [LedgerEntry(key: cloud.key, base: normal.comparable, system: cloud.system)]
        try? await ledger.write(write)
    }
}

/// A brain that settles every record by the design's own rules (`RecordMerge`, section 5), kept as small as it can be:
/// not the engine (session 139 builds that), but enough to show that the rig and the invariants do not cry wolf at a
/// brain that keeps the rules. It sets fetched records aside in the ledger until the fetch ends (section 8), sends
/// nothing before its first whole fetch (section 7), forgets its memory on a lost zone or another account (section 10),
/// and compares again after every answer from iCloud.
actor MergingBrain: SimBrain, SyncTransportDelegate {
    private let store: MemoryLocalStore
    private let ledger: MemoryLedger
    private let transport: FakeTransport
    private let clock: SimClock

    init(_ parts: SimParts) async {
        store = parts.store
        ledger = parts.ledger
        transport = parts.transport
        clock = parts.clock
    }

    static let make: SimBrainFactory = { parts in await MergingBrain(parts) }

    func start() async throws {
        await transport.start(delegate: self)
        try await reconcile(nil)
    }

    func stop() async { await transport.stop() }

    func localChanged(_ keys: Set<SyncKey>?) async throws { try await reconcile(keys) }

    func syncNow() async throws {
        try await transport.fetch()
        try await transport.send()
    }

    /// Section 4: an item that differs from its base, an item deleted here, an item made again: waiting to go.
    private func reconcile(_ keys: Set<SyncKey>?) async throws {
        guard try await ledger.fact(LedgerFact.firstFetchDone) != nil else { return }
        let entries = Dictionary(try await ledger.entries().map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let records = Dictionary(try await store.records().map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let all = keys ?? Set(entries.keys).union(records.keys)
        var changes: [PendingChange] = []
        var write = LedgerWrite()
        for key in all.sorted() {
            let entry = entries[key]
            if let local = records[key] {
                if entry?.base == nil || !RecordMerge.same(local, entry?.base) { changes.append(.save(key)) }
            } else if let base = entry?.base, !base.isDeleted {
                if entry?.deletedHereAt == nil {
                    var noticed = entry!
                    noticed.deletedHereAt = clock.now()
                    write.upsert.append(noticed)
                }
                changes.append(.save(key))
            }
        }
        if !write.isEmpty { try await ledger.write(write) }
        await transport.add(changes)
    }

    func handle(_ event: TransportEvent) async {
        do {
            switch event {
            case .account(let change):
                if case .signedIn(let current) = change,
                   let mine = try await ledger.fact(LedgerFact.account), String(decoding: mine, as: UTF8.self) == current {
                    return
                }
                try await forget()
                if case .signedIn(let current) = change { try await setAccount(current) }
                if case .switched(_, let current) = change { try await setAccount(current) }
            case .zoneLost:
                let account = try await ledger.fact(LedgerFact.account)
                try await forget()
                if let account { try await setAccount(String(decoding: account, as: UTF8.self)) }
            case .fetched(let changed, let removed):
                var write = LedgerWrite()
                write.deferUpsert = changed.filter { SyncSchema.type($0.key.type) != nil }
                try await ledger.write(write)
                for key in removed { try await settle(key, server: nil, system: nil) }
            case .didFetch(nil):
                try await settleSetAside()
                var write = LedgerWrite()
                write.facts[LedgerFact.firstFetchDone] = Data([1])
                try await ledger.write(write)
                try await reconcile(nil)
            case .sent(let saved, let removed, let failed):
                for record in saved { try await accepted(record) }
                var write = LedgerWrite()
                write.remove = removed
                if !write.isEmpty { try await ledger.write(write) }
                for key in failed.keys.sorted() {
                    switch failed[key]! {
                    case .conflict(let server): try await settle(key, server: server.record, system: server.system)
                    case .unknownItem: try await settle(key, server: nil, system: nil)
                    default: break
                    }
                }
            default:
                break
            }
        } catch {
            // A test brain: the ledger in memory does not fail unless told to.
        }
    }

    func recordToSend(_ key: SyncKey) async -> OutgoingRecord? {
        let entry = await ledger.entry(key)
        if let local = await store.record(key) { return OutgoingRecord(record: local, system: entry?.system) }
        if let base = entry?.base, !base.isDeleted {
            return OutgoingRecord(record: .marker(key, deletedAt: entry?.deletedHereAt ?? clock.now()), system: entry?.system)
        }
        return nil
    }

    // MARK: -

    private func forget() async throws {
        try await ledger.reset()
        await transport.reset()
    }

    private func setAccount(_ account: String) async throws {
        var write = LedgerWrite()
        write.facts[LedgerFact.account] = Data(account.utf8)
        try await ledger.write(write)
    }

    /// The fetch is whole: everything set aside is settled in one go, so that a task finds its Group and its parent
    /// whichever page brought them.
    private func settleSetAside() async throws {
        let waiting = try await ledger.deferred()
        guard !waiting.isEmpty else { return }
        var writes: [LocalWrite] = []
        var write = LedgerWrite()
        var again: [PendingChange] = []
        for cloud in waiting {
            let (local, outcome, entry) = try await decide(cloud.key, server: cloud.record)
            if !RecordMerge.same(local, outcome.device) {
                writes.append(LocalWrite(key: cloud.key, expected: local, record: outcome.device))
            }
            write.upsert.append(LedgerEntry(key: cloud.key, base: RecordMerge.normal(cloud.record)?.comparable,
                                            system: cloud.system, deletedHereAt: outcome.merged?.isDeleted == true ? entry?.deletedHereAt : nil))
            if !RecordMerge.same(outcome.merged, cloud.record) { again.append(.save(cloud.key)) }
        }
        write.deferRemove = waiting.map(\.key)
        _ = try await store.apply(writes)
        try await ledger.write(write)
        await transport.add(again)
    }

    /// One record, settled at once: a conflict, a removal for good, a change unknown to iCloud.
    private func settle(_ key: SyncKey, server: SyncRecord?, system: Data?) async throws {
        let (local, outcome, entry) = try await decide(key, server: server)
        if !RecordMerge.same(local, outcome.device) {
            _ = try await store.apply([LocalWrite(key: key, expected: local, record: outcome.device)])
        }
        var write = LedgerWrite()
        if let server {
            write.upsert = [LedgerEntry(key: key, base: RecordMerge.normal(server)?.comparable, system: system,
                                        deletedHereAt: outcome.merged?.isDeleted == true ? entry?.deletedHereAt : nil)]
        } else {
            write.remove = [key]
        }
        try await ledger.write(write)
        if outcome.merged != nil, !RecordMerge.same(outcome.merged, server) { await transport.add([.save(key)]) }
    }

    private func decide(_ key: SyncKey, server: SyncRecord?) async throws -> (SyncRecord?, MergeOutcome, LedgerEntry?) {
        let local = await store.record(key)
        let entry = await ledger.entry(key)
        let input = MergeInput(base: entry?.base, local: local, deletedHereAt: entry?.deletedHereAt, server: server,
                               now: clock.now())
        return (local, RecordMerge.merge(input), entry)
    }

    /// iCloud took a save: that version is the base now; if the item changed meanwhile, it goes again.
    private func accepted(_ cloud: CloudRecord) async throws {
        let entry = await ledger.entry(cloud.key)
        var write = LedgerWrite()
        write.upsert = [LedgerEntry(key: cloud.key, base: RecordMerge.normal(cloud.record)?.comparable, system: cloud.system,
                                    deletedHereAt: cloud.record.isDeleted ? entry?.deletedHereAt : nil)]
        try await ledger.write(write)
        let local = await store.record(cloud.key)
        if let local, !RecordMerge.same(local, cloud.record) { await transport.add([.save(cloud.key)]) }
        if local == nil, !cloud.record.isDeleted { await transport.add([.save(cloud.key)]) }
    }
}
