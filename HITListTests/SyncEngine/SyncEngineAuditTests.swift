import XCTest
import HITListCore
@testable import HITList

/// Check iCloud… on the engine (`SyncEngineAudit.compare`): what counts as the same, and each way two sides differ.
final class SyncEngineAuditTests: XCTestCase {
    private func task(_ name: String, title: String = "Buy milk", _ more: [String: SyncValue] = [:]) -> SyncRecord {
        var fields: [String: SyncValue] = ["title": .string(title), "updatedAt": .millis(1_000), "createdAt": .millis(500)]
        for (key, value) in more { fields[key] = value }
        return SyncRecord(type: "TaskItem", name: name, fields: fields)
    }

    private func group(_ name: String) -> SyncRecord {
        SyncRecord(type: "Project", name: name, fields: ["name": .string("Home"), "updatedAt": .millis(1), "createdAt": .millis(1)])
    }

    func testTheSameOnBothSidesIsTheSame() {
        let records = [task("A"), task("B"), group("G")]
        let report = SyncEngineAudit.compare(local: records, cloud: records)
        XCTAssertTrue(report.isSame)
        XCTAssertEqual(report.same, 3)
        XCTAssertEqual(report.summary, "iCloud and this device hold the same 3 items.")
    }

    /// A device holds a required field's default where iCloud's record has none (an older build's record): the
    /// same, as the merge reads it. Data is compared by its digest.
    func testDefaultsAndDataCompareAsTheMergeReadsThem() {
        let here = task("A", ["priority": .int(4), "notes": .string(""), "isCompleted": .bool(false)])
        let there = task("A")
        XCTAssertTrue(SyncEngineAudit.compare(local: [here], cloud: [there]).isSame)
        let bytes = Data([1, 2, 3])
        let mine = SyncRecord(type: "Profile", name: "profile", fields: ["avatarData": .data(bytes), "updatedAt": .millis(1), "createdAt": .millis(1)])
        let theirs = SyncRecord(type: "Profile", name: "profile", fields: ["avatarData": .digest(SyncValue.digest(of: bytes)), "updatedAt": .millis(1), "createdAt": .millis(1)])
        XCTAssertTrue(SyncEngineAudit.compare(local: [mine], cloud: [theirs]).isSame)
    }

    func testEachWayTheTwoSidesDiffer() {
        let marker = SyncRecord.marker(SyncKey(type: "TaskItem", name: "GoneThereAliveHere"), deletedAt: Date(timeIntervalSince1970: 9))
        let goneBoth = SyncRecord.marker(SyncKey(type: "TaskItem", name: "GoneBoth"), deletedAt: Date(timeIntervalSince1970: 9))
        let report = SyncEngineAudit.compare(
            local: [task("Same"), task("OnlyHere"), task("GoneThereAliveHere"), task("Differs", title: "Buy milk")],
            cloud: [task("Same"), task("OnlyThere"), marker, goneBoth, task("Differs", title: "Buy oat milk", ["priority": .int(1)])],
            waiting: 2)
        XCTAssertEqual(report.same, 1)
        XCTAssertEqual(report.onlyHere.map(\.name), ["OnlyHere"])
        XCTAssertEqual(report.onlyInCloud.map(\.name), ["OnlyThere"])
        XCTAssertEqual(report.deletedInCloud.map(\.name), ["GoneThereAliveHere"])
        XCTAssertEqual(report.different, [SyncEngineAudit.Difference(key: SyncKey(type: "TaskItem", name: "Differs"), fields: ["priority", "title"])])
        XCTAssertEqual(report.markers, 2)
        XCTAssertEqual(report.differences, 4)
        XCTAssertFalse(report.isSame)
        XCTAssertEqual(report.summary, "1 item the same; 1 on this device isn't in iCloud, 1 in iCloud isn't on this device, "
                       + "1 deleted in iCloud is still here, 1 differs. 2 changes were waiting to go when it was read.")
        XCTAssertTrue(report.logLines.contains("differs: TaskItem/Differs in priority, title"))
        XCTAssertFalse(report.logLines.joined().contains("milk"), "the log names keys and fields, never a title")
    }

    /// A reference iCloud holds to an item that is not on this device is waited for, not a difference
    /// (`dev/SYNC-ENGINE.md` section 8); the missing item itself is reported.
    func testAReferenceToAnItemThatIsNotHereIsNotADifference() {
        let here = task("A")
        let there = task("A", ["project": .reference("G"), "labels": .references(["L1", "L2"])])
        let label = SyncRecord(type: "TaskLabel", name: "L1", fields: ["name": .string("x"), "updatedAt": .millis(1), "createdAt": .millis(1)])
        var report = SyncEngineAudit.compare(local: [here], cloud: [there, group("G")])
        XCTAssertEqual(report.different, [])
        XCTAssertEqual(report.onlyInCloud.map(\.name), ["G"])
        // With the label here and not on the task, the task differs in its labels.
        report = SyncEngineAudit.compare(local: [here, label], cloud: [there, label])
        XCTAssertEqual(report.different.map(\.fields), [["labels"]])
        // A reference this device holds and iCloud does not is a difference.
        report = SyncEngineAudit.compare(local: [task("A", ["project": .reference("G")]), group("G")], cloud: [task("A"), group("G")])
        XCTAssertEqual(report.different.map(\.fields), [["project"]])
    }

    /// A newer build's type is counted and left alone; the zone's own record is not an item.
    func testUnknownTypesAndTheZonesOwnRecordAreNotCompared() {
        let meta = SyncRecord(type: SyncSchema.metaType, name: SyncSchema.metaName, fields: ["formatVersion": .int(1)])
        let newer = SyncRecord(type: "Habit", name: "H", fields: ["name": .string("x")])
        let report = SyncEngineAudit.compare(local: [task("A")], cloud: [task("A"), meta, newer])
        XCTAssertTrue(report.isSame)
        XCTAssertEqual(report.unknown, 1)
        XCTAssertEqual(report.inCloud, 1)
    }

    /// A key from a newer build on a record of a known type is not a difference: this build neither sends nor
    /// clears it.
    func testANewerBuildsFieldIsNotADifference() {
        let there = task("A", ["energy": .int(3)])
        XCTAssertTrue(SyncEngineAudit.compare(local: [task("A")], cloud: [there]).isSame)
    }
}
