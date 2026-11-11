import XCTest
@testable import HITListCore

/// Brief 74: the file the app writes for its widgets.
final class WidgetSnapshotTests: XCTestCase {
    private func sample() -> WidgetSnapshot {
        let board = UUID()
        let clock = WidgetSnapshot.Clock(SwitchboardSchedule(cadence: .weekly, resetMinutes: 5 * 60, resetWeekday: 1))
        let floss = WidgetSnapshot.Task(id: UUID(), title: "Floss", priority: 4, due: Fixed.date(2026, 10, 22),
                                        hasTime: false, groupName: nil, groupColorHex: nil, labelNames: ["flipboard"],
                                        isRecurring: true, createdAt: Fixed.date(2026, 10, 1), isShared: false,
                                        switchOptedIn: true, switchboardID: board, clock: clock)
        let call = WidgetSnapshot.Task(id: UUID(), title: "Call Sam", priority: 1, due: Fixed.date(2026, 10, 21, 15),
                                       hasTime: true, groupName: "Work", groupColorHex: "#E5484D", labelNames: ["calls"],
                                       isRecurring: false, createdAt: nil, isShared: false, switchOptedIn: false,
                                       switchboardID: nil, clock: nil)
        return WidgetSnapshot(writtenAt: Fixed.now, themeID: "moss", weekStart: 1, tasks: [floss, call],
                              looseSwitchIDs: [],
                              switchboards: [.init(id: board, name: "Deep Clean", line: "Weekly · resets Sunday 5:00 AM",
                                                   clock: clock, switchIDs: [floss.id])])
    }

    func testItRoundTripsThroughJSON() throws {
        let snapshot = sample()
        let data = try snapshot.encoded()
        XCTAssertEqual(try WidgetSnapshot.decode(data), snapshot)
        XCTAssertEqual(try WidgetSnapshot.decode(data).format, WidgetSnapshot.currentFormat)
    }

    func testAFileFromALaterBuildWithMoreFieldsStillReads() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: sample().encoded()) as? [String: Any])
        object["somethingNew"] = ["a": 1]
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try WidgetSnapshot.decode(data).tasks.count, 2)
    }

    func testATaskIsAFilterableTaskTheListsJudge() {
        let snapshot = sample()
        let floss = snapshot.tasks[0], call = snapshot.tasks[1]
        XCTAssertTrue(FlipboardSwitch.isMember(floss))
        XCTAssertEqual(floss.filterSwitchboard, SwitchboardSchedule(cadence: .weekly, resetMinutes: 300, resetWeekday: 1))
        XCTAssertTrue(floss.filterSwitchOptedIn)
        XCTAssertFalse(floss.filterIsCompleted)
        XCTAssertFalse(floss.filterIsSubtask)
        XCTAssertEqual(call.filterTitle, "Call Sam")
        XCTAssertEqual(call.filterPriority, 1)
        XCTAssertEqual(call.filterDueDate, Fixed.date(2026, 10, 21, 15))
        XCTAssertTrue(call.filterHasDueTime)
        XCTAssertEqual(call.filterProjectName, "Work")
        XCTAssertEqual(call.filterLabelNames, ["calls"])
        XCTAssertNil(call.filterSwitchboard)
    }

    func testTheClockKeepsAnUnknownCadenceAsDaily() {
        let clock = WidgetSnapshot.Clock(cadence: "fortnightly", resetMinutes: 60, resetWeekday: 3)
        XCTAssertEqual(clock.schedule, SwitchboardSchedule(cadence: .daily, resetMinutes: 60, resetWeekday: 3))
    }

    func testTheWrittenMomentAloneIsNotAChange() {
        let a = sample()
        var b = a
        b.writtenAt = a.writtenAt.addingTimeInterval(60)
        XCTAssertTrue(a.isSameContent(as: b))
        b.themeID = "slate"
        XCTAssertFalse(a.isSameContent(as: b))
    }

    /// The file sits beside the store and is named after it, so a side store (HITLIST_STORE_SUFFIX) has its own and a
    /// Debug run never feeds the real widgets. The app's `ModelContainerFactory.storeName(suffix:)` follows the same
    /// rule (WidgetSnapshotWriterTests checks the two agree).
    func testEachStoreHasItsOwnFile() {
        XCTAssertEqual(WidgetSnapshot.fileName(suffix: nil), "HITList.widgets.json")
        XCTAssertEqual(WidgetSnapshot.fileName(suffix: ""), "HITList.widgets.json")
        XCTAssertEqual(WidgetSnapshot.fileName(suffix: "s74"), "HITList-s74.widgets.json")
        XCTAssertEqual(WidgetSnapshot.fileName(suffix: "demo-2"), "HITList-demo-2.widgets.json")
        XCTAssertEqual(WidgetSnapshot.fileName(suffix: "../x"), "HITList.widgets.json", "never a path")
        XCTAssertEqual(WidgetSnapshot.mainFileName, "HITList.widgets.json")
    }
}
