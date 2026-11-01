import XCTest
import HITListCore
@testable import HITList

/// The popout pickers' pure parts: where a card goes in the window.
@MainActor
final class PickerTests: XCTestCase {

    // MARK: Placement

    /// The minimum window's content (760 × 560 less a 52 pt toolbar), in layer coordinates.
    private let window = CGRect(x: 0, y: 52, width: 760, height: 508)
    private let dateCard = CGSize(width: 320, height: 390)

    func testCardGoesBelowItsChipWithItsLeadingEdge() {
        let chip = CGRect(x: 200, y: 100, width: 80, height: 30)
        let card = CGSize(width: 280, height: 200)
        let placed = PickerPlacement.place(anchor: chip, cardSize: card, bounds: window)
        XCTAssertEqual(placed.edge, .below)
        XCTAssertEqual(placed.frame, CGRect(x: 200, y: 130 + PickerPlacement.gap, width: 280, height: 200))
    }

    func testCardGoesAboveWhenThereIsNoRoomBelow() {
        let chip = CGRect(x: 200, y: 450, width: 80, height: 30)
        let placed = PickerPlacement.place(anchor: chip, cardSize: CGSize(width: 280, height: 200), bounds: window)
        XCTAssertEqual(placed.edge, .above)
        XCTAssertEqual(placed.frame.maxY, 450 - PickerPlacement.gap)
        XCTAssertEqual(placed.frame.minX, 200)
    }

    func testCardIsClampedHorizontallyInsideTheWindow() {
        let nearRight = CGRect(x: 700, y: 100, width: 50, height: 30)
        let right = PickerPlacement.frame(anchor: nearRight, cardSize: dateCard, bounds: window)
        XCTAssertEqual(right.maxX, window.maxX - PickerPlacement.margin)
        let pastLeft = CGRect(x: -40, y: 100, width: 50, height: 30)
        let left = PickerPlacement.frame(anchor: pastLeft, cardSize: dateCard, bounds: window)
        XCTAssertEqual(left.minX, window.minX + PickerPlacement.margin)
    }

    func testCardWithNoRoomEitherSideStaysInsideOnTheRoomierSide() {
        // The quick-add chip bar in the minimum window: 390 pt fits neither below nor above.
        let chip = CGRect(x: 150, y: 210, width: 70, height: 30)
        let placed = PickerPlacement.place(anchor: chip, cardSize: dateCard, bounds: window)
        XCTAssertEqual(placed.edge, .overlapping)
        XCTAssertEqual(placed.frame.maxY, window.maxY - PickerPlacement.margin, "more room below: pinned to the bottom")
        XCTAssertTrue(window.contains(placed.frame))
        let high = CGRect(x: 150, y: 380, width: 70, height: 30)
        let up = PickerPlacement.place(anchor: high, cardSize: dateCard, bounds: window)
        XCTAssertEqual(up.frame.minY, window.minY + PickerPlacement.margin, "more room above: pinned to the top")
    }

    func testCardTallerOrWiderThanTheWindowShrinksToIt() {
        let small = CGRect(x: 0, y: 0, width: 200, height: 150)
        let frame = PickerPlacement.frame(anchor: CGRect(x: 20, y: 20, width: 40, height: 20), cardSize: dateCard, bounds: small)
        XCTAssertEqual(frame, small.insetBy(dx: PickerPlacement.margin, dy: PickerPlacement.margin))
    }

    func testEveryCardStaysInsideEveryLegalWindow() {
        let sizes = [CGSize(width: 760, height: 508), CGSize(width: 820, height: 600), CGSize(width: 1440, height: 848)]
        let cards = PickerKind.allCases.map { CGSize(width: $0.width, height: 420) }
        for size in sizes {
            let bounds = CGRect(origin: CGPoint(x: 0, y: 52), size: size)
            for x in stride(from: -20, through: size.width + 20, by: 37) {
                for y in stride(from: 52, through: 52 + size.height - 30, by: 41) {
                    for card in cards {
                        let frame = PickerPlacement.frame(anchor: CGRect(x: x, y: y, width: 90, height: 30), cardSize: card, bounds: bounds)
                        XCTAssertTrue(bounds.contains(frame), "\(frame) leaves \(bounds)")
                        XCTAssertEqual(frame.size, card)
                    }
                }
            }
        }
    }

    // MARK: HITCalendar

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func grid(_ year: Int, _ month: Int, weekStart: Int) -> [[HITCalendar.Day]] {
        HITCalendar.weeks(for: year, month: month, weekStart: weekStart, calendar: calendar)
    }

