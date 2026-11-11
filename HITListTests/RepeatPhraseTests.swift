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
        XCTAssertEqual(task.recurrenceRule?.displayText, "Every month on the 1st")

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
        XCTAssertEqual(task.recurrenceRule?.displayText, "Every month on the first Monday")
    }

    /// The Repeat menu (brief 97) ticks the choice a rule is on the task's day; a rule that is none of them is its own
    /// ticked line, and picking it changes nothing (the quick-add card does not rewrite what was typed).
    func testTheRepeatMenuTicksTheRuleInForce() {
        let on28 = RecurrenceRule(frequency: .monthly, place: .day(28))
        XCTAssertEqual(RepeatChoice.matching(on28, on: date(2026, 10, 28), calendar: calendar)?.title, "Every month on the 28th")
        XCTAssertNil(RepeatChoice.matching(on28, on: date(2026, 10, 21), calendar: calendar))
        XCTAssertEqual(on28.rowText, "Every month on the 28th")
        // "Every month" from before 0.9.4, anchored to the 21st, is "Every month on the 21st" on the 21st.
        XCTAssertEqual(RepeatChoice.matching(RecurrenceRule(frequency: .monthly, anchorDay: 21), on: date(2026, 10, 21),
                                             calendar: calendar)?.kind, .monthly)
        XCTAssertNil(RepeatChoice.matching(nil, on: date(2026, 10, 21), calendar: calendar))
    }

    func testRepeatWordsForEachNewShape() {
        let cases: [(String, String)] = [
            ("every month on the 28th", "Every month on the 28th"),
            ("every 3 months on the 10th", "Every 3 months on the 10th"),
            ("every last day of the month", "Every month on the last day"),
            ("every first Monday", "Every month on the first Monday"),
            ("every last Friday", "Every month on the last Friday"),
            ("every 2nd Tuesday", "Every month on the second Tuesday"),
            ("every year on Mar 3", "Every year on Mar 3"),
            ("quarterly", "Every 3 months"),
        ]
        let parser = QuickAddParser(now: date(2026, 10, 21, 14, 30), calendar: calendar)
        for (typed, words) in cases {
            XCTAssertEqual(parser.parse(typed).recurrence?.displayText, words, typed)
        }
    }
}
