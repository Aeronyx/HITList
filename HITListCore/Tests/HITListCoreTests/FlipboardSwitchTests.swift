import XCTest
@testable import HITListCore

/// Brief 59: a Flipboard switch judged from any `FilterableTask`, without the app.
final class FlipboardSwitchTests: XCTestCase {
    private let cal = Fixed.calendar
    /// Wednesday 2026-10-21 14:30 UTC.
    private let now = Fixed.now

    private func shave(due: Date?, labels: [String] = ["flipboard"], recurring: Bool = true,
                       hasTime: Bool = false, completed: Bool = false) -> PlainTask {
        PlainTask(title: "Shave", dueDate: due, hasDueTime: hasTime, isCompleted: completed,
                  labelNames: labels, isRecurring: recurring)
    }

    // MARK: - Membership

    func testAMemberIsAnOpenRecurringTaskWithoutATimeCarryingTheLabel() {
        let due = Fixed.date(2026, 10, 25)
        XCTAssertTrue(FlipboardSwitch.isMember(shave(due: due)))
        XCTAssertTrue(FlipboardSwitch.isMember(shave(due: due, labels: ["home", "FlipBoard"])), "the label in any case")
        XCTAssertFalse(FlipboardSwitch.isMember(shave(due: due, labels: ["home"])), "no label")
        XCTAssertFalse(FlipboardSwitch.isMember(shave(due: due, recurring: false)), "no repeat")
        XCTAssertFalse(FlipboardSwitch.isMember(shave(due: due, hasTime: true)), "a time of day")
        XCTAssertFalse(FlipboardSwitch.isMember(shave(due: due, completed: true)), "completed")
        XCTAssertTrue(FlipboardSwitch.isMember(shave(due: nil)), "never flipped, no date yet")
    }

    func testTheLabelAloneIsNotMembership() {
        XCTAssertTrue(FlipboardSwitch.hasLabel(["Errands", "flipboard"]))
        XCTAssertFalse(FlipboardSwitch.hasLabel(["flip"]))
        XCTAssertFalse(FlipboardSwitch.hasLabel([]))
    }

    // MARK: - Sides

    func testGreenIsDueAfterTodayRedIsDueTodayOverdueOrUndated() {
        XCTAssertEqual(FlipboardSwitch.side(due: Fixed.date(2026, 10, 22), now: now, calendar: cal), .green, "due tomorrow")
        XCTAssertEqual(FlipboardSwitch.side(due: Fixed.date(2026, 10, 21), now: now, calendar: cal), .red, "due today")
        XCTAssertEqual(FlipboardSwitch.side(due: Fixed.date(2026, 10, 21, 23), now: now, calendar: cal), .red, "later today")
        XCTAssertEqual(FlipboardSwitch.side(due: Fixed.date(2026, 10, 14), now: now, calendar: cal), .red, "overdue")
        XCTAssertEqual(FlipboardSwitch.side(due: nil, now: now, calendar: cal), .red, "never flipped")
    }

    func testOverdueIsPastItsDueDayNotMerelyDueToday() {
        XCTAssertFalse(FlipboardSwitch.isOverdue(due: Fixed.date(2026, 10, 21), now: now, calendar: cal))
        XCTAssertTrue(FlipboardSwitch.isOverdue(due: Fixed.date(2026, 10, 20), now: now, calendar: cal))
        XCTAssertFalse(FlipboardSwitch.isOverdue(due: nil, now: now, calendar: cal))
    }

    func testTheSideOfATaskIsNilWhenItIsNotASwitch() {
        XCTAssertEqual(FlipboardSwitch.side(of: shave(due: Fixed.date(2026, 10, 30)), now: now, calendar: cal), .green)
        XCTAssertEqual(FlipboardSwitch.side(of: shave(due: Fixed.date(2026, 10, 1)), now: now, calendar: cal), .red)
        XCTAssertNil(FlipboardSwitch.side(of: shave(due: Fixed.date(2026, 10, 30), labels: []), now: now, calendar: cal))
    }
}
