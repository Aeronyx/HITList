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

    /// The Repeat menu's rules carry no anchor (final review): picked again, they keep the task's day.
    func testAMenuRulePickedAgainKeepsTheDayTheTaskReturnsTo() {
        let thirtyFirst = RecurrenceRule(frequency: .monthly, anchorDay: 31)
        let feb28 = Fixed.date(2027, 2, 28, 9)
        XCTAssertEqual(RecurrenceRule.monthly.keepingAnchor(of: thirtyFirst, due: feb28, calendar: cal).anchorDay, 31)
        XCTAssertEqual(RecurrenceRule(frequency: .monthly, interval: 3).keepingAnchor(of: thirtyFirst, due: feb28, calendar: cal).encoded,
                       "monthly;3;;31")
        // Moved off the anchor: the due day. Another frequency: the due day. No previous rule: the due day.
        XCTAssertEqual(RecurrenceRule.monthly.keepingAnchor(of: thirtyFirst, due: Fixed.date(2027, 3, 15), calendar: cal).anchorDay, 15)
        XCTAssertEqual(RecurrenceRule.yearly.keepingAnchor(of: thirtyFirst, due: feb28, calendar: cal).anchorDay, 28)
        XCTAssertEqual(RecurrenceRule.monthly.keepingAnchor(of: nil, due: Fixed.date(2027, 1, 31), calendar: cal).anchorDay, 31)
        XCTAssertEqual(RecurrenceRule.monthly.keepingAnchor(of: .weekly, due: Fixed.date(2027, 1, 30), calendar: cal).anchorDay, 30)
        // Left as they are: days and weeks, an undated task, a rule that has its own anchor.
        XCTAssertEqual(RecurrenceRule.weekdays.keepingAnchor(of: thirtyFirst, due: feb28, calendar: cal).encoded, "weekly;1;2,3,4,5,6")
        XCTAssertNil(RecurrenceRule.monthly.keepingAnchor(of: thirtyFirst, due: nil, calendar: cal).anchorDay)
        XCTAssertEqual(RecurrenceRule(frequency: .monthly, anchorDay: 30).keepingAnchor(of: thirtyFirst, due: feb28, calendar: cal).anchorDay, 30)
        // And the 31st comes back after the short month.
        let kept = RecurrenceRule.monthly.keepingAnchor(of: thirtyFirst, due: feb28, calendar: cal)
        assertDate(kept.nextOccurrence(after: feb28, calendar: cal), 2027, 3, 31, 9)
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

    // MARK: Time of day (brief 31)

    func testTimeEncoding() {
        let daily = RecurrenceRule.daily.withTime(hour: 2, minute: 30)
        XCTAssertEqual(daily.time, RecurrenceRule.TimeOfDay(hour: 2, minute: 30))
        XCTAssertEqual(daily.encoded, "daily;1;;;02:30")
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, weekdays: [2, 4]).withTime(hour: 9, minute: 0).encoded, "weekly;1;2,4;;09:00")
        XCTAssertEqual(RecurrenceRule(frequency: .monthly, anchorDay: 31).withTime(hour: 17, minute: 5).encoded, "monthly;1;;31;17:05")
        for encoded in ["daily;1;;;02:30", "weekly;1;2,4;;09:00", "monthly;1;;31;17:05", "yearly;2;;29;23:59"] {
            XCTAssertEqual(RecurrenceRule(encoded: encoded)?.encoded, encoded)
        }
        XCTAssertEqual(RecurrenceRule(encoded: "monthly;1;;31;17:05")?.anchorDay, 31)
        XCTAssertEqual(RecurrenceRule(encoded: "monthly;1;;31;17:05")?.time, RecurrenceRule.TimeOfDay(hour: 17, minute: 5))
        // No time, no extra part; nonsense times are dropped.
        XCTAssertEqual(RecurrenceRule.daily.encoded, "daily;1")
        XCTAssertEqual(daily.withoutTime.encoded, "daily;1")
        for bad in ["daily;1;;;25:00", "daily;1;;;9:60", "daily;1;;;x", "daily;1;;;", "daily;1;;;-1:00", "daily;1;;;0930"] {
            XCTAssertNil(RecurrenceRule(encoded: bad)?.time, bad)
            XCTAssertEqual(RecurrenceRule(encoded: bad)?.encoded, "daily;1", bad)
        }
        XCTAssertNil(RecurrenceRule.daily.withTime(hour: 24, minute: 0).time)
    }

    func testTimedFollowsTheDueTime() {
        let due = Fixed.date(2026, 10, 21, 7, 45)
        XCTAssertEqual(RecurrenceRule.daily.timed(to: due, hasTime: true, calendar: Fixed.calendar).time,
                       RecurrenceRule.TimeOfDay(hour: 7, minute: 45))
        XCTAssertNil(RecurrenceRule.daily.withTime(hour: 7, minute: 0).timed(to: due, hasTime: false, calendar: Fixed.calendar).time,
                     "an all-day task's repeat has no time")
        XCTAssertNil(RecurrenceRule.daily.withTime(hour: 7, minute: 0).timed(to: nil, hasTime: true, calendar: Fixed.calendar).time)
    }

    /// Like the anchor, the time follows the due date: the Repeat menu still ticks "Every day".
    func testEqualityIgnoresTheTime() {
        XCTAssertEqual(RecurrenceRule.daily.withTime(hour: 9, minute: 0), .daily)
        XCTAssertEqual(Set([RecurrenceRule.daily.withTime(hour: 9, minute: 0), .daily]).count, 1)
    }

    func testOccurrencesAreRebuiltFromTheRulesTime() {
        let cal = Fixed.calendar
        // A due date that drifted off the rule's time comes back to it on the next step.
        let rule = RecurrenceRule.daily.withTime(hour: 9, minute: 0)
        assertDate(rule.nextOccurrence(after: Fixed.date(2026, 10, 21, 10, 0), calendar: cal), 2026, 10, 22, 9, 0)
        let weekly = RecurrenceRule(frequency: .weekly, weekdays: [2, 4]).withTime(hour: 18, minute: 30)
        assertDate(weekly.nextOccurrence(after: Fixed.date(2026, 10, 21, 18, 30), calendar: cal), 2026, 10, 26, 18, 30)
        let monthly = RecurrenceRule(frequency: .monthly, anchorDay: 31).withTime(hour: 8, minute: 15)
        assertDate(monthly.nextOccurrence(after: Fixed.date(2027, 1, 31, 8, 15), calendar: cal), 2027, 2, 28, 8, 15)
        assertDate(monthly.nextDueDate(from: Fixed.date(2026, 8, 31, 8, 15), now: Fixed.now, calendar: cal), 2026, 10, 31, 8, 15)
    }

    /// Builds 13 and before decode with exactly this logic: a timed rule must read as the plain rule (with
    /// its anchor), so a TestFlight build that hasn't updated still repeats it.
    func testBuild13ReadsATimedRuleAsTheRuleWithoutItsTime() {
        func decodeLikeBuild13(_ encoded: String) -> RecurrenceRule? {
            let parts = encoded.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, let freq = RecurrenceRule.Frequency(rawValue: parts[0]), let interval = Int(parts[1]) else { return nil }
            var weekdays: Set<Int>? = nil
            if parts.count >= 3, !parts[2].isEmpty {
                weekdays = Set(parts[2].split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
            }
            let anchorDay = parts.count >= 4 ? Int(parts[3]) : nil
            return RecurrenceRule(frequency: freq, interval: interval, weekdays: weekdays, anchorDay: anchorDay)
        }
        XCTAssertEqual(decodeLikeBuild13("daily;1;;;02:30")?.encoded, "daily;1")
        XCTAssertEqual(decodeLikeBuild13("weekly;2;2,4;;09:00")?.encoded, "weekly;2;2,4")
        XCTAssertEqual(decodeLikeBuild13("monthly;1;;31;17:05")?.encoded, "monthly;1;;31")
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
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, weekdays: [2, 4, 6]).displayText, "Every Mon, Wed and Fri")
        XCTAssertEqual(RecurrenceRule(frequency: .monthly, interval: 3).displayText, "Every 3 months")
    }
}
