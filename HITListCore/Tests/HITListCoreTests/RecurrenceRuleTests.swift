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

    // MARK: Anchor day (George, 2026-11-02): monthly and yearly repeats keep their original day

    func testMonthlyOnThe31stKeepsComingBackToThe31st() {
        let rule = RecurrenceRule(frequency: .monthly, anchorDay: 31)
        var due = Fixed.date(2027, 1, 31, 9)
        for (month, day) in [(2, 28), (3, 31), (4, 30), (5, 31), (6, 30), (7, 31)] {
            due = rule.nextOccurrence(after: due, calendar: cal)
            assertDate(due, 2027, month, day, 9)
        }
        // A leap year's February ends on the 29th.
        assertDate(rule.nextOccurrence(after: Fixed.date(2028, 1, 31), calendar: cal), 2028, 2, 29)
        assertDate(rule.nextOccurrence(after: Fixed.date(2028, 2, 29), calendar: cal), 2028, 3, 31)
    }

    func testEveryTwoMonthsOnThe31st() {
        let rule = RecurrenceRule(frequency: .monthly, interval: 2, anchorDay: 31)
        var due = Fixed.date(2026, 12, 31)
        for (year, month, day) in [(2027, 2, 28), (2027, 4, 30), (2027, 6, 30), (2027, 8, 31)] {
            due = rule.nextOccurrence(after: due, calendar: cal)
            assertDate(due, year, month, day)
        }
    }

    func testCompletingOnFebruary28StillLandsOnMarch31() {
        let rule = RecurrenceRule(frequency: .monthly, anchorDay: 31)
        let now = Fixed.date(2027, 2, 28, 15)
        assertDate(rule.nextDueDate(from: Fixed.date(2027, 2, 28), now: now, calendar: cal), 2027, 3, 31)
        // Overdue since Jan 31 and completed on Mar 5: Feb 28 is past, so Mar 31.
        assertDate(rule.nextDueDate(from: Fixed.date(2027, 1, 31), now: Fixed.date(2027, 3, 5), calendar: cal), 2027, 3, 31)
    }

    func testYearlyOnFebruary29() {
        let rule = RecurrenceRule(frequency: .yearly, anchorDay: 29)
        var due = Fixed.date(2028, 2, 29, 8)
        for (year, day) in [(2029, 28), (2030, 28), (2031, 28), (2032, 29), (2033, 28)] {
            due = rule.nextOccurrence(after: due, calendar: cal)
            assertDate(due, year, 2, day, 8)
        }
    }

    func testARuleWithoutAnAnchorBehavesAsBefore() {
        XCTAssertNil(RecurrenceRule.monthly.anchorDay)
        let feb = RecurrenceRule.monthly.nextOccurrence(after: Fixed.date(2027, 1, 31), calendar: cal)
        assertDate(feb, 2027, 2, 28)
        assertDate(RecurrenceRule.monthly.nextOccurrence(after: feb, calendar: cal), 2027, 3, 28)
        assertDate(RecurrenceRule.yearly.nextOccurrence(after: Fixed.date(2028, 2, 29), calendar: cal), 2029, 2, 28)
    }

    func testAnAnchorTheDueDateNoLongerMatchesFollowsTheDueDate() {
        // The user moved a "31st" task to the 15th: it repeats on the 15th.
        let rule = RecurrenceRule(frequency: .monthly, anchorDay: 31)
        assertDate(rule.nextOccurrence(after: Fixed.date(2027, 3, 15), calendar: cal), 2027, 4, 15)
        XCTAssertEqual(rule.anchored(to: Fixed.date(2027, 3, 15), calendar: cal).anchorDay, 15)
        // Feb 28 is the 31st clamped, so the anchor stays.
        XCTAssertEqual(rule.anchored(to: Fixed.date(2027, 2, 28), calendar: cal).anchorDay, 31)
    }

    func testAnchoredTakesTheDayOfTheDueDate() {
        XCTAssertEqual(RecurrenceRule.monthly.anchored(to: Fixed.date(2027, 1, 31), calendar: cal).anchorDay, 31)
        XCTAssertEqual(RecurrenceRule.yearly.anchored(to: Fixed.date(2028, 2, 29), calendar: cal).anchorDay, 29)
        XCTAssertEqual(RecurrenceRule(frequency: .monthly, interval: 3).anchored(to: Fixed.date(2026, 10, 21), calendar: cal).encoded,
                       "monthly;3;;21")
        // Days and weeks have no anchor.
        XCTAssertNil(RecurrenceRule.daily.anchored(to: Fixed.date(2027, 1, 31), calendar: cal).anchorDay)
        XCTAssertEqual(RecurrenceRule.weekdays.anchored(to: Fixed.date(2027, 1, 31), calendar: cal).encoded, "weekly;1;2,3,4,5,6")
    }

    func testAnchorEncoding() {
        let rule = RecurrenceRule(frequency: .monthly, anchorDay: 31)
        XCTAssertEqual(rule.encoded, "monthly;1;;31")
        XCTAssertEqual(RecurrenceRule(encoded: "monthly;1;;31")?.anchorDay, 31)
        XCTAssertEqual(RecurrenceRule(encoded: "yearly;2;;29")?.encoded, "yearly;2;;29")
        XCTAssertNil(RecurrenceRule(encoded: "monthly;1")?.anchorDay)
        XCTAssertEqual(RecurrenceRule.monthly.encoded, "monthly;1", "no anchor, no extra part")
        // Out of range, or on a frequency that has no use for it: dropped.
        XCTAssertNil(RecurrenceRule(encoded: "monthly;1;;45")?.anchorDay)
        XCTAssertNil(RecurrenceRule(encoded: "monthly;1;;x")?.anchorDay)
        XCTAssertNil(RecurrenceRule(frequency: .weekly, anchorDay: 5).anchorDay)
        XCTAssertEqual(RecurrenceRule(encoded: "weekly;1;2,4;9")?.encoded, "weekly;1;2,4")
    }

    /// Builds before this one (0.3.x) decode with exactly this logic: the anchor must read as plain "every month".
    func testOlderBuildsReadAnAnchoredRuleAsThePlainRule() {
        func decodeLikeBuild12(_ encoded: String) -> RecurrenceRule? {
            let parts = encoded.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, let freq = RecurrenceRule.Frequency(rawValue: parts[0]), let interval = Int(parts[1]) else { return nil }
            var weekdays: Set<Int>? = nil
            if parts.count >= 3, !parts[2].isEmpty {
                weekdays = Set(parts[2].split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
            }
            return RecurrenceRule(frequency: freq, interval: interval, weekdays: weekdays)
        }
        let old = decodeLikeBuild12(RecurrenceRule(frequency: .monthly, interval: 2, anchorDay: 31).encoded)
        XCTAssertEqual(old?.frequency, .monthly)
        XCTAssertEqual(old?.interval, 2)
        XCTAssertNil(old?.weekdays)
        XCTAssertEqual(old?.encoded, "monthly;2")
    }

    /// The anchor follows the due date; it does not make a different repeat. The Repeat menu ticks
    /// "Every month" for an anchored monthly rule.
    func testEqualityIgnoresTheAnchor() {
        let anchored = RecurrenceRule(frequency: .monthly, anchorDay: 31)
        XCTAssertEqual(anchored, .monthly)
        XCTAssertEqual(Set([anchored, .monthly]).count, 1)
        XCTAssertNotEqual(anchored, .yearly)
        XCTAssertEqual(anchored.displayText, "Every month")
    }

    func testDisplayText() {
        XCTAssertEqual(RecurrenceRule.daily.displayText, "Every day")
        XCTAssertEqual(RecurrenceRule.weekdays.displayText, "Every weekday")
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, weekdays: [2, 4, 6]).displayText, "Every Mon, Wed, Fri")
        XCTAssertEqual(RecurrenceRule(frequency: .monthly, interval: 3).displayText, "Every 3 months")
    }
}
