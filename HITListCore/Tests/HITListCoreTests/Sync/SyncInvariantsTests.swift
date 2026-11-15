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
