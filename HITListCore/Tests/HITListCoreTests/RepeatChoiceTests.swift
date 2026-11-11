import XCTest
@testable import HITListCore

/// Brief 97, item 1 (George, 2026-11-11: "there should be a custom dropdown like when repeating tasks on a calendar"):
/// the Repeat menu's seven choices worded for the task's day, as Todoist words them, the choice the rule in force is,
/// the row's own words for any other rule, and the words quick add writes for a pick (they read back to the rule).
final class RepeatChoiceTests: XCTestCase {
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var c = Fixed.calendar
        c.firstWeekday = firstWeekday
        return c
    }

    private func choices(_ y: Int, _ m: Int, _ d: Int, firstWeekday: Int = 1) -> [RepeatChoice] {
        RepeatChoice.all(for: Fixed.date(y, m, d), calendar: calendar(firstWeekday: firstWeekday))
    }

    private func titles(_ y: Int, _ m: Int, _ d: Int, firstWeekday: Int = 1) -> [String] {
        choices(y, m, d, firstWeekday: firstWeekday).map(\.title)
    }

    // MARK: The words

    /// Wednesday, November 11, 2026: George's picture 4, in the brief's words.
    func testWordedForWednesdayThe11th() {
        XCTAssertEqual(titles(2026, 11, 11), [
            "Every day",
            "Every weekday (Mon – Fri)",
            "Every week on Wednesday",
            "Every 2 weeks on Wednesday",
            "Every month on the 11th",
            "Every 3 months on the 11th",
            "Every year on November 11",
        ])
    }

    /// The words after the repeat itself are the quieter part, as in picture 4.
    func testEachChoiceSplitsIntoTheRepeatAndItsPlace() {
        let parts = choices(2026, 11, 11).map { [$0.lead, $0.detail] }
        XCTAssertEqual(parts, [
            ["Every day", ""],
            ["Every weekday", "(Mon – Fri)"],
            ["Every week", "on Wednesday"],
            ["Every 2 weeks", "on Wednesday"],
            ["Every month", "on the 11th"],
            ["Every 3 months", "on the 11th"],
            ["Every year", "on November 11"],
        ])
    }

    /// Each choice is the rule typing its words makes (item 4 compares them with the parser).
    func testTheRulesForTheDay() {
        let rules = choices(2026, 11, 11).map(\.rule)
        XCTAssertEqual(rules, [
            .daily,
            .weekdays,
            .weekly,
            RecurrenceRule(frequency: .weekly, interval: 2),
            RecurrenceRule(frequency: .monthly, place: .day(11)),
            RecurrenceRule(frequency: .monthly, interval: 3, place: .day(11)),
            RecurrenceRule(frequency: .yearly, place: .date(month: 11, day: 11)),
        ])
        XCTAssertEqual(choices(2026, 11, 11).map(\.kind), RepeatChoice.Kind.allCases)
    }

    /// Every weekday, each in its own words, whichever day the week starts on in Settings.
    func testEveryWeekdayAndEachFirstWeekdaySetting() {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        for firstWeekday in 1...7 {
            for offset in 0..<7 {
                // Sunday, November 8, 2026 and the six days after it.
                let day = 8 + offset
                let all = titles(2026, 11, day, firstWeekday: firstWeekday)
                XCTAssertEqual(all[2], "Every week on \(names[offset])", "Nov \(day), week from \(firstWeekday)")
                XCTAssertEqual(all[3], "Every 2 weeks on \(names[offset])", "Nov \(day), week from \(firstWeekday)")
                XCTAssertEqual(all[1], "Every weekday (Mon – Fri)")
                XCTAssertEqual(all, titles(2026, 11, day), "the week's first day changes no word")
            }
        }
    }

    /// The last day of every length of month, and the days only some months have.
    func testEveryMonthLength() {
        let cases: [((Int, Int, Int), String, String)] = [
            ((2027, 1, 31), "on the 31st", "on January 31"),    // 31 days
            ((2026, 11, 30), "on the 30th", "on November 30"),  // 30 days
            ((2027, 2, 28), "on the 28th", "on February 28"),   // 28 days
            ((2028, 2, 29), "on the 29th", "on February 29"),   // 29 days
            ((2026, 12, 29), "on the 29th", "on December 29"),
            ((2026, 12, 30), "on the 30th", "on December 30"),
            ((2026, 12, 31), "on the 31st", "on December 31"),
            ((2027, 3, 1), "on the 1st", "on March 1"),
        ]
        for ((y, m, d), month, year) in cases {
            let all = choices(y, m, d)
            XCTAssertEqual(all[4].detail, month, "\(y)-\(m)-\(d)")
            XCTAssertEqual(all[5].detail, month, "\(y)-\(m)-\(d)")
            XCTAssertEqual(all[6].detail, year, "\(y)-\(m)-\(d)")
            XCTAssertEqual(all[4].rule.place, .day(d))
            XCTAssertEqual(all[6].rule.place, .date(month: m, day: d))
        }
    }

    /// "Every month on the 31st" is each shorter month's last day and the 31st again after it; "on the 29th" is
    /// Feb 28 in a common year.
    func testThe29thTo31stLandInShortMonths() {
        let cal = calendar()
        func steps(_ rule: RecurrenceRule, from start: Date, _ n: Int) -> [Date] {
            var out: [Date] = [], at = start
            for _ in 0..<n { at = rule.nextOccurrence(after: at, calendar: cal); out.append(at) }
            return out
        }
        let on31 = choices(2027, 1, 31)[4].rule
        XCTAssertEqual(steps(on31, from: Fixed.date(2027, 1, 31), 4),
                       [Fixed.date(2027, 2, 28), Fixed.date(2027, 3, 31), Fixed.date(2027, 4, 30), Fixed.date(2027, 5, 31)])
        let on30 = choices(2027, 1, 30)[4].rule
        XCTAssertEqual(steps(on30, from: Fixed.date(2027, 1, 30), 2), [Fixed.date(2027, 2, 28), Fixed.date(2027, 3, 30)])
        let on29 = choices(2027, 1, 29)[4].rule
        XCTAssertEqual(steps(on29, from: Fixed.date(2027, 1, 29), 2), [Fixed.date(2027, 2, 28), Fixed.date(2027, 3, 29)])
        let quarterly31 = choices(2026, 10, 31)[5].rule
        XCTAssertEqual(steps(quarterly31, from: Fixed.date(2026, 10, 31), 2), [Fixed.date(2027, 1, 31), Fixed.date(2027, 4, 30)])
    }

    /// Feb 29: every month on the 29th; every year on February 29, which is Feb 28 in the years between.
    func testFebruary29() {
        let cal = calendar()
        let all = choices(2028, 2, 29)
        XCTAssertEqual(all[4].title, "Every month on the 29th")
        XCTAssertEqual(all[6].title, "Every year on February 29")
        let yearly = all[6].rule
        let next = yearly.nextOccurrence(after: Fixed.date(2028, 2, 29), calendar: cal)
        XCTAssertEqual(next, Fixed.date(2029, 2, 28))
        XCTAssertEqual(yearly.nextOccurrence(after: Fixed.date(2031, 2, 28), calendar: cal), Fixed.date(2032, 2, 29))
        XCTAssertEqual(all[4].rule.nextOccurrence(after: Fixed.date(2028, 2, 29), calendar: cal), Fixed.date(2028, 3, 29))
    }

    func testOrdinals() {
        let cases: [(Int, String)] = [(1, "1st"), (2, "2nd"), (3, "3rd"), (4, "4th"), (10, "10th"), (11, "11th"),
                                      (12, "12th"), (13, "13th"), (21, "21st"), (22, "22nd"), (23, "23rd"),
                                      (24, "24th"), (30, "30th"), (31, "31st")]
        for (day, words) in cases {
            XCTAssertEqual(choices(2027, 1, day)[4].detail, "on the \(words)")
        }
    }

    // MARK: The rule in force

    func testEachChoiceIsTickedForItsOwnRule() {
        let day = Fixed.date(2026, 11, 11)
        for choice in RepeatChoice.all(for: day, calendar: calendar()) {
            XCTAssertEqual(RepeatChoice.matching(choice.rule, on: day, calendar: calendar())?.kind, choice.kind)
            // A timed rule is the same repeat.
            let timed = choice.rule.withTime(hour: 9, minute: 30)
            XCTAssertEqual(RepeatChoice.matching(timed, on: day, calendar: calendar())?.kind, choice.kind)
        }
        XCTAssertNil(RepeatChoice.matching(nil, on: day, calendar: calendar()))
    }

    /// A rule that repeats on exactly the same days from the task's day is that choice: the presets before 0.9.4
    /// ("Every month" kept the day it started on), and "every wednesday" typed on a Wednesday.
    func testOlderRulesThatLandOnTheSameDaysAreTicked() {
        let cal = calendar()
        let wed11 = Fixed.date(2026, 11, 11)
        let cases: [(RecurrenceRule, RepeatChoice.Kind)] = [
            (RecurrenceRule(frequency: .monthly, anchorDay: 11), .monthly),
            (RecurrenceRule(frequency: .monthly), .monthly),
            (RecurrenceRule(frequency: .monthly, interval: 3, anchorDay: 11), .everyThreeMonths),
            (RecurrenceRule(frequency: .yearly, anchorDay: 11), .yearly),
            (RecurrenceRule(frequency: .weekly, weekdays: [4]), .weekly),
            (RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [4]), .everyTwoWeeks),
        ]
        for (rule, kind) in cases {
            XCTAssertEqual(RepeatChoice.matching(rule, on: wed11, calendar: cal)?.kind, kind, rule.encoded)
        }
    }

    /// Anything else is its own line at the top of the menu, in the row's words.
    func testOtherRulesAreNoneOfTheSeven() {
        let cal = calendar()
        let wed11 = Fixed.date(2026, 11, 11)
        let others: [RecurrenceRule] = [
            RecurrenceRule(frequency: .weekly, weekdays: [3, 5, 7]),
            RecurrenceRule(frequency: .monthly, place: .day(28)),
            RecurrenceRule(frequency: .monthly, place: .lastDay),
            RecurrenceRule(frequency: .monthly, place: .weekday(4, ordinal: 2)),
            RecurrenceRule(frequency: .daily, interval: 3),
            RecurrenceRule(frequency: .daily, interval: 7),
            RecurrenceRule(frequency: .weekly, interval: 3),
            RecurrenceRule(frequency: .yearly, place: .date(month: 3, day: 3)),
            RecurrenceRule(frequency: .weekly, weekdays: [5]),
        ]
        for rule in others {
            XCTAssertNil(RepeatChoice.matching(rule, on: wed11, calendar: cal), rule.encoded)
        }
        // "Every month" that started on the 31st, now due Feb 28, goes back to the 31st: not "on the 28th".
        let from31 = RecurrenceRule(frequency: .monthly, anchorDay: 31)
        XCTAssertNil(RepeatChoice.matching(from31, on: Fixed.date(2027, 2, 28), calendar: cal))
        XCTAssertEqual(RepeatChoice.matching(from31, on: Fixed.date(2027, 3, 31), calendar: cal)?.kind, .monthly)
    }

    // MARK: The row's words

    func testRowWords() {
        let cases: [(RecurrenceRule, String)] = [
            (.daily, "Every day"),
            (RecurrenceRule(frequency: .daily, interval: 3), "Every 3 days"),
            (.weekdays, "Every weekday"),
            (.weekly, "Every week"),
            (RecurrenceRule(frequency: .weekly, interval: 2), "Every 2 weeks"),
            (RecurrenceRule(frequency: .weekly, weekdays: [4]), "Every Wed"),
            (RecurrenceRule(frequency: .weekly, weekdays: [3, 5]), "Every Tue and Thu"),
            (RecurrenceRule(frequency: .weekly, weekdays: [3, 5, 7]), "Every Tue, Thu and Sat"),
            (RecurrenceRule(frequency: .weekly, weekdays: [1, 7]), "Every Sun and Sat"),
            (RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [3, 5]), "Every 2 weeks on Tue and Thu"),
            (RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2, 3, 4, 5, 6]), "Every 2 weeks on weekdays"),
            (.monthly, "Every month"),
            (RecurrenceRule(frequency: .monthly, interval: 3), "Every 3 months"),
            (RecurrenceRule(frequency: .monthly, place: .day(28)), "Every month on the 28th"),
            (RecurrenceRule(frequency: .monthly, interval: 3, place: .day(10)), "Every 3 months on the 10th"),
            (RecurrenceRule(frequency: .monthly, place: .lastDay), "Every month on the last day"),
            (RecurrenceRule(frequency: .monthly, interval: 2, place: .lastDay), "Every 2 months on the last day"),
            (RecurrenceRule(frequency: .monthly, place: .weekday(4, ordinal: 2)), "Every month on the second Wednesday"),
            (RecurrenceRule(frequency: .monthly, place: .weekday(6, ordinal: -1)), "Every month on the last Friday"),
            (RecurrenceRule(frequency: .monthly, interval: 2, place: .weekday(2, ordinal: 1)), "Every 2 months on the first Monday"),
            (.yearly, "Every year"),
            (RecurrenceRule(frequency: .yearly, interval: 2), "Every 2 years"),
            (RecurrenceRule(frequency: .yearly, place: .date(month: 3, day: 3)), "Every year on Mar 3"),
            (RecurrenceRule(frequency: .yearly, interval: 2, place: .date(month: 12, day: 31)), "Every 2 years on Dec 31"),
        ]
        for (rule, words) in cases { XCTAssertEqual(rule.displayText, words, rule.encoded) }
    }

    /// The short words a narrow button falls back to: how often, without the day or place.
    func testShortWords() {
        let cases: [(RecurrenceRule, String)] = [
            (.daily, "Every day"),
            (RecurrenceRule(frequency: .daily, interval: 3), "Every 3 days"),
            (.weekdays, "Every weekday"),
            (RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2, 3, 4, 5, 6]), "Every 2 weeks"),
            (RecurrenceRule(frequency: .weekly, weekdays: [3, 5, 7]), "Every week"),
            (RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [3, 5]), "Every 2 weeks"),
            (RecurrenceRule(frequency: .monthly, place: .weekday(4, ordinal: 2)), "Every month"),
            (RecurrenceRule(frequency: .monthly, interval: 3, place: .day(11)), "Every 3 months"),
            (RecurrenceRule(frequency: .yearly, place: .date(month: 11, day: 11)), "Every year"),
            (RecurrenceRule(frequency: .yearly, interval: 2), "Every 2 years"),
        ]
        for (rule, words) in cases { XCTAssertEqual(rule.shortText, words, rule.encoded) }
    }

    /// The days of a weekly rule are listed from the first day of the week in Settings.
    func testRowWordsFollowTheWeeksFirstDay() {
        let sunMon = RecurrenceRule(frequency: .weekly, weekdays: [1, 2])
        XCTAssertEqual(sunMon.displayText(weekStart: 1), "Every Sun and Mon")
        XCTAssertEqual(sunMon.displayText(weekStart: 2), "Every Mon and Sun")
        let spread = RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [1, 4, 7])
        XCTAssertEqual(spread.displayText(weekStart: 1), "Every 2 weeks on Sun, Wed and Sat")
        XCTAssertEqual(spread.displayText(weekStart: 2), "Every 2 weeks on Wed, Sat and Sun")
        XCTAssertEqual(spread.displayText(weekStart: 7), "Every 2 weeks on Sat, Sun and Wed")
        XCTAssertEqual(spread.displayText, spread.displayText(weekStart: 1))
    }

    // MARK: What quick add writes

    /// The words the quick-add card writes for a pick read back as the same rule, for every shape the Repeat menu
    /// and Custom can make that quick add can type; nil for the one it cannot (several days every 2 weeks or more).
    func testTypedWordsReadBackAsTheSameRule() {
        let parser = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar)
        var rules: [RecurrenceRule] = [.daily, .weekdays, .weekly, .monthly, .yearly]
        for n in [2, 3, 12] {
            rules.append(RecurrenceRule(frequency: .daily, interval: n))
            rules.append(RecurrenceRule(frequency: .weekly, interval: n))
            rules.append(RecurrenceRule(frequency: .monthly, interval: n))
            rules.append(RecurrenceRule(frequency: .yearly, interval: n))
        }
        for days: Set<Int> in [[1], [4], [7], [1, 7], [3, 5], [2, 4, 6], [3, 5, 7], [1, 2, 3, 4, 5, 6, 7]] {
            rules.append(RecurrenceRule(frequency: .weekly, weekdays: days))
        }
        for n in [1, 2, 3] {
            for place: RecurrenceRule.Place in [.day(1), .day(11), .day(22), .day(29), .day(31), .lastDay,
                                                .weekday(2, ordinal: 1), .weekday(4, ordinal: 2), .weekday(1, ordinal: 5),
                                                .weekday(6, ordinal: -1)] {
                rules.append(RecurrenceRule(frequency: .monthly, interval: n, place: place))
            }
            for (m, d) in [(1, 1), (2, 29), (3, 3), (11, 11), (12, 31)] {
                rules.append(RecurrenceRule(frequency: .yearly, interval: n, place: .date(month: m, day: d)))
            }
        }
        for rule in rules {
            guard let words = rule.typedWords else { return XCTFail("no words for \(rule.encoded)") }
            let parsed = parser.parse("Water plants " + words)
            XCTAssertEqual(parsed.recurrence, rule, "\(rule.encoded) as “\(words)”")
            XCTAssertEqual(parsed.title, "Water plants", "\(rule.encoded) as “\(words)”")
        }
        XCTAssertEqual(RecurrenceRule(frequency: .monthly, place: .day(11)).typedWords, "every month on the 11th")
        XCTAssertEqual(RecurrenceRule(frequency: .yearly, place: .date(month: 11, day: 11)).typedWords, "every year on nov 11")
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, weekdays: [3, 5, 7]).typedWords, "every tue, thu and sat")
        XCTAssertNil(RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [3, 5]).typedWords)
        XCTAssertNil(RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [4]).typedWords)
    }
}
