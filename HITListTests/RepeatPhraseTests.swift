import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 71: a repeat with a place ("every month on the 1st", "every first Monday", "every year on Mar 3")
/// saved from quick add, completed, and shown by the Repeat card, which keeps a rule it cannot edit.
@MainActor
final class RepeatPhraseTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testPayRentOnThe1stSavesAndRollsOverToThe1st() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let now = date(2026, 10, 21, 14, 30)
        let parsed = QuickAddParser(now: now, calendar: calendar).parse("Pay rent every month on the 1st 9am p1 #Finance")
        let task = try TaskActions.create(from: parsed, defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.title, "Pay rent")
        XCTAssertEqual(task.dueDate, date(2026, 11, 1, 9))
        XCTAssertEqual(task.recurrence, "monthly;1;;1;09:00;d1")
        XCTAssertEqual(task.recurrenceRule?.displayText, "Monthly on the 1st")

        TaskActions.toggleCompletion(task, in: context, now: date(2026, 11, 1, 10))
        XCTAssertFalse(task.isCompleted)
        XCTAssertEqual(task.dueDate, date(2026, 12, 1, 9))
        XCTAssertEqual(task.recurrence, "monthly;1;;1;09:00;d1")
    }

    func testFirstMondayRollsOverMonthByMonth() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let parsed = QuickAddParser(now: date(2026, 10, 21, 14, 30), calendar: calendar).parse("Book club every first Monday")
        let task = try TaskActions.create(from: parsed, defaultProject: nil, defaultLabel: nil, in: context)
        XCTAssertEqual(task.dueDate, date(2026, 11, 2))
        TaskActions.toggleCompletion(task, in: context, now: date(2026, 11, 2, 12))
        XCTAssertEqual(task.dueDate, date(2026, 12, 7))
        TaskActions.toggleCompletion(task, in: context, now: date(2026, 12, 7, 12))
        XCTAssertEqual(task.dueDate, date(2027, 1, 4))
        XCTAssertEqual(task.recurrenceRule?.displayText, "First Monday of the month")
    }

    /// The Repeat card shows a rule it has no preset for as the current choice, and that row picks nothing:
    /// the quick-add card would otherwise write it back as plain "every month".
    func testTheRepeatCardKeepsARuleItCannotEdit() {
        let on28 = RecurrenceRule(frequency: .monthly, place: .day(28))
        XCTAssertNil(RepeatPresets.preset(for: on28))
        XCTAssertEqual(RepeatPresets.currentRow(for: on28), "Monthly on the 28th")
        XCTAssertEqual(RepeatPresets.preset(for: RecurrenceRule(frequency: .monthly, anchorDay: 21))?.title, "Every month")
        XCTAssertNil(RepeatPresets.currentRow(for: .monthly))
        XCTAssertNil(RepeatPresets.currentRow(for: nil))
        // Picking "Every month" on that task replaces the place and keeps the day the task is on.
        let picked = RepeatPresets.preset(for: .monthly)!.rule.keepingAnchor(of: on28, due: date(2026, 10, 28))
        XCTAssertNil(picked.place)
        XCTAssertEqual(picked.anchorDay, 28)
    }

    func testRepeatWordsForEachNewShape() {
        let cases: [(String, String)] = [
            ("every month on the 28th", "Monthly on the 28th"),
            ("every 3 months on the 10th", "Every 3 months on the 10th"),
            ("every last day of the month", "Last day of the month"),
            ("every first Monday", "First Monday of the month"),
            ("every last Friday", "Last Friday of the month"),
            ("every 2nd Tuesday", "Second Tuesday of the month"),
            ("every year on Mar 3", "Yearly on Mar 3"),
            ("quarterly", "Every 3 months"),
        ]
        let parser = QuickAddParser(now: date(2026, 10, 21, 14, 30), calendar: calendar)
        for (typed, words) in cases {
            XCTAssertEqual(parser.parse(typed).recurrence?.displayText, words, typed)
        }
    }
}
