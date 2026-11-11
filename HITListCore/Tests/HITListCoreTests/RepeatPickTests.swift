import XCTest
@testable import HITListCore

/// Brief 97, item 4: choosing a repeat does what typing it does: the same due date, the same anchor and time, and a
/// task with no date gets the repeat's next occurrence. Each menu choice (and each shape Custom makes) is compared with
/// the parser's result for its words, typed alone, after a day, and after a day and a time.
final class RepeatPickTests: XCTestCase {
    private let calendar = Fixed.calendar

    /// Days to pick on: a Wednesday, a Saturday (no weekday), the 31st, Feb 29, a 30-day month's last day.
    private let days: [Date] = [
        Fixed.date(2026, 10, 21, 14, 30), Fixed.date(2026, 10, 24, 10), Fixed.date(2026, 10, 31, 9),
        Fixed.date(2028, 2, 29, 8), Fixed.date(2026, 11, 30, 23, 15),
    ]

    /// Custom's shapes beside the menu's.
    private let customRules: [RecurrenceRule] = [
        RecurrenceRule(frequency: .daily, interval: 3),
        RecurrenceRule(frequency: .weekly, weekdays: [3, 5, 7]),
        RecurrenceRule(frequency: .weekly, weekdays: [1, 7]),
        RecurrenceRule(frequency: .weekly, interval: 3),
        RecurrenceRule(frequency: .monthly, place: .day(28)),
        RecurrenceRule(frequency: .monthly, interval: 2, place: .lastDay),
        RecurrenceRule(frequency: .monthly, place: .weekday(6, ordinal: -1)),
        RecurrenceRule(frequency: .monthly, place: .weekday(2, ordinal: 1)),
        RecurrenceRule(frequency: .yearly, interval: 2, place: .date(month: 2, day: 29)),
        RecurrenceRule(frequency: .yearly, place: .date(month: 3, day: 3)),
    ]

    private func parsed(_ words: String, now: Date) -> QuickAddResult {
        QuickAddParser(now: now, calendar: calendar).parse("Task " + words)
    }

    private func iso(_ day: Date) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }

    private func assertSame(_ pick: RecurrenceRule.Pick, _ typed: QuickAddResult, _ what: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pick.due, typed.dueDate, "\(what): due", file: file, line: line)
        XCTAssertEqual(pick.hasTime, typed.hasDueTime, "\(what): time", file: file, line: line)
        XCTAssertEqual(pick.rule.encoded, typed.recurrence?.encoded, "\(what): rule", file: file, line: line)
    }

    /// No date: the menu is worded for today, and the task takes the repeat's next occurrence from today.
    func testWithNoDateAPickStartsAtItsNextOccurrence() {
        for now in days {
            let today = calendar.startOfDay(for: now)
            let rules = RepeatChoice.all(for: today, calendar: calendar).map(\.rule) + customRules
            for rule in rules {
                let words = rule.typedWords!
                let pick = rule.picked(due: nil, hasTime: false, previous: nil, now: now, calendar: calendar)
                assertSame(pick, parsed(words, now: now), "“\(words)” on \(iso(now))")
            }
        }
        // Every weekday picked on a Saturday starts on Monday.
        let saturday = Fixed.date(2026, 10, 24, 10)
        assertDate(RecurrenceRule.weekdays.picked(due: nil, hasTime: false, previous: nil, now: saturday, calendar: calendar).due,
                   2026, 10, 26)
        // Every month on the 28th, picked on the 21st, starts on the 28th.
        assertDate(RecurrenceRule(frequency: .monthly, place: .day(28)).picked(due: nil, hasTime: false, previous: nil,
                                                                               now: Fixed.now, calendar: calendar).due,
                   2026, 10, 28)
    }

    /// A day: the menu is worded for it, and the day stays as a typed day does ("2026-11-04 every day").
    func testWithADayThePickKeepsIt() {
        for now in days {
            let day = calendar.date(byAdding: .day, value: 9, to: calendar.startOfDay(for: now))!
            let rules = RepeatChoice.all(for: day, calendar: calendar).map(\.rule) + customRules
            for rule in rules {
                let words = rule.typedWords!
                let pick = rule.picked(due: day, hasTime: false, previous: nil, now: now, calendar: calendar)
                assertSame(pick, parsed(iso(day) + " " + words, now: now), "“\(iso(day)) \(words)”")
            }
        }
    }

    /// A day and a time: the time stays, and the rule keeps it ("2026-11-04 9:30am every month on the 4th").
    func testWithADayAndATimeThePickKeepsBoth() {
        for now in days {
            let start = calendar.date(byAdding: .day, value: 9, to: calendar.startOfDay(for: now))!
            let due = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: start)!
            for rule in RepeatChoice.all(for: due, calendar: calendar).map(\.rule) + customRules {
                let words = rule.typedWords!
                let pick = rule.picked(due: due, hasTime: true, previous: nil, now: now, calendar: calendar)
                assertSame(pick, parsed(iso(start) + " 9:30am " + words, now: now), "“\(iso(start)) 9:30am \(words)”")
                XCTAssertEqual(pick.rule.time, RecurrenceRule.TimeOfDay(hour: 9, minute: 30))
            }
        }
    }

    /// The menu's own words, typed: the same rule and day for every choice but the two weekly ones. Those are typed as
    /// "every week" (the card writes that: its day is the task's own), because "on Wednesday" typed on a Wednesday is
    /// next Wednesday to the parser, a week after the menu's pick. Reported to the supervisor rather than changed here.
    func testTheMenusWordsTyped() {
        for now in days {
            let today = calendar.startOfDay(for: now)
            for choice in RepeatChoice.all(for: today, calendar: calendar) where ![.weekly, .everyTwoWeeks].contains(choice.kind) {
                let typed = parsed(choice.title.lowercased(), now: now)
                let pick = choice.rule.picked(due: nil, hasTime: false, previous: nil, now: now, calendar: calendar)
                XCTAssertEqual(typed.recurrence?.encoded, pick.rule.encoded, "“\(choice.title)” on \(iso(now))")
                XCTAssertEqual(typed.dueDate, pick.due, "“\(choice.title)” on \(iso(now))")
            }
        }
    }

    /// A repeat picked again keeps the day its monthly rule returns to (`keepingAnchor`): "Every month" from the 31st,
    /// now due Feb 28, is still the 31st's.
    func testAPickKeepsThePreviousAnchor() {
        let from31 = RecurrenceRule(frequency: .monthly, anchorDay: 31)
        let pick = RecurrenceRule.monthly.picked(due: Fixed.date(2027, 2, 28), hasTime: false, previous: from31, now: Fixed.now,
                                                 calendar: calendar)
        XCTAssertEqual(pick.rule.anchorDay, 31)
        XCTAssertEqual(pick.due, Fixed.date(2027, 2, 28))
    }
}
