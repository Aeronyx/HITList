import XCTest
import SwiftUI
@testable import HITList

/// Brief 114: the room inside the cards. The frames themselves are measured on a simulator by `CardInsetsUITests`;
/// these pin the arithmetic behind them.
@MainActor
final class CardInsetsTests: XCTestCase {

    // MARK: The date card's quick choices

    func testPresetsShareOneWidthWhenTheirLabelsAllow() {
        let widths = DatePresetRow.widths(ideal: [40, 50, 60, 55, 50], available: 336, spacing: 6)
        let each = (336 - 4 * 6) / 5.0
        for width in widths { XCTAssertEqual(width, each, accuracy: 0.001) }
    }

    func testAWideLabelKeepsItsWidthAndTheRestShareWhatIsLeft() {
        // "Tomorrow" and "Next week" with 8 pt either side, on the Duo's row: they keep what they need.
        let ideal: [CGFloat] = [48, 66, 70, 62, 58]
        let widths = DatePresetRow.widths(ideal: ideal, available: 340, spacing: 6)
        XCTAssertEqual(widths.reduce(0, +) + 4 * 6, 340, accuracy: 0.001, "the row is used to its end")
        for (width, wanted) in zip(widths, ideal) { XCTAssertGreaterThanOrEqual(width + 0.001, wanted, "never under its label") }
        XCTAssertEqual(widths[0], widths[4], accuracy: 0.001, "the narrow ones share one width")
        XCTAssertEqual(widths[2], 70, accuracy: 0.001, "the widest keeps its own")
    }

    func testPresetsShareTheRoomByWhatTheyWantWhenEvenTheirLabelsDoNotFit() {
        let ideal: [CGFloat] = [60, 80, 90, 80, 70]
        let widths = DatePresetRow.widths(ideal: ideal, available: 300, spacing: 6)
        XCTAssertEqual(widths.reduce(0, +), 300 - 24, accuracy: 0.001)
        XCTAssertLessThan(widths[0], widths[2])
    }

    func testPresetRowLeavesEightPointsBesideEachLabelAndSixBetweenTiles() {
        XCTAssertGreaterThanOrEqual(DatePresetRow.labelInset, 8)
        XCTAssertGreaterThanOrEqual(DatePresetRow.spacing, 6)
    }

    // MARK: The calendar's edges

    func testCalendarCirclesSitOnItsEdges() {
        // The phone's date card: 336 pt of calendar, 32 pt days.
        let width: CGFloat = 336, day: CGFloat = 32
        let outset = HITCalendar.outset(width: width, daySize: day)
        let column = (width + 2 * outset) / 7
        XCTAssertEqual((column - day) / 2, outset, accuracy: 0.001, "the first circle's edge is the calendar's edge")
        XCTAssertEqual(HITCalendar.outset(width: 100, daySize: 32), 0, "never inwards")
    }

    // MARK: The cards on a narrow screen

    func testACardIsNeverWiderThanTheScreensRoom() {
        // The iPhone Duo's outer display: 376 pt beside the bar column; the 360 pt cards ran into the column.
        let area = CGRect(x: 0, y: 15, width: 376, height: 648)
        let placed = PhonePickerPlacement.place(anchor: CGRect(x: 220, y: 256, width: 107, height: 30), area: area)
        XCTAssertEqual(placed.width, 376 - 2 * PhonePickerPlacement.margin)
        XCTAssertLessThan(placed.width ?? .infinity, PickerKind.reminder.width(room: placed.room))
        // The iPhone 16 has the room for the whole card.
        let sixteen = PhonePickerPlacement.place(anchor: CGRect(x: 220, y: 300, width: 107, height: 30),
                                                 area: CGRect(x: 0, y: 59, width: 393, height: 759))
        XCTAssertGreaterThanOrEqual(sixteen.width ?? 0, PickerKind.date.width)
    }

    func testReminderCardInsetsAreAtTheFloors() {
        XCTAssertGreaterThanOrEqual(ReminderCardMetrics.shortInset, 12)
        XCTAssertGreaterThanOrEqual(ReminderCardMetrics.inset, 16)
    }

    // MARK: The fading chip row

    func testScrollingRowFadesOnlyWhereChipsAreHidden() {
        typealias Hidden = HITScrollingChipRow<EmptyView>.Hidden
        XCTAssertEqual(Hidden.edges(offset: 0, content: 300, container: 300), Hidden(), "all of it shows: no fade")
        XCTAssertEqual(Hidden.edges(offset: 0, content: 500, container: 300), Hidden(leading: false, trailing: true))
        XCTAssertEqual(Hidden.edges(offset: 100, content: 500, container: 300), Hidden(leading: true, trailing: true))
        XCTAssertEqual(Hidden.edges(offset: 200, content: 500, container: 300), Hidden(leading: true, trailing: false))
    }
}
