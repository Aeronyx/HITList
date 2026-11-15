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

    /// Brief 145, seed 34 (memory faults): a label's deletion arrived on A and the store took it off the task; A's person
    /// then added another label; the first label was put back elsewhere (an undo) and section 8 gave the task its label
    /// back everywhere. I2 judged the person's save as the whole set and called the label that came back a lost edit.
    /// A set of references is judged name by name: only the names a person added or removed are theirs.
    func testI2_aSetOfReferencesIsJudgedNameByName_aNameTheStoreTookOffIsNotAPersonsRemoval() {
        let l1 = SyncRecord(type: "TaskLabel", name: "l1", fields: ["name": .string("one"), "updatedAt": .millis(1)])
        let l2 = SyncRecord(type: "TaskLabel", name: "l2", fields: ["name": .string("two"), "updatedAt": .millis(1)])
        func labelled(_ names: [String]) -> SyncRecord {
            var record = task("t1", "x")
            if !names.isEmpty { record["labels"] = .references(names) }
            return record
        }
        var intent = SimIntent()
        intent.record(step: 1, device: "B", before: [:], after: [l1.key: l1, l2.key: l2])
        intent.record(step: 2, device: "A", before: [:], after: [key("t1"): labelled(["l1"])])
        // On A the store took l1 off when l1's deletion arrived (no person's action), then A's person added l2.
        intent.record(step: 3, device: "A", before: [key("t1"): labelled([])], after: [key("t1"): labelled(["l2"])])
        let both = labelled(["l1", "l2"])
        XCTAssertEqual(SyncInvariants.noLostEdit(devices: [holder("A", [both, l1, l2]), holder("B", [both, l1, l2])],
                                                 cloud: [cloud(both), cloud(l1), cloud(l2)], intent: intent), [],
                       "l1 was made with the task and nobody removed it; l2 was added by A")
        // The same history with l2 lost, or with l1 dropped, is a lost edit, named by the name.
        let onlyOne = labelled(["l1"])
        XCTAssertEqual(SyncInvariants.noLostEdit(devices: [holder("A", [onlyOne, l1, l2]), holder("B", [both, l1, l2])],
                                                 cloud: [cloud(both), cloud(l1), cloud(l2)], intent: intent).map(\.description), [
            "I2 TaskItem/t1 labels should hold →l2: device A added it at step 3 and no other device changed it; device A does not",
        ])
        let dropped = labelled(["l2"])
        XCTAssertEqual(SyncInvariants.noLostEdit(devices: [holder("A", [dropped, l1, l2]), holder("B", [dropped, l1, l2])],
                                                 cloud: [cloud(dropped), cloud(l1), cloud(l2)], intent: intent).map(\.description), [
            "I2 TaskItem/t1 labels should hold →l1: device A made it so at step 2 and nobody changed it; device A does not; device B does not; iCloud does not",
        ])
    }

    func testI2_aNameAPersonRemovedIsGoneEverywhere_andTwoDevicesTouchingOneNameAreNotJudged() {
        let l1 = SyncRecord(type: "TaskLabel", name: "l1", fields: ["name": .string("one"), "updatedAt": .millis(1)])
        func labelled(_ names: [String]) -> SyncRecord {
            var record = task("t1", "x")
            if !names.isEmpty { record["labels"] = .references(names) }
            return record
        }
        var intent = SimIntent()
        intent.record(step: 1, device: "A", before: [:], after: [l1.key: l1, key("t1"): labelled(["l1"])])
        intent.record(step: 2, device: "B", before: [key("t1"): labelled(["l1"])], after: [key("t1"): labelled([])])
        let kept = labelled(["l1"])
        XCTAssertEqual(SyncInvariants.noLostEdit(devices: [holder("A", [kept, l1])], cloud: [cloud(kept), cloud(l1)],
                                                 intent: intent).map(\.description), [
            "I2 TaskItem/t1 labels should not hold →l1: device B removed it at step 2 and no other device changed it; device A holds it; iCloud holds it",
        ])
        intent.record(step: 3, device: "A", before: [key("t1"): labelled(["l1"])], after: [key("t1"): labelled([])])
        intent.record(step: 4, device: "A", before: [key("t1"): labelled([])], after: [key("t1"): labelled(["l1"])])
        XCTAssertEqual(SyncInvariants.noLostEdit(devices: [holder("A", [kept, l1])], cloud: [cloud(kept), cloud(l1)],
                                                 intent: intent), [], "A and B both touched l1: either outcome")
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

    // MARK: I9 References kept

    func testI9_holdsWhenTheDeviceThatDroppedAReferenceHadAPersonChangeIt() {
        var placed = task("t1", "x")
        placed["project"] = .reference("g")
        var intent = SimIntent()
        intent.record(step: 1, device: "A", before: [:], after: [key("t1"): placed])
        intent.record(step: 2, device: "B", before: [key("t1"): placed], after: [key("t1"): task("t1", "x")])
        intent.recordDrops(step: 3, [FakeCloud.ReferenceDrop(device: "B", key: key("t1"), field: "project", removed: ["g"])])
        XCTAssertEqual(SyncInvariants.referencesKept(intent: intent), [])
    }

    func testI9_breaksWhenADeviceDroppedAReferenceNoPersonThereChanged() {
        var placed = task("t1", "x")
        placed["project"] = .reference("g")
        var intent = SimIntent()
        intent.record(step: 1, device: "A", before: [:], after: [key("t1"): placed])
        intent.recordDrops(step: 3, [FakeCloud.ReferenceDrop(device: "B", key: key("t1"), field: "project", removed: ["g"])])
        XCTAssertEqual(SyncInvariants.referencesKept(intent: intent).map(\.description), [
            "I9 device B sent TaskItem/t1 without project →g at step 3, which iCloud held; no person on B changed project",
        ])
    }

    func testI1AndI2_judgeIcloudAsADeviceShowsIt_aReferenceToAnItemThatIsGoneIsNoDifference() {
        var dangling = task("t1", "x")
        dangling["labels"] = .references(["gone"])
        var intent = SimIntent()
        intent.record(step: 1, device: "A", before: [:], after: [key("t1"): task("t1", "x")])
        let devices = [holder("A", [task("t1", "x")])]
        XCTAssertEqual(SyncInvariants.sameEverywhere(devices: devices, cloud: [cloud(dangling)]), [])
        XCTAssertEqual(SyncInvariants.noLostEdit(devices: devices, cloud: [cloud(dangling)], intent: intent), [])
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

    /// Section 8 as rewritten (4d402a1), on the case the rig found against the first version (seeds 58 and 62 of 100): a
    /// task sent in one batch, its label in the next, and a device that fetches in between. Under the first design that
    /// device wrote the task without the label and sent it so, and the label was gone from the task everywhere (I2
    /// said so). Now it waits for the label, sends nothing of it, and shows it when it arrives: every invariant holds.
    func testSection8_aReferenceToALateTargetIsWaitedForAndKeptEverywhere() async {
        var config = SimConfig()
        config.batchSize = 1
        let sim = SyncSimulation(seed: 1, config: config, brain: MergingBrain.make)
        await sim.addDevice("A")
        await sim.addDevice("C")
        let t = key("11111111-0000-0000-0000-000000000001")
        let l = SyncKey(type: "TaskLabel", name: "22222222-0000-0000-0000-000000000002")
        await sim.play([
            .act("C", .put(SyncRecord(key: t, fields: ["title": .string("task")]))),
            .act("C", .put(SyncRecord(key: l, fields: ["name": .string("label")]))),
            .act("C", .edit(t, ["labels": .references([l.name])])),
            // The task already waits to go ahead of the label; C sends it, and the network drops before the label.
            .fault("C", .dropNetwork(after: 1)),
            .sync("C"),
            // A fetches the task and not the label: it waits for it, and sends nothing.
            .sync("A"),
            .fault("C", .network(up: true)),
            .sync("C"),
        ])
        let findings = await sim.check()
        XCTAssertEqual(findings, [], findings.map(\.description).joined(separator: "\n"))
        let inCloud = await sim.cloud.record(t)?.record["labels"]
        XCTAssertEqual(inCloud, .references([l.name]))
        let onA = await sim.device("A")?.store.record(t)?["labels"]
        XCTAssertEqual(onA, .references([l.name]))
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

    /// Seeds that once found something, kept for wave 2 to run against the real brain: swap `MergingBrain.make` for
    /// `SyncCore` wrapped as a `SimBrain`. Each says what it found, under which faults, and the record names to trace it
    /// by (`HITLIST_SIM_TRACE=<seed> HITLIST_SIM_KEYS=<keys> [HITLIST_SIM_FAULTS=<faults>] swift test -c release
    /// -Xswiftc -enable-testing --filter testTrace`). A seed whose keys no longer appear in its script means the
    /// generator has drifted and the seed no longer plays the case: find it again with `testManySeeds`.
    struct KeptSeed {
        var seed: UInt64
        var steps = 300
        /// "everyday", "ledger", "zone" or "memory" (`HITLIST_SIM_FAULTS`).
        var faults = "everyday"
        var keys: [String]
        var found: String
    }

    static let keptSeeds: [KeptSeed] = [
        KeptSeed(seed: 58, keys: ["29222198", "039713C8"],
                 found: "section 8's first version: a label sent a batch after its task was cleared from the task everywhere"),
        KeptSeed(seed: 62, keys: ["D3B8B1A9", "D88598D6"],
                 found: "section 8's first version, a parent reference cleared everywhere"),
        KeptSeed(seed: 60, keys: ["A34441B4"],
                 found: "deletedHereAt kept after an undo: a second deletion offline carried the first one's time; M8 brought the item back (I3)"),
        KeptSeed(seed: 85, keys: ["C0B472C5", "473723E0"],
                 found: "a sub-task two levels under a deleted task goes with it (the model's cascade, at any depth)"),
        KeptSeed(seed: 27, steps: 500, keys: ["project"],
                 found: "a device's clearing of a deleted Group's reference beat a person's later move in M7 (reviewer; section 8 now forbids the clearing)"),
        KeptSeed(seed: 4, faults: "zone", keys: ["33D4268A"],
                 found: "the transport's state lost, then the zone: no zoneLost ever comes; a kept ledger left items out of iCloud (I1; T12 now)"),
        KeptSeed(seed: 18, faults: "memory", keys: ["hears"],
                 found: "a crash halfway through a fetch in the last round: the rig called it quiet with a device short of iCloud (rig bug, fixed)"),
        KeptSeed(seed: 1, faults: "ledger", keys: ["29636A12"],
                 found: "edits made before a lost memory finished its first fetch (the model's exposure, fixed)"),
        KeptSeed(seed: 7, keys: ["641C6D76", "B0C90D89"], found: "section 8's first version, a parent reference"),
        KeptSeed(seed: 18, keys: ["7B99BE4C", "3D715A3A"], found: "section 8's first version, a label"),
        KeptSeed(seed: 99, keys: ["4A88A6F0", "8C1632AF"], found: "section 8's first version, a label"),
        KeptSeed(seed: 16, faults: "memory", keys: ["5A7ADDAC", "78E1A262"], found: "section 8's first version, a label"),
    ]

    static func config(_ faults: String) -> SimConfig {
        var config = SimConfig()
        switch faults {
        case "ledger": config.faults = SimFaultKind.everyday.union([.ledgerLost]); config.faultPercent = 10
        case "zone": config.faults = SimFaultKind.everyday.union([.zoneDeleted, .zoneReset]); config.faultPercent = 10
        case "memory": config.faults = SimFaultKind.everyday.union([.ledgerLost, .zoneDeleted, .zoneReset])
        default: break
        }
        return config
    }

    /// Every kept seed with the brain under test: no findings. (Wave 2: the same list with `SyncCore`.)
    func testKeptSeeds() async {
        for kept in SyncInvariantsTests.keptSeeds {
            let report = await SyncSimulation.randomRun(seed: kept.seed, devices: 3, steps: kept.steps,
                                                        config: SyncInvariantsTests.config(kept.faults), brain: MergingBrain.make)
            XCTAssertEqual(report.findings, [], "seed \(kept.seed) (\(kept.faults)), which found: \(kept.found)\n\(report.description)")
            // Record names are hex; a word ("project", "hears") is a trace filter, not a name to look for.
            let names = kept.keys.filter { $0.allSatisfy(\.isHexDigit) }
            let plays = names.allSatisfy { name in report.script.contains { $0.contains(name) } }
            print("Kept seed \(kept.seed) (\(kept.faults), \(kept.steps) steps): \(names.isEmpty ? "no record names to look for" : (plays ? "still plays \(names.joined(separator: ", "))" : "DRIFTED: \(names.joined(separator: ", ")) not in its script"))")
        }
    }

    /// Many seeds, only when asked: `HITLIST_SIM_SEEDS=100 swift test -c release -Xswiftc -enable-testing --filter
    /// testManySeeds` (optionally `HITLIST_SIM_STEPS`, default 300, and `HITLIST_SIM_FAULTS=memory` to add the faults
    /// that lose a memory). Runs the rules-keeping brain; wave 2 swaps in `SyncCore`. Prints every seed with a finding.
    func testManySeeds_whenAskedFor() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let count = environment["HITLIST_SIM_SEEDS"].flatMap(UInt64.init), count > 0 else {
            throw XCTSkip("set HITLIST_SIM_SEEDS to run many seeds")
        }
        let steps = environment["HITLIST_SIM_STEPS"].flatMap(Int.init) ?? 300
        var config = SimConfig()
        if environment["HITLIST_SIM_FAULTS"] == "memory" {
            config.faults = SimFaultKind.everyday.union([.ledgerLost, .zoneDeleted, .zoneReset])
        }
        var failing: [UInt64] = []
        for seed in UInt64(1)...count {
            let report = await SyncSimulation.randomRun(seed: seed, devices: 3, steps: steps, config: config, brain: MergingBrain.make)
            if !report.findings.isEmpty {
                failing.append(seed)
                print(report.description)
            }
        }
        print("\(count) seeds × \(steps) steps: \(failing.isEmpty ? "every invariant holds" : "findings on seeds \(failing)")")
        XCTAssertEqual(failing, [])
    }

    /// One seed traced, only when asked: `HITLIST_SIM_TRACE=<seed> HITLIST_SIM_KEYS=<name prefixes, comma separated>
    /// swift test --filter testTrace` prints the script and the rules-keeping brain's log lines that name those keys.
    func testTrace_whenAskedFor() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let seed = environment["HITLIST_SIM_TRACE"].flatMap(UInt64.init) else {
            throw XCTSkip("set HITLIST_SIM_TRACE to a seed")
        }
        let keys = (environment["HITLIST_SIM_KEYS"] ?? "").split(separator: ",").map(String.init)
        let lines = FakeWords()
        var config = SimConfig()
        config.log = { line in if keys.contains(where: { line.contains($0) }) { lines.append(line) } }
        let faults = SyncInvariantsTests.config(environment["HITLIST_SIM_FAULTS"] ?? "everyday")
        config.faults = faults.faults
        config.faultPercent = faults.faultPercent
        let steps = environment["HITLIST_SIM_STEPS"].flatMap(Int.init) ?? 300
        let report = await SyncSimulation.randomRun(seed: seed, devices: 3, steps: steps, config: config, brain: MergingBrain.make)
        for line in report.script where keys.contains(where: { line.contains($0) }) || line.contains("fault") { print("SCRIPT \(line)") }
        for line in lines.all { print("BRAIN \(line)") }
        for line in report.notes { print("NOTE \(line)") }
        print(report.description)
    }

    /// Every fault kind, the ones that are not everyday among them (a memory lost, the zone deleted or reset, an
    /// account switched or signed out, iCloud full, a refusal), drawn often: the rig plays them all through, relaunches
    /// what crashed, heals, and still reaches its checks. (The simple brain's findings are not the point here.)
    func testEveryFaultKindPlaysThroughTheRig() async {
        var config = SimConfig()
        config.faults = Set(SimFaultKind.allCases)
        config.faultPercent = 30
        // Two seeds, so that every kind shows whatever the draw (a kind added later moves each seed's draws).
        var script: [String] = []
        for seed: UInt64 in [3, 4] {
            let report = await SyncSimulation.randomRun(seed: seed, devices: 3, steps: 400, config: config, brain: NaiveBrain.make)
            XCTAssertEqual(report.script.count, 400)
            script += report.script
            print("Every fault kind, seed \(seed): \(report.findings.count) findings, \(report.notes.count) notes")
        }
        for kind in ["without its ledger", "fault account", "iCloud deleteZone", "iCloud quotaFull", "iCloud refuseNextSave",
                     "fault crash", "fault deliverTwice", "transport syncs by itself", "iCloud poke", "fault network down",
                     "fault store loses"] {
            XCTAssertTrue(script.contains { $0.contains(kind) }, "no step '\(kind)' in seeds 3 and 4")
        }
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
                _ = try? await store.applyCascading([LocalWrite(key: key, expected: await store.record(key), record: nil)])
                var write = LedgerWrite()
                write.remove = [key]
                try? await ledger.write(write)
            }
            if notesEveryFetch, let first = changed.first, let here = await store.record(first.key) {
                fetchedEvents += 1
                var marked = here
                marked["notes"] = .string("fetched events seen: \(fetchedEvents)")
                _ = try? await store.applyCascading([LocalWrite(key: first.key, expected: here, record: marked)])
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
        _ = try? await store.applyCascading([LocalWrite(key: cloud.key, expected: here, record: normal.isDeleted ? nil : normal)])
        var write = LedgerWrite()
        write.upsert = [LedgerEntry(key: cloud.key, base: normal.comparable, system: cloud.system)]
        try? await ledger.write(write)
    }
}

