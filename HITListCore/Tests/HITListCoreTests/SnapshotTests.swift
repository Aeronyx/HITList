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

    func testRejectsNewerVersion() throws {
        var snap = Snapshot(deviceName: "x", projects: [], labels: [], tasks: [], filters: [])
        snap.version = 99
        let data = try snap.jsonData()
        XCTAssertThrowsError(try Snapshot.from(json: data)) { error in
            XCTAssertEqual(error as? Snapshot.SnapshotError, .unsupportedVersion(99))
        }
    }
}