    private func assertShape(_ weeks: [[HITCalendar.Day]], weekStart: Int, inMonth: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(weeks.count, HITCalendar.weeksShown, file: file, line: line)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 }, file: file, line: line)
        XCTAssertTrue(weeks.allSatisfy { calendar.component(.weekday, from: $0[0].date) == weekStart }, "every week starts on the week start", file: file, line: line)
        let days = weeks.flatMap { $0 }
        XCTAssertEqual(days.filter(\.isInMonth).count, inMonth, file: file, line: line)
        for (a, b) in zip(days, days.dropFirst()) {
            XCTAssertEqual(calendar.dateComponents([.day], from: a.date, to: b.date).day, 1, "consecutive days", file: file, line: line)
        }
    }

    func testJanuaryGridBothWeekStarts() {
        // 1 January 2026 is a Thursday.
        let monday = grid(2026, 1, weekStart: 2)
        assertShape(monday, weekStart: 2, inMonth: 31)
        XCTAssertEqual(monday[0][0], HITCalendar.Day(date: date(2025, 12, 29), isInMonth: false), "the old year's last days lead in")
        XCTAssertEqual(monday[0][3], HITCalendar.Day(date: date(2026, 1, 1), isInMonth: true))
        XCTAssertEqual(monday[5][6].date, date(2026, 2, 8))
        let sunday = grid(2026, 1, weekStart: 1)
        assertShape(sunday, weekStart: 1, inMonth: 31)
        XCTAssertEqual(sunday[0][0].date, date(2025, 12, 28))
        XCTAssertEqual(sunday[0][4].date, date(2026, 1, 1))
    }

    func testDecemberGridRunsIntoNextYear() {
        // 1 December 2026 is a Tuesday.
        let weeks = grid(2026, 12, weekStart: 2)
        assertShape(weeks, weekStart: 2, inMonth: 31)
        XCTAssertEqual(weeks[0][0], HITCalendar.Day(date: date(2026, 11, 30), isInMonth: false))
        XCTAssertEqual(weeks[0][1].date, date(2026, 12, 1))
        XCTAssertEqual(weeks[5][6], HITCalendar.Day(date: date(2027, 1, 10), isInMonth: false))
        XCTAssertFalse(weeks.flatMap { $0 }.contains { $0.isInMonth && calendar.component(.year, from: $0.date) == 2027 },
                       "January 2027 is not December 2026")
        assertShape(grid(2026, 12, weekStart: 1), weekStart: 1, inMonth: 31)
    }

    func testLeapYearFebruary() {
        let leap = grid(2028, 2, weekStart: 2)
        assertShape(leap, weekStart: 2, inMonth: 29)
        XCTAssertTrue(leap.flatMap { $0 }.contains(HITCalendar.Day(date: date(2028, 2, 29), isInMonth: true)))
        assertShape(grid(2028, 2, weekStart: 1), weekStart: 1, inMonth: 29)
        assertShape(grid(2027, 2, weekStart: 2), weekStart: 2, inMonth: 28)
        assertShape(grid(2100, 2, weekStart: 2), weekStart: 2, inMonth: 28) // not a leap year
    }

    func testAMonthStartingOnTheWeekStartBeginsWithTheFirst() {
        // 1 February 2026 is a Sunday.
        XCTAssertEqual(grid(2026, 2, weekStart: 1)[0][0], HITCalendar.Day(date: date(2026, 2, 1), isInMonth: true))
        XCTAssertEqual(grid(2026, 2, weekStart: 2)[0][0].date, date(2026, 1, 26), "Monday start: a week of January first")
    }

    func testWeekdayInitialsFollowTheWeekStart() {
        XCTAssertEqual(HITCalendar.weekdayInitials(weekStart: 2, calendar: calendar), ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(HITCalendar.weekdayInitials(weekStart: 1, calendar: calendar), ["S", "M", "T", "W", "T", "F", "S"])
        XCTAssertEqual(HITCalendar.weekdayInitials(weekStart: 7, calendar: calendar).first, "S")
    }

    func testArrowKeysCrossMonthsAndYears() {
        XCTAssertEqual(HITCalendar.moved(date(2026, 1, 31), .nextDay, calendar: calendar), date(2026, 2, 1))
        XCTAssertEqual(HITCalendar.moved(date(2028, 3, 1), .previousDay, calendar: calendar), date(2028, 2, 29))
        XCTAssertEqual(HITCalendar.moved(date(2026, 12, 28), .nextWeek, calendar: calendar), date(2027, 1, 4))
        XCTAssertEqual(HITCalendar.moved(date(2026, 1, 3), .previousWeek, calendar: calendar), date(2025, 12, 27))
        XCTAssertEqual(HITCalendar.month(date(2026, 12, 1), adding: 1, calendar: calendar), date(2027, 1, 1))
        XCTAssertEqual(HITCalendar.firstOfMonth(date(2026, 1, 31).addingTimeInterval(3600 * 15), calendar: calendar), date(2026, 1, 1))
    }

    func testCardsFitTheQuickAddPanel() {
        for kind in PickerKind.allCases {
            XCTAssertLessThanOrEqual(kind.width, 560 - 2 * 20, "\(kind) is wider than the panel's content")
        }
    }
}