/// A brain that settles every record by the design's own rules (`RecordMerge`, section 5), kept as small as it can be:
/// not the engine (session 139 builds that), but enough to show that the rig and the invariants do not cry wolf at a
/// brain that keeps the rules. It sets fetched records aside in the ledger until the fetch ends (section 8), keeps the
/// references a record is waiting for and never clears one itself (section 8 as rewritten at 4d402a1), sends what is
/// pointed at before what points at it, sends nothing before its first whole fetch (section 7), forgets its memory on
/// a lost zone and on every account event (section 10, T12), and compares again after every answer from iCloud.
actor MergingBrain: SimBrain, SyncTransportDelegate {
    private let store: MemoryLocalStore
    private let ledger: MemoryLedger
    private let transport: FakeTransport
    private let clock: SimClock
    private let log: @Sendable (String) -> Void
    private let device: String

    init(_ parts: SimParts) async {
        store = parts.store
        ledger = parts.ledger
        transport = parts.transport
        clock = parts.clock
        log = parts.log
        device = parts.device
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

    /// Section 4: an item that differs from its base, an item deleted here, an item made again: waiting to go. Each
    /// record is compared as it would be with every reference honoured (section 8).
    private func reconcile(_ keys: Set<SyncKey>?) async throws {
        guard try await ledger.fact(LedgerFact.firstFetchDone) != nil else {
            log("\(device) reconcile skipped: no whole fetch yet")
            return
        }
        try await honourWaits()
        let entries = Dictionary(try await ledger.entries().map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let records = Dictionary(try await store.records().map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var waits = try await allWaits()
        let all = keys ?? Set(entries.keys).union(records.keys)
        var changes: [PendingChange] = []
        var write = LedgerWrite()
        for key in all.sorted() {
            let entry = entries[key]
            if let local = records[key] {
                // A reference the base holds to an item that is not here (deleted here, or never arrived): waited for,
                // not a change. A to-one field the person filled is theirs.
                if let base = entry?.base, !base.isDeleted {
                    var wait = waits[key] ?? [:]
                    for (field, value) in references(base) {
                        switch value {
                        case .reference(let name):
                            if local.fields[field] == nil, !present(field, name, key, records) { wait[field] = value }
                        case .referenceList(let names):
                            var held: Set<String> = []
                            if case .referenceList(let list)? = local.fields[field] { held = Set(list) }
                            let missing = names.filter { !held.contains($0) && !present(field, $0, key, records) }
                            var waited: Set<String> = []
                            if case .referenceList(let old)? = wait[field] { waited = Set(old) }
                            if !missing.isEmpty || !waited.isEmpty { wait[field] = .references(waited.union(missing)) }
                        default: break
                        }
                    }
                    for (field, value) in wait {
                        if case .reference = value, local.fields[field] != nil { wait[field] = nil }
                    }
                    if wait != (waits[key] ?? [:]) {
                        waits[key] = wait
                        if wait.isEmpty { write.deferRemove.append(waitKey(key)) } else { write.deferUpsert.append(waitRecord(key, wait)) }
                    }
                }
                let whole = honoured(local, waits[key])
                if entry?.base == nil || !RecordMerge.same(whole, entry?.base) { changes.append(.save(key)) }
                if var back = entry, back.deletedHereAt != nil {
                    // Here again (an undo): the deletion noticed before is over. Kept, a later deletion would carry
                    // its old time, and M8 would bring the item back (seed 60 found it).
                    back.deletedHereAt = nil
                    write.upsert.append(back)
                }
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
        await transport.add(try await inSendingOrder(changes))
    }

    // MARK: Waiting references (section 8)

    /// The waited-for references are kept in the ledger's deferred list under a key of their own type, apart from
    /// fetched records set aside.
    private func waitKey(_ key: SyncKey) -> SyncKey { SyncKey(type: "Waiting." + key.type, name: key.name) }

    private func waitRecord(_ key: SyncKey, _ fields: [String: SyncValue]) -> CloudRecord {
        CloudRecord(record: SyncRecord(key: waitKey(key), fields: fields), system: Data())
    }

    private func allWaits() async throws -> [SyncKey: [String: SyncValue]] {
        var out: [SyncKey: [String: SyncValue]] = [:]
        for cloud in try await ledger.deferred() where cloud.key.type.hasPrefix("Waiting.") {
            out[SyncKey(type: String(cloud.key.type.dropFirst("Waiting.".count)), name: cloud.key.name)] = cloud.record.fields
        }
        return out
    }

    private func references(_ record: SyncRecord) -> [(String, SyncValue)] {
        guard let type = SyncSchema.type(record.key.type) else { return [] }
        return type.fields.compactMap { field -> (String, SyncValue)? in
            switch (field.kind, record.fields[field.key]) {
            case (.reference, let value?), (.references, let value?): return (field.key, value)
            default: return nil
            }
        }
    }

    private func target(_ field: String, of key: SyncKey) -> String? {
        switch SyncSchema.type(key.type)?.field(field)?.kind {
        case .reference(let type)?, .references(let type)?: return type
        default: return nil
        }
    }

    private func present(_ field: String, _ name: String, _ key: SyncKey, _ records: [SyncKey: SyncRecord]) -> Bool {
        guard let type = target(field, of: key) else { return true }
        return records[SyncKey(type: type, name: name)] != nil
    }

    /// The device's record with the references it waits for: what is compared, merged and sent.
    private func honoured(_ local: SyncRecord?, _ wait: [String: SyncValue]?) -> SyncRecord? {
        guard var out = local, let wait else { return local }
        for (field, value) in wait {
            switch value {
            case .reference: if out.fields[field] == nil { out.fields[field] = value }
            case .referenceList(let names):
                var held: Set<String> = []
                if case .referenceList(let list)? = out.fields[field] { held = Set(list) }
                out.fields[field] = .references(held.union(names))
            default: break
            }
        }
        return out
    }

    /// After the device was written with `merged`: what it could not show is waited for.
    private func wait(for merged: SyncRecord?, _ key: SyncKey) async throws {
        var wait: [String: SyncValue] = [:]
        if let merged, !merged.isDeleted, let here = await store.record(key) {
            for (field, value) in references(merged) {
                switch value {
                case .reference: if here.fields[field] != value { wait[field] = value }
                case .referenceList(let names):
                    var held: Set<String> = []
                    if case .referenceList(let list)? = here.fields[field] { held = Set(list) }
                    let missing = names.filter { !held.contains($0) }
                    if !missing.isEmpty { wait[field] = .references(missing) }
                default: break
                }
            }
        }
        var write = LedgerWrite()
        if wait.isEmpty { write.deferRemove = [waitKey(key)] } else { write.deferUpsert = [waitRecord(key, wait)] }
        try await ledger.write(write)
    }

    /// An item waited for is here now: its references are written on the device and stop waiting.
    private func honourWaits() async throws {
        let waits = try await allWaits()
        guard !waits.isEmpty else { return }
        for key in waits.keys.sorted() {
            guard let local = await store.record(key), let whole = honoured(local, waits[key]) else { continue }
            if whole != local { _ = try await store.applyCascading([LocalWrite(key: key, expected: local, record: whole)]) }
            try await wait(for: whole, key)
        }
    }

    /// What is pointed at before what points at it: `SyncSchema.types` order, a task after its parent.
    private func inSendingOrder(_ changes: [PendingChange]) async throws -> [PendingChange] {
        let order = Dictionary(uniqueKeysWithValues: SyncSchema.types.enumerated().map { ($1.name, $0) })
        var depth: [SyncKey: Int] = [:]
        for change in changes where change.key.type == SyncSchema.taskItem.name {
            var level = 0
            var at = await store.record(change.key)
            while case .reference(let parent)? = at?.fields["parent"], level < 8 {
                level += 1
                at = await store.record(SyncKey(type: SyncSchema.taskItem.name, name: parent))
            }
            depth[change.key] = level
        }
        return changes.enumerated().sorted { a, b in
            (order[a.element.key.type] ?? .max, depth[a.element.key] ?? 0, a.offset)
                < (order[b.element.key.type] ?? .max, depth[b.element.key] ?? 0, b.offset)
        }.map(\.element)
    }

    func handle(_ event: TransportEvent) async {
        switch event {
        case .account, .zoneLost, .didFetch: log("\(device) hears \(event)")
        case .fetched(let changed, let removed): log("\(device) hears fetched \(changed.count) changed, \(removed.count) removed")
        case .sent(let saved, _, let failed): log("\(device) hears sent \(saved.count) saved, \(failed.count) failed")
        default: break
        }
        do {
            switch event {
            case .account(let change):
                // Every account event empties the memory, a sign-in to the account it already belongs to too: that one
                // means the transport's state was lost (or could not be read), and a ledger must not outlive its
                // bookmark. A zone lost meanwhile is never announced to a state that never knew it, and bases kept
                // for records the new zone lacks would keep this device's items out of iCloud for good (seed 4 with
                // lost zones found it: I1).
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
                if !write.deferUpsert.isEmpty { try await ledger.write(write) }
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
        let waits = (try? await allWaits()) ?? [:]
        if let local = honoured(await store.record(key), waits[key]) {
            log("\(device) sends \(key): \(local.fields.keys.sorted().map { "\($0)=\(SyncInvariants.say(local.fields[$0]))" }.joined(separator: " "))")
            return OutgoingRecord(record: local, system: entry?.system)
        }
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
        let waiting = try await ledger.deferred().filter { !$0.key.type.hasPrefix("Waiting.") }
        guard !waiting.isEmpty else { return }
        let waits = try await allWaits()
        var writes: [LocalWrite] = []
        var write = LedgerWrite()
        var again: [PendingChange] = []
        var merged: [SyncKey: SyncRecord?] = [:]
        for cloud in waiting {
            let (local, outcome, entry) = try await decide(cloud.key, server: cloud.record, waits: waits)
            merged[cloud.key] = .some(outcome.device)
            log("\(device) settles fetched \(cloud.key) by \(outcome.rule.rawValue): here \(local.map(SyncInvariants.sketch) ?? "nothing"), iCloud \(SyncInvariants.sketch(cloud.record)) \(cloud.record.fields.keys.sorted().map { "\($0)=\(SyncInvariants.say(cloud.record.fields[$0]))" }.joined(separator: " "))")
            if !RecordMerge.same(local, outcome.device) {
                writes.append(LocalWrite(key: cloud.key, expected: local, record: outcome.device))
            }
            write.upsert.append(LedgerEntry(key: cloud.key, base: RecordMerge.normal(cloud.record)?.comparable,
                                            system: cloud.system, deletedHereAt: outcome.merged?.isDeleted == true ? entry?.deletedHereAt : nil))
            if !RecordMerge.same(outcome.merged, cloud.record) { again.append(.save(cloud.key)) }
        }
        write.deferRemove = waiting.map(\.key)
        _ = try await store.applyCascading(writes)
        try await ledger.write(write)
        for key in merged.keys.sorted() { try await wait(for: merged[key] ?? nil, key) }
        try await honourWaits()
        await transport.add(try await inSendingOrder(again))
    }

    /// One record, settled at once: a conflict, a removal for good, a change unknown to iCloud.
    private func settle(_ key: SyncKey, server: SyncRecord?, system: Data?) async throws {
        let (local, outcome, entry) = try await decide(key, server: server, waits: try await allWaits())
        log("\(device) settles \(key) by \(outcome.rule.rawValue) (conflict or removal): iCloud \(server.map(SyncInvariants.sketch) ?? "nothing")")
        if !RecordMerge.same(local, outcome.device) {
            _ = try await store.applyCascading([LocalWrite(key: key, expected: local, record: outcome.device)])
        }
        var write = LedgerWrite()
        if let server {
            write.upsert = [LedgerEntry(key: key, base: RecordMerge.normal(server)?.comparable, system: system,
                                        deletedHereAt: outcome.merged?.isDeleted == true ? entry?.deletedHereAt : nil)]
        } else {
            write.remove = [key]
        }
        try await ledger.write(write)
        try await wait(for: outcome.device, key)
        if outcome.merged != nil, !RecordMerge.same(outcome.merged, server) { await transport.add([.save(key)]) }
    }

    /// The merge, with the device's record as it would be with every waited-for reference honoured (section 8). The
    /// first value is the device's record as it is, for `LocalWrite.expected`.
    private func decide(_ key: SyncKey, server: SyncRecord?, waits: [SyncKey: [String: SyncValue]]) async throws
        -> (SyncRecord?, MergeOutcome, LedgerEntry?) {
        let local = await store.record(key)
        let entry = await ledger.entry(key)
        let input = MergeInput(base: entry?.base, local: honoured(local, waits[key]), deletedHereAt: entry?.deletedHereAt,
                               server: server)
        return (local, RecordMerge.merge(input), entry)
    }

    /// iCloud took a save: that version is the base now; if the item changed meanwhile, it goes again.
    private func accepted(_ cloud: CloudRecord) async throws {
        let entry = await ledger.entry(cloud.key)
        var write = LedgerWrite()
        write.upsert = [LedgerEntry(key: cloud.key, base: RecordMerge.normal(cloud.record)?.comparable, system: cloud.system,
                                    deletedHereAt: cloud.record.isDeleted ? entry?.deletedHereAt : nil)]
        try await ledger.write(write)
        let local = honoured(await store.record(cloud.key), try await allWaits()[cloud.key])
        if let local, !RecordMerge.same(local, cloud.record) { await transport.add([.save(cloud.key)]) }
        if local == nil, !cloud.record.isDeleted { await transport.add([.save(cloud.key)]) }
    }
}

extension MemoryLocalStore {
    /// The test brains' way of writing (`NaiveBrain`, `MergingBrain`): a task's deletion takes the sub-tasks the device
    /// holds under it, named, as the store's cascade did before the store became strict (the supervisor's rule of
    /// 2026-11-15: the store deletes exactly the rows the writes name). These simple brains keep the old behaviour on
    /// purpose; `SyncCore` decides each sub-task (review finding 1).
    func applyCascading(_ writes: [LocalWrite]) async throws -> Set<SyncKey> {
        guard writes.contains(where: { $0.record == nil && $0.key.type == "TaskItem" }) else { return try await apply(writes) }
        var all = writes
        let named = Set(writes.map(\.key))
        let held = try await records()
        var next = writes.filter { $0.record == nil && $0.key.type == "TaskItem" }.map(\.key.name)
        var seen = Set(next)
        while let parent = next.popLast() {
            for record in held where record.key.type == "TaskItem" && record.fields["parent"] == .reference(parent) {
                guard seen.insert(record.key.name).inserted else { continue }
                if !named.contains(record.key) { all.append(LocalWrite(key: record.key, expected: record, record: nil)) }
                next.append(record.key.name)
            }
        }
        return try await apply(all).intersection(named)
    }
}
