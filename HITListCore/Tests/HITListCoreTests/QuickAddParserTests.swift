import XCTest
@testable import HITListCore

final class QuickAddParserTests: XCTestCase {
    let parser = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar,
                                knownProjects: ["Finance", "Home Repairs", "Work"],
                                knownLabels: ["bills", "errand"])

    func testFullExample() {
        let r = parser.parse("Pay rent tomorrow 5pm p1 #Finance @bills every month")
        XCTAssertEqual(r.title, "Pay rent")
        assertDate(r.dueDate, 2026, 10, 22, 17, 0)
        XCTAssertTrue(r.hasDueTime)
        XCTAssertEqual(r.priority, .p1)
        XCTAssertEqual(r.projectName, "Finance")
        XCTAssertEqual(r.labelNames, ["bills"])
        XCTAssertEqual(r.recurrence, .monthly)
        XCTAssertEqual(r.tokens.map(\.kind), [.date, .time, .priority, .project, .label, .recurrence])
        XCTAssertEqual(r.tokens.map(\.text), ["tomorrow", "5pm", "p1", "#Finance", "@bills", "every month"])
    }

    func testPlainTitle() {
        let r = parser.parse("Call mom")
        XCTAssertEqual(r.title, "Call mom")
        XCTAssertNil(r.dueDate)
        XCTAssertEqual(r.priority, .p4)
        XCTAssertNil(r.projectName)
        XCTAssertTrue(r.labelNames.isEmpty)
        XCTAssertTrue(r.tokens.isEmpty)
    }

    func testDateInMiddleOfTitle() {
        let r = parser.parse("Submit report fri at 9 for the board")
        XCTAssertEqual(r.title, "Submit report for the board")
        assertDate(r.dueDate, 2026, 10, 23, 9, 0)
        XCTAssertTrue(r.hasDueTime)
    }

    func testProjectCanonicalCasingAndMultiWord() {
        XCTAssertEqual(parser.parse("Fix sink #finance").projectName, "Finance")
        let r = parser.parse("Fix sink #home repairs tomorrow")
        XCTAssertEqual(r.projectName, "Home Repairs")
        XCTAssertEqual(r.title, "Fix sink")
        assertDate(r.dueDate, 2026, 10, 22)
        let q = parser.parse("Fix sink #\"Home Repairs\"")
        XCTAssertEqual(q.projectName, "Home Repairs")
        XCTAssertEqual(q.title, "Fix sink")
        // Unknown project names pass through so the app can offer to create them.
        XCTAssertEqual(parser.parse("Plan trip #Travel").projectName, "Travel")
    }

    func testLabels() {
        let r = parser.parse("Buy stamps @errand @Errand @post")
        XCTAssertEqual(r.labelNames, ["errand", "post"])
        XCTAssertEqual(r.title, "Buy stamps")
    }

    func testPriorityForms() {
        XCTAssertEqual(parser.parse("x p2").priority, .p2)
        XCTAssertEqual(parser.parse("x !!3").priority, .p3)
        XCTAssertEqual(parser.parse("x P1").priority, .p1)
        XCTAssertEqual(parser.parse("x p5").priority, .p4)
        XCTAssertEqual(parser.parse("x p5").title, "x p5")
    }

    func testRecurrenceForms() {
        XCTAssertEqual(parser.parse("Gym every mon, wed and fri").recurrence, RecurrenceRule(frequency: .weekly, weekdays: [2, 4, 6]))
        XCTAssertEqual(parser.parse("Gym every mon, wed and fri").title, "Gym")
        XCTAssertEqual(parser.parse("Standup every weekday 9am").recurrence, .weekdays)
        XCTAssertEqual(parser.parse("Water plants every 3 days").recurrence, RecurrenceRule(frequency: .daily, interval: 3))
        XCTAssertEqual(parser.parse("Trash every other week").recurrence, RecurrenceRule(frequency: .weekly, interval: 2))
        XCTAssertEqual(parser.parse("Review daily").recurrence, .daily)
        XCTAssertEqual(parser.parse("Taxes yearly").recurrence, .yearly)
        // "every" with nothing recognizable stays in the title.
        XCTAssertNil(parser.parse("Thank every volunteer").recurrence)
        XCTAssertEqual(parser.parse("Thank every volunteer").title, "Thank every volunteer")
    }

    func testRecurrenceStartDate() {
        // Today is Wednesday. "every monday" with no explicit date starts next Monday.
        assertDate(parser.parse("Gym every monday").dueDate, 2026, 10, 26)
        // "every day" starts today.
        assertDate(parser.parse("Journal every day").dueDate, 2026, 10, 21)
        // Explicit date wins.
        assertDate(parser.parse("Journal every day starting jan 5").dueDate, 2027, 1, 5)
        // 9 am has passed at 14:30 (George, 2026-11-02): the next weekday, not today overdue.
        assertDate(parser.parse("Standup every weekday 9am").dueDate, 2026, 10, 22, 9, 0)
    }

    private func parser(at now: Date) -> QuickAddParser { QuickAddParser(now: now, calendar: Fixed.calendar) }

    /// George, 2026-11-02: a repeating task typed at a time already past today starts at its next occurrence.
    func testARepeatingTaskTypedAfterItsTimeStartsAtTheNextOccurrence() {
        // Wednesday 14:30.
        assertDate(parser.parse("Standup every weekday 9am").dueDate, 2026, 10, 22, 9, 0)
        assertDate(parser.parse("Pills every day 8pm").dueDate, 2026, 10, 21, 20, 0)
        assertDate(parser.parse("Pills every day 2pm").dueDate, 2026, 10, 22, 14, 0)
        assertDate(parser.parse("Water every 3 days 9am").dueDate, 2026, 10, 24, 9, 0)
        assertDate(parser.parse("Bins every week 7am").dueDate, 2026, 10, 28, 7, 0)
        let rent = parser.parse("Rent every month 9am")
        assertDate(rent.dueDate, 2026, 11, 21, 9, 0)
        XCTAssertEqual(rent.recurrence?.anchorDay, 21)
        XCTAssertTrue(parser.parse("Standup every weekday 9am").hasDueTime)

        // "every day 8pm" typed at 7 pm is today; at 9 pm it is tomorrow; at exactly 8 pm it is now.
        assertDate(parser(at: Fixed.date(2026, 10, 21, 19)).parse("Pills every day 8pm").dueDate, 2026, 10, 21, 20, 0)
        assertDate(parser(at: Fixed.date(2026, 10, 21, 21)).parse("Pills every day 8pm").dueDate, 2026, 10, 22, 20, 0)
        assertDate(parser(at: Fixed.date(2026, 10, 21, 20)).parse("Pills every day 8pm").dueDate, 2026, 10, 21, 20, 0)
        // Friday afternoon: the next weekday is Monday.
        assertDate(parser(at: Fixed.date(2026, 10, 23, 14)).parse("Standup every weekday 9am").dueDate, 2026, 10, 26, 9, 0)
        // Monday 10:00, "every monday 7am": next Monday.
        assertDate(parser(at: Fixed.date(2026, 10, 26, 10)).parse("Gym every monday 7am").dueDate, 2026, 11, 2, 7, 0)
        // A matching day still ahead is unaffected.
        assertDate(parser.parse("Gym every monday 7am").dueDate, 2026, 10, 26, 7, 0)
        // Jan 31 at 14:00, "every month 9am": Feb 28, still anchored to the 31st.
        let jan31 = parser(at: Fixed.date(2027, 1, 31, 14)).parse("Rent every month 9am")
        assertDate(jan31.dueDate, 2027, 2, 28, 9, 0)
        XCTAssertEqual(jan31.recurrence?.encoded, "monthly;1;;31")
    }

    func testAnExplicitPastDateOnARepeatingTaskIsKeptAsTyped() {
        assertDate(parser.parse("Standup every day yesterday 9am").dueDate, 2026, 10, 20, 9, 0)
        assertDate(parser.parse("Standup every weekday today 9am").dueDate, 2026, 10, 21, 9, 0)
        assertDate(parser.parse("Review every month oct 3 2026 9am").dueDate, 2026, 10, 3, 9, 0)
        assertDate(parser.parse("Review every month oct 3 2026").dueDate, 2026, 10, 3)
        // Not repeating: a time-only task still rolls to tomorrow, a dated one is kept.
        assertDate(parser.parse("Call bank 9am").dueDate, 2026, 10, 22, 9, 0)
        assertDate(parser.parse("Call bank today 9am").dueDate, 2026, 10, 21, 9, 0)
    }

    func testMonthlyAndYearlyRulesAreAnchoredToTheDueDay() {
        XCTAssertEqual(parser.parse("Rent every month").recurrence?.anchorDay, 21)
        XCTAssertEqual(parser.parse("Rent every month").recurrence?.encoded, "monthly;1;;21")
        XCTAssertEqual(parser.parse("Invoice every month jan 31").recurrence?.encoded, "monthly;1;;31")
        XCTAssertEqual(parser.parse("Birthday yearly 2/29/28").recurrence?.encoded, "yearly;1;;29")
        XCTAssertNil(parser.parse("Journal every day").recurrence?.anchorDay)
        XCTAssertNil(parser.parse("Gym every monday").recurrence?.anchorDay)
    }

    func testTimeOnlyRollsToTomorrowWhenPassed() {
        assertDate(parser.parse("Call bank 9am").dueDate, 2026, 10, 22, 9, 0)
        assertDate(parser.parse("Call bank 4pm").dueDate, 2026, 10, 21, 16, 0)
    }

    /// George, 2026-11-02: times are 24-hour unless the user says otherwise; a bare hour is a time only
    /// right after a date word or "at".
    func testTwentyFourHourTimes() {
        let tom13 = parser.parse("Haircut tom 13")
        XCTAssertEqual(tom13.title, "Haircut")
        assertDate(tom13.dueDate, 2026, 10, 22, 13, 0)
        XCTAssertTrue(tom13.hasDueTime)
        XCTAssertEqual(tom13.tokens.map(\.kind), [.date, .time])
        XCTAssertEqual(tom13.tokens.map(\.text), ["tom", "13"])

        let fri9 = parser.parse("Call friday 9 about the lease")
        XCTAssertEqual(fri9.title, "Call about the lease")
        assertDate(fri9.dueDate, 2026, 10, 23, 9, 0)

        // Time only, now 14:30.
        assertDate(parser.parse("Gym at 5").dueDate, 2026, 10, 22, 5, 0)
        assertDate(parser.parse("Dinner at 19").dueDate, 2026, 10, 21, 19, 0)
        assertDate(parser.parse("Run 5:30").dueDate, 2026, 10, 22, 5, 30)
        assertDate(parser.parse("Call 5pm").dueDate, 2026, 10, 21, 17, 0)
        assertDate(parser.parse("Call 5p").dueDate, 2026, 10, 21, 17, 0)
        assertDate(parser.parse("Call 5 pm").dueDate, 2026, 10, 21, 17, 0)
        assertDate(parser.parse("Lunch noon").dueDate, 2026, 10, 22, 12, 0)
        assertDate(parser.parse("Lunch tom noon").dueDate, 2026, 10, 22, 12, 0)
        assertDate(parser.parse("Backup midnight").dueDate, 2026, 10, 22, 0, 0)
        assertDate(parser.parse("Call tom 9 am").dueDate, 2026, 10, 22, 9, 0)
        XCTAssertEqual(parser.parse("Call tom 9 am").title, "Call")

        // Bare numbers anywhere else stay in the title.
        let apples = parser.parse("Buy 3 apples")
        XCTAssertEqual(apples.title, "Buy 3 apples")
        XCTAssertNil(apples.dueDate)
        let applesTom = parser.parse("Buy 3 apples tomorrow")
        XCTAssertEqual(applesTom.title, "Buy 3 apples")
        assertDate(applesTom.dueDate, 2026, 10, 22)
        XCTAssertFalse(applesTom.hasDueTime)
        XCTAssertEqual(parser.parse("Run tom 30 laps").title, "Run 30 laps", "30 is not an hour")
        XCTAssertFalse(parser.parse("Run tom 30 laps").hasDueTime)
        // A repeat is not a date word: "every day 5" leaves the 5.
        XCTAssertEqual(parser.parse("Stretch every day 5").title, "Stretch 5")
        // A time already typed wins; a second bare hour stays in the title.
        let twice = parser.parse("Call 5pm tom 9")
        assertDate(twice.dueDate, 2026, 10, 22, 17, 0)
        XCTAssertEqual(twice.title, "Call 9")
    }

    func testNumbersInTitleAreNotDates() {
        let r = parser.parse("Read 5 pages of chapter 12")
        XCTAssertEqual(r.title, "Read 5 pages of chapter 12")
        XCTAssertNil(r.dueDate)
    }

    func testQuotedTitleTextIsPreserved() {
        let r = parser.parse("Email \"tomorrow\" agenda today")
        XCTAssertEqual(r.title, "Email tomorrow agenda")
        assertDate(r.dueDate, 2026, 10, 21)
    }

    func testTokenRangesCoverOriginalText() {
        let input = "Pay rent tomorrow 5pm p1 #Finance"
        let r = parser.parse(input)
        for token in r.tokens {
            XCTAssertEqual(String(input[token.range]), token.text)
        }
    }

    // MARK: Reminder offsets

    func testGeorgesHaircutExample() {
        let r = parser.parse("Haircut tom 11am p1 !15mb")
        XCTAssertEqual(r.title, "Haircut")
        assertDate(r.dueDate, 2026, 10, 22, 11, 0)
        XCTAssertTrue(r.hasDueTime)
        XCTAssertEqual(r.priority, .p1)
        XCTAssertEqual(r.reminderOffsetMinutes, 15)
        XCTAssertEqual(r.tokens.map(\.kind), [.date, .time, .priority, .reminder])
        XCTAssertEqual(r.tokens.last?.text, "!15mb")
        XCTAssertNil(r.deadline)
        XCTAssertNil(r.locationName)
    }

    func testReminderOffsetForms() {
        let cases: [(String, Int)] = [
            ("!15mb", 15), ("!15m", 15), ("!5M", 5), ("!1hb", 60), ("!1h", 60), ("!2hb", 120),
            ("!1db", 1440), ("!1d", 1440), ("!3d", 4320), ("!0", 0), ("!at", 0), ("!AT", 0), ("!90m,", 90),
        ]
        for (token, minutes) in cases {
            let r = parser.parse("Call 5pm \(token)")
            XCTAssertEqual(r.reminderOffsetMinutes, minutes, token)
            XCTAssertEqual(r.title, "Call", token)
            XCTAssertEqual(r.tokens.first { $0.kind == .reminder }?.text, token, token)
        }
    }

    func testNonReminderBangWordsStayInTheTitle() {
        for text in ["Wow!", "!", "!b", "!mb", "!15", "!15x", "!-5m", "!0m", "!1.5h", "!30d", "Yay !important"] {
            let r = parser.parse(text)
            XCTAssertNil(r.reminderOffsetMinutes, text)
            XCTAssertEqual(r.title, text, text)
        }
        // "!!2" is still a priority, not a reminder.
        XCTAssertEqual(parser.parse("x !!2").priority, .p2)
        XCTAssertNil(parser.parse("x !!2").reminderOffsetMinutes)
    }

    func testOnlyTheFirstReminderTokenCounts() {
        let r = parser.parse("Pills 9pm !10m !1h")
        XCTAssertEqual(r.reminderOffsetMinutes, 10)
        XCTAssertEqual(r.title, "Pills !1h")
    }

    func testReminderWithoutATimeStillParses() {
        let r = parser.parse("Pack tomorrow !1db")
        XCTAssertEqual(r.reminderOffsetMinutes, 1440)
        XCTAssertFalse(r.hasDueTime)
        XCTAssertEqual(r.title, "Pack")
    }

    func testReminderTokensRoundTrip() {
        for minutes in [0, 5, 15, 30, 45, 60, 90, 120, 1440, 2880, 4320] {
            let token = ReminderOffset.token(minutes: minutes)
            XCTAssertEqual(ReminderOffset.minutes(fromToken: token), minutes, token)
        }
        XCTAssertEqual(ReminderOffset.token(minutes: 15), "!15mb")
        XCTAssertEqual(ReminderOffset.token(minutes: 60), "!1hb")
        XCTAssertEqual(ReminderOffset.token(minutes: 1440), "!1db")
        XCTAssertEqual(ReminderOffset.token(minutes: 0), "!at")
    }

    // MARK: Huge numbers (beta review)

    /// The parser runs on every keystroke of the quick-add card. "!9999999999999999d" multiplied the
    /// digits by 1440 past Int.max, which traps: the app crashed while the user typed.
    func testAHugeReminderOffsetStaysInTheTitleInsteadOfCrashing() {
        for token in ["!9999999999999999d", "!999999999999999999h", "!9223372036854775807m"] {
            XCTAssertNil(ReminderOffset.minutes(fromToken: token), token)
            let r = parser.parse("Call 5pm \(token)")
            XCTAssertNil(r.reminderOffsetMinutes, token)
            XCTAssertEqual(r.title, "Call \(token)", token)
        }
    }

    /// "every 2000000000000000000 weeks" made a rule whose next date, worked out on completion, computed
    /// 7 × interval past Int.max and trapped. Absurd counts stay in the title, and a rule never holds one.
    func testHugeCountsStayInTheTitle() {
        let every = parser.parse("Trash every 2000000000000000000 weeks")
        XCTAssertNil(every.recurrence)
        XCTAssertEqual(every.title, "Trash every 2000000000000000000 weeks")
        let inDays = parser.parse("Renew in 99999999999 days")
        XCTAssertNil(inDays.dueDate)
        XCTAssertEqual(inDays.title, "Renew in 99999999999 days")
        XCTAssertEqual(parser.parse("Water every 3 days").recurrence, RecurrenceRule(frequency: .daily, interval: 3), "sane counts still parse")

        let rule = RecurrenceRule(frequency: .weekly, interval: 2_000_000_000_000_000_000)
        XCTAssertEqual(rule.interval, RecurrenceRule.maxInterval)
        XCTAssertGreaterThan(rule.nextOccurrence(after: Fixed.now, calendar: Fixed.calendar), Fixed.now)
        XCTAssertEqual(RecurrenceRule(encoded: "daily;99999999999999")?.interval, RecurrenceRule.maxInterval)
    }

    func testReminderOffsetWording() {
        XCTAssertEqual(ReminderOffset.label(minutes: 0), "At time")
        XCTAssertEqual(ReminderOffset.label(minutes: 15), "15 min before")
        XCTAssertEqual(ReminderOffset.label(minutes: 60), "1 hour before")
        XCTAssertEqual(ReminderOffset.label(minutes: 120), "2 hours before")
        XCTAssertEqual(ReminderOffset.label(minutes: 1440), "1 day before")
        XCTAssertEqual(ReminderOffset.duration(minutes: 90), "1 hr 30 min")
        XCTAssertEqual(ReminderOffset.duration(minutes: 1500), "1 day 1 hr")
        XCTAssertEqual(ReminderOffset.duration(minutes: 2880), "2 days")
    }
}
