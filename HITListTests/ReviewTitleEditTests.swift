import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 127's scan: Review Inbox's title edit reads the text as quick add does, and a reminder typed there is set as
/// quick add sets it. Before, the parser took "!30mb" and "!15m" out of the title and nothing kept them: the reminder
/// was lost without a word.
@MainActor
final class ReviewTitleEditTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()
    /// Saturday 31 October 2026, 2 pm.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 14))! }
    private var container: ModelContainer?

    private func reviewed(_ title: String) -> (TaskItem, ModelContext) {
        let container = ModelContainerFactory.preview()
        self.container = container
        let task = TaskItem(title: title)
        container.mainContext.insert(task)
        try? container.mainContext.save()
        return (task, container.mainContext)
    }

    private var parser: QuickAddParser { QuickAddParser(now: now, calendar: calendar) }

    func testAReminderBeforeATypedTimeIsSet() {
        let (task, context) = reviewed("Pay the bill")
        let edit = ReviewTitleEdit.apply("Pay the bill 5pm !30mb", parser: parser, to: task, in: context)
        XCTAssertTrue(edit.handled, "a date gives it its place")
        XCTAssertTrue(edit.touchesReminders)
        XCTAssertEqual(task.title, "Pay the bill")
        XCTAssertEqual(task.dueDate, calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now))
        XCTAssertTrue(task.hasDueTime)
        XCTAssertEqual(task.reminderOffsetMinutes, 30)
    }

    func testAReminderFromNowIsSet() {
        let (task, context) = reviewed("Call mom")
        let edit = ReviewTitleEdit.apply("Call mom !15m", parser: parser, to: task, in: context)
        XCTAssertFalse(edit.handled, "a reminder alone gives it no place: it stays in the review")
        XCTAssertTrue(edit.touchesReminders)
        XCTAssertEqual(task.title, "Call mom")
        XCTAssertEqual(task.reminderDate, now.addingTimeInterval(15 * 60))
        XCTAssertNil(task.dueDate)
    }

    /// No time typed: "!30mb" is the title's text, as in quick add; "!at" beside a time is the default, at it.
    func testWithoutATimeABeforeReminderStaysText() {
        let (task, context) = reviewed("Pack")
        ReviewTitleEdit.apply("Pack !30mb", parser: parser, to: task, in: context)
        XCTAssertEqual(task.title, "Pack !30mb")
        XCTAssertNil(task.reminderOffsetMinutes)

        let (other, otherContext) = reviewed("Pack")
        ReviewTitleEdit.apply("Pack 9pm !at", parser: parser, to: other, in: otherContext)
        XCTAssertEqual(other.title, "Pack")
        XCTAssertNil(other.reminderOffsetMinutes, "at the time is the default")
    }
}
