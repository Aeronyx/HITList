import XCTest
@testable import HITListCore

/// Brief 97, item 2: Custom…, the card that can say every repeat quick add can type (macOS Calendar's, picture 5:
/// a frequency, "Every [1] week on:", seven day buttons). Opening it on any rule shows that rule exactly, and Done
/// with nothing changed gives the same rule back.
final class RepeatFormTests: XCTestCase {
    private let calendar = Fixed.calendar

    private func form(_ rule: RecurrenceRule?, _ y: Int, _ m: Int, _ d: Int) -> RepeatForm {
        RepeatForm(rule: rule, day: Fixed.date(y, m, d), calendar: calendar)
    }

    // MARK: Opening

    /// With no repeat it starts weekly, on the day's own weekday; every other frequency starts on the day's own place.
    func testOpensOnTheDaysOwnPlaces() {
        let f = form(nil, 2026, 11, 11) // Wednesday, the second Wednesday of November
        XCTAssertEqual(f.frequency, .weekly)
        XCTAssertEqual(f.interval, 1)
        XCTAssertEqual(f.weekdays, [4])
        XCTAssertEqual(f.monthly, .day)
        XCTAssertEqual(f.monthDay, 11)
        XCTAssertEqual(f.ordinal, 2)
        XCTAssertEqual(f.ordinalWeekday, 4)
        XCTAssertEqual(f.month, 11)
        XCTAssertEqual(f.yearDay, 11)
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .weekly, weekdays: [4]))
        XCTAssertEqual(form(nil, 2026, 11, 25).ordinal, 4, "the 25th is the fourth Wednesday")
        XCTAssertEqual(form(nil, 2026, 10, 29).ordinal, 5, "Oct 29 is the fifth Thursday")
        XCTAssertEqual(form(nil, 2026, 11, 1).ordinal, 1)
    }

    /// Each frequency builds its own rule from what the card shows.
    func testEachFrequencyBuildsItsRule() {
        var f = form(nil, 2026, 11, 11)
        f.frequency = .daily
        f.interval = 3
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .daily, interval: 3))
        f.frequency = .weekly
        f.interval = 2
        f.toggle(weekday: 3)
        f.toggle(weekday: 5)
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [3, 4, 5]))
        f.frequency = .monthly
        f.interval = 1
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .monthly, place: .day(11)))
        f.monthDay = 31
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .monthly, place: .day(31)))
        f.monthly = .lastDay
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .monthly, place: .lastDay))
        f.monthly = .weekday
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .monthly, place: .weekday(4, ordinal: 2)))
        f.ordinal = -1
        f.ordinalWeekday = 6
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .monthly, place: .weekday(6, ordinal: -1)))
        f.frequency = .yearly
        f.interval = 2
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .yearly, interval: 2, place: .date(month: 11, day: 11)))
        f.setMonth(2)
        f.yearDay = 29
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .yearly, interval: 2, place: .date(month: 2, day: 29)))
    }

    /// A weekly repeat keeps at least one day: the last one on cannot be turned off.
    func testWeeklyKeepsOneDayOn() {
        var f = form(nil, 2026, 11, 11)
        XCTAssertFalse(f.toggle(weekday: 4))
        XCTAssertEqual(f.weekdays, [4])
        XCTAssertTrue(f.toggle(weekday: 7))
        XCTAssertTrue(f.toggle(weekday: 4))
        XCTAssertEqual(f.weekdays, [7])
    }

    /// The day of a yearly repeat is one its month has (Feb 29 allowed: it is Feb 28 in other years).
    func testYearlyDayFitsTheMonth() {
        var f = form(nil, 2027, 1, 31)
        f.frequency = .yearly
        XCTAssertEqual(f.yearDay, 31)
        f.setMonth(2)
        XCTAssertEqual(f.yearDay, 29)
        XCTAssertEqual(RepeatForm.days(inMonth: 2), 29)
        f.setMonth(4)
        XCTAssertEqual(f.yearDay, 29, "only ever shortened")
        f.yearDay = 31
        XCTAssertEqual(f.rule.place, .date(month: 4, day: 30), "clamped")
        XCTAssertEqual(RepeatForm.days(inMonth: 4), 30)
        XCTAssertEqual(RepeatForm.days(inMonth: 12), 31)
    }

    func testIntervalStaysInRange() {
        var f = form(nil, 2026, 11, 11)
        f.interval = 0
        XCTAssertEqual(f.rule.interval, 1)
        f.interval = 5000
        XCTAssertEqual(f.rule.interval, RecurrenceRule.maxInterval)
        XCTAssertEqual(RepeatForm.interval(from: "12"), 12)
        XCTAssertEqual(RepeatForm.interval(from: " 3 "), 3)
        XCTAssertNil(RepeatForm.interval(from: "0"))
        XCTAssertNil(RepeatForm.interval(from: "1000"))
        XCTAssertNil(RepeatForm.interval(from: "two"))
    }

    /// "Every [1] week", "Every [3] months".
    func testUnitWords() {
        var f = form(nil, 2026, 11, 11)
        let units: [(RecurrenceRule.Frequency, String, String)] = [
            (.daily, "day", "days"), (.weekly, "week", "weeks"), (.monthly, "month", "months"), (.yearly, "year", "years")]
        for (frequency, one, many) in units {
            f.frequency = frequency
            f.interval = 1
            XCTAssertEqual(f.unit, one)
            f.interval = 4
            XCTAssertEqual(f.unit, many)
        }
    }

    // MARK: Round trips

    /// Every rule the card builds opens again showing what was picked, and builds the same rule.
    func testEveryBuiltRuleOpensAsItWasBuilt() {
        let day = Fixed.date(2026, 11, 11)
        var forms: [RepeatForm] = []
        for n in [1, 2, 5] {
            var f = RepeatForm(rule: nil, day: day, calendar: calendar)
            f.interval = n
            for frequency in RecurrenceRule.Frequency.allCases {
                f.frequency = frequency
                switch frequency {
                case .weekly:
                    for days: Set<Int> in [[4], [1], [2, 3, 4, 5, 6], [1, 7], [3, 5, 7]] {
                        f.weekdays = days
                        forms.append(f)
                    }
                case .monthly:
                    for d in [1, 11, 29, 31] { f.monthly = .day; f.monthDay = d; forms.append(f) }
                    f.monthly = .lastDay
                    forms.append(f)
                    for o in [1, 2, 5, -1] { f.monthly = .weekday; f.ordinal = o; f.ordinalWeekday = 6; forms.append(f) }
                case .yearly:
                    for (m, d) in [(1, 1), (2, 29), (11, 11), (12, 31)] { f.setMonth(m); f.yearDay = d; forms.append(f) }
                case .daily:
                    forms.append(f)
                }
            }
        }
        for f in forms {
            let reopened = RepeatForm(rule: f.rule, day: day, calendar: calendar)
            XCTAssertEqual(reopened.rule, f.rule, f.rule.encoded)
            XCTAssertEqual(reopened.shown, f.shown, f.rule.encoded)
        }
    }

    /// Every kind of repeat the parser's tests produce: Custom opened on it and closed with Done gives the rule back,
    /// its day and time included, and what the card shows lands on the same days.
    func testEveryParsedRepeatRoundTrips() {
        let phrases = [
            "every day", "daily", "every other day", "every 3 days", "every morning", "every day 9am", "every day 2:30",
            "every week", "weekly", "every other week", "every 2 weeks", "every week 7am",
            "every weekday", "every weekday 9:15am", "every weekend", "every monday", "every monday 7am",
            "every mon and thu", "every mon, wed and fri", "every tue, thu and sat",
            "every month", "monthly", "every other month", "every 2 months", "every 3 months", "quarterly",
            "every quarter", "every month 9am", "every month jan 31",
            "every year", "yearly", "annually", "every other year", "every 2 years", "yearly 2/29/28",
            "every month on the 28th", "every 28th", "every 1st", "every month on 28", "monthly on the 28th",
            "on the 28th of every month", "the 28th of each month", "every month on the 31st",
            "every 3 months on the 10th", "every other month on the 15th", "every 28th at 18:30",
            "every last day of the month", "every month on the last day", "end of every month",
            "the last day of every month", "every first day of the month",
            "every first Monday", "every first Monday of the month", "every 2nd Tuesday", "every last Friday",
            "every third Wednesday of the month", "every month on the first Monday", "on the first Monday of each month",
            "every other month on the last Friday", "every 1st Monday of every month",
            "every year on Mar 3", "every March 3", "yearly on March 3rd", "annually on 3 March", "every 2 years on 3 Mar",
            "every year on the 3rd of March", "every Feb 29", "every Oct 21 9am",
        ]
        let parser = QuickAddParser(now: Fixed.now, calendar: calendar)
        for phrase in phrases {
            let parsed = parser.parse("Task " + phrase)
            guard let rule = parsed.recurrence, let due = parsed.dueDate else { XCTFail("no repeat in “\(phrase)”"); continue }
            let f = RepeatForm(rule: rule, day: due, calendar: calendar)
            XCTAssertEqual(f.rule, rule, phrase)
            XCTAssertEqual(f.rule.encoded, rule.encoded, "\(phrase): its day and time too")
            XCTAssertEqual(f.frequency, rule.frequency, phrase)
            XCTAssertEqual(f.interval, rule.interval, phrase)
            XCTAssertEqual(RepeatChoice.days(of: f.shownRule, from: due, calendar: calendar),
                           RepeatChoice.days(of: rule, from: due, calendar: calendar), "\(phrase): what the card shows")
        }
    }

    /// Changing anything builds a new rule; changing it back gives the rule it opened on again.
    func testChangingItBackIsTheOpenedRule() {
        let opened = RecurrenceRule(frequency: .monthly, anchorDay: 11).withTime(hour: 9, minute: 0)
        var f = RepeatForm(rule: opened, day: Fixed.date(2026, 11, 11, 9), calendar: calendar)
        XCTAssertEqual(f.rule.encoded, opened.encoded)
        f.monthDay = 12
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .monthly, place: .day(12)))
        f.monthDay = 11
        XCTAssertEqual(f.rule.encoded, opened.encoded)
        f.frequency = .weekly
        XCTAssertEqual(f.rule, RecurrenceRule(frequency: .weekly, weekdays: [4]))
        f.frequency = .monthly
        XCTAssertEqual(f.rule.encoded, opened.encoded)
    }
}
