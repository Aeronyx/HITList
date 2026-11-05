import XCTest
@testable import HITListCore

final class SnapshotTests: XCTestCase {
    func testRoundTrip() throws {
        let pid = UUID(), lid = UUID()
        let snap = Snapshot(
            exportedAt: Fixed.now, deviceName: "Test Mac",
            projects: [.init(id: pid, name: "Work", colorHex: "#FF0000", sortOrder: 0, createdAt: Fixed.now, updatedAt: Fixed.now)],
            labels: [.init(id: lid, name: "urgent", colorHex: "#00FF00", createdAt: Fixed.now, updatedAt: Fixed.now)],
            tasks: [.init(id: UUID(), title: "Ship it", notes: "", priority: 1, dueDate: Fixed.date(2026, 10, 22, 17), hasDueTime: true,
                          isCompleted: false, completedAt: nil, recurrence: RecurrenceRule.weekly.encoded, sortOrder: 0,
                          projectID: pid, labelIDs: [lid], createdAt: Fixed.now, updatedAt: Fixed.now)],
            filters: [.init(id: UUID(), name: "Now", query: "overdue | today", colorHex: "#0000FF", sortOrder: 0, createdAt: Fixed.now, updatedAt: Fixed.now)]
        )
        let data = try snap.jsonData()
        let back = try Snapshot.from(json: data)
        XCTAssertEqual(back, snap)
        XCTAssertEqual(back.version, Snapshot.currentVersion)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"exportedAt\" : \"2026-10-21T14:30:00Z\""))
    }

    /// A backup written by 0.3.5 or earlier has none of schema V2's keys; it must still import.
    func testABackupFromBeforeTheV2FieldsStillDecodes() throws {
        let json = """
            {"deviceName":"iPhone","exportedAt":"2026-10-21T14:30:00Z","filters":[],"labels":[],"projects":[],"version":1,
             "tasks":[{"createdAt":"2026-10-21T14:30:00Z","hasDueTime":false,"id":"6B1F3E2A-9C4D-4E5F-8A7B-1D2C3E4F5A6B",
                       "isCompleted":false,"labelIDs":[],"notes":"","priority":4,"sortOrder":0,"title":"Old",
                       "updatedAt":"2026-10-21T14:30:00Z"}]}
            """
        let snapshot = try Snapshot.from(json: Data(json.utf8))
        let task = try XCTUnwrap(snapshot.tasks.first)
        XCTAssertEqual(task.title, "Old")
        XCTAssertFalse(task.hasV2Fields)
        XCTAssertNil(task.reminderOffsetMinutes)
        XCTAssertNil(task.deadline)
    }

    func testV2FieldsRoundTrip() throws {
        let record = Snapshot.TaskRecord(id: UUID(), title: "Haircut", notes: "", priority: 1, dueDate: Fixed.date(2026, 10, 22, 11),
                                         hasDueTime: true, isCompleted: false, completedAt: nil, recurrence: nil, sortOrder: 0,
                                         projectID: nil, labelIDs: [], createdAt: Fixed.now, updatedAt: Fixed.now,
                                         reminderOffsetMinutes: 15, deadline: Fixed.date(2026, 10, 25), locationName: "Barber",
                                         flipTarget: 3, flipCount: 1, flipPeriodStart: Fixed.date(2026, 10, 20))
        let snap = Snapshot(exportedAt: Fixed.now, deviceName: "x", projects: [], labels: [], tasks: [record], filters: [])
        let back = try Snapshot.from(json: snap.jsonData())
        XCTAssertEqual(back.tasks, [record])
        XCTAssertTrue(back.tasks[0].hasV2Fields)
    }

    /// Schema V5 (brief 48): a task's own reminder moment ("!15m") goes into backups and comes back, with the
    /// record saying it was written by a build that knows the field (so a restore can tell "none" from "too old
    /// to say").
    func testTheReminderDateRoundTrips() throws {
        let record = Snapshot.TaskRecord(id: UUID(), title: "Call mom", notes: "", priority: 4, dueDate: nil, hasDueTime: false,
                                         isCompleted: false, completedAt: nil, recurrence: nil, sortOrder: 0, projectID: nil,
                                         labelIDs: [], createdAt: Fixed.now, updatedAt: Fixed.now, flipTarget: 1, flipCount: 0,
                                         reminderDate: Fixed.date(2026, 10, 21, 14, 45), schemaVersion: Snapshot.TaskRecord.currentSchemaVersion)
        XCTAssertTrue(record.hasV5Fields)
        let data = try Snapshot(exportedAt: Fixed.now, deviceName: "x", projects: [], labels: [], tasks: [record], filters: []).jsonData()
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"reminderDate\" : \"2026-10-21T14:45:00Z\""))
        let back = try Snapshot.from(json: data)
        XCTAssertEqual(back.tasks, [record])
        XCTAssertEqual(Snapshot.TaskRecord.currentSchemaVersion, 5)
    }

    func testABackupFromBeforeV5DoesNotSayAboutTheReminderDate() throws {
        let json = """
            {"deviceName":"iPhone","exportedAt":"2026-10-21T14:30:00Z","filters":[],"labels":[],"projects":[],"version":1,
             "tasks":[{"createdAt":"2026-10-21T14:30:00Z","hasDueTime":false,"id":"6B1F3E2A-9C4D-4E5F-8A7B-1D2C3E4F5A6B",
                       "isCompleted":false,"labelIDs":[],"notes":"","priority":4,"sortOrder":0,"title":"0.6.0",
                       "updatedAt":"2026-10-21T14:30:00Z","flipTarget":1,"flipCount":0}]}
            """
        let task = try XCTUnwrap(try Snapshot.from(json: Data(json.utf8)).tasks.first)
        XCTAssertTrue(task.hasV2Fields)
        XCTAssertFalse(task.hasV5Fields)
        XCTAssertNil(task.reminderDate)
    }

    func testRejectsNewerVersion() throws {
        var snap = Snapshot(deviceName: "x", projects: [], labels: [], tasks: [], filters: [])
        snap.version = 99
        let data = try snap.jsonData()
        XCTAssertThrowsError(try Snapshot.from(json: data)) { error in
            XCTAssertEqual(error as? Snapshot.SnapshotError, .unsupportedVersion(99))
        }
    }
}
