import XCTest
@testable import HITListCore

final class RecurrenceRuleTests: XCTestCase {
    let cal = Fixed.calendar

    func testEncodingRoundTrip() {
        let rules: [RecurrenceRule] = [.daily, .weekly, .monthly, .yearly, .weekdays,
                                       RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2, 4])]
        for rule in rules {
            XCTAssertEqual(RecurrenceRule(encoded: rule.encoded), rule)
        }
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, weekdays: [4, 2]).encoded, "weekly;1;2,4")
        XCTAssertNil(RecurrenceRule(encoded: "bogus"))
        XCTAssertNil(RecurrenceRule(encoded: "weekly"))
    }

    func testNextOccurrence() {
        let wed = Fixed.date(2026, 10, 21, 9)
        assertDate(RecurrenceRule.daily.nextOccurrence(after: wed, calendar: cal), 2026, 10, 22, 9)
        assertDate(RecurrenceRule(frequency: .daily, interval: 3).nextOccurrence(after: wed, calendar: cal), 2026, 10, 24, 9)
        assertDate(RecurrenceRule.weekly.nextOccurrence(after: wed, calendar: cal), 2026, 10, 28, 9)
        assertDate(RecurrenceRule.monthly.nextOccurrence(after: wed, calendar: cal), 2026, 11, 21, 9)
        assertDate(RecurrenceRule.yearly.nextOccurrence(after: wed, calendar: cal), 2027, 10, 21, 9)
        // Mon/Wed from a Wednesday → next Monday.
        assertDate(RecurrenceRule(frequency: .weekly, weekdays: [2, 4]).nextOccurrence(after: wed, calendar: cal), 2026, 10, 26, 9)
        // Weekdays from Friday → Monday.
        assertDate(RecurrenceRule.weekdays.nextOccurrence(after: Fixed.date(2026, 10, 23), calendar: cal), 2026, 10, 26)
        // Every 2 weeks on Monday, from Mon Oct 19 → Mon Nov 2.
        assertDate(RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2]).nextOccurrence(after: Fixed.date(2026, 10, 19), calendar: cal), 2026, 11, 2)
        // Month-end clamping.
        assertDate(RecurrenceRule.monthly.nextOccurrence(after: Fixed.date(2027, 1, 31), calendar: cal), 2027, 2, 28)
    }

    func testNextDueDateSkipsPast() {
        // Daily task last due a week ago, completed today → due tomorrow? No: next occurrence not in the past is today.
        let due = Fixed.date(2026, 10, 14)
        assertDate(RecurrenceRule.daily.nextDueDate(from: due, now: Fixed.now, calendar: cal), 2026, 10, 21)
        // Weekly task due yesterday (Tue) → next Tuesday.
        assertDate(RecurrenceRule.weekly.nextDueDate(from: Fixed.date(2026, 10, 20), now: Fixed.now, calendar: cal), 2026, 10, 27)
        // Task due in the future just moves one step.
        assertDate(RecurrenceRule.weekly.nextDueDate(from: Fixed.date(2026, 10, 30), now: Fixed.now, calendar: cal), 2026, 11, 6)
    }

    func testDisplayText() {
        XCTAssertEqual(RecurrenceRule.daily.displayText, "Every day")
        XCTAssertEqual(RecurrenceRule.weekdays.displayText, "Every weekday")
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, weekdays: [2, 4, 6]).displayText, "Every Mon, Wed, Fri")
        XCTAssertEqual(RecurrenceRule(frequency: .monthly, interval: 3).displayText, "Every 3 months")
    }
}
