import XCTest
@testable import HITListCore

/// Brief 48 (George, 2026-11-05: "'!15mb' naturally requires a time before it would get highlighted, but '!15m'
/// would not, as it just means 15 minutes from now"): `!15m`, `!2h`, `!1d`, `!90m`, `!1h30m` remind that long
/// from now, with or without a due date; `!15mb`, `!2hb`, `!1db` remind that long before the due time (and need
/// one); `!at` / `!0` remind at the due time.
final class ReminderGrammarTests: XCTestCase {
    private let parser = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar)

    private func minutes(_ n: Int, after date: Date = Fixed.now) -> Date { date.addingTimeInterval(TimeInterval(n * 60)) }

    // MARK: From now

    func testFifteenMinutesFromNowNeedsNoDueDate() {
        let r = parser.parse("Call mom !15m")
        XCTAssertEqual(r.title, "Call mom")
        XCTAssertEqual(r.reminderDate, minutes(15))
        XCTAssertEqual(r.reminderFromNow, ReminderSpan(minutes: 15))
        XCTAssertNil(r.reminderOffsetMinutes, "not before a due time")
        XCTAssertNil(r.dueDate, "a from-now reminder gives the task no date")
        XCTAssertFalse(r.hasDueTime)
        XCTAssertEqual(r.tokens.map(\.kind), [.reminder])
        XCTAssertEqual(r.tokens.map(\.text), ["!15m"])
    }

    func testFromNowForms() {
        let cases: [(String, ReminderSpan, Int)] = [
            ("!15m", ReminderSpan(minutes: 15), 15), ("!5M", ReminderSpan(minutes: 5), 5),
            ("!2h", ReminderSpan(minutes: 120), 120), ("!90m", ReminderSpan(minutes: 90), 90),
            ("!1h30m", ReminderSpan(minutes: 90), 90), ("!1d", ReminderSpan(days: 1), 1440),
            ("!3d", ReminderSpan(days: 3), 3 * 1440), ("!1d12h", ReminderSpan(days: 1, minutes: 720), 2160),
            ("!2d3h15m", ReminderSpan(days: 2, minutes: 195), 2 * 1440 + 195), ("!90m,", ReminderSpan(minutes: 90), 90),
        ]
        for (token, span, total) in cases {
            XCTAssertEqual(ReminderPhrase(token: token), .fromNow(span), token)
            XCTAssertEqual(span.totalMinutes, total, token)
            let r = parser.parse("Call \(token)")
            XCTAssertEqual(r.reminderFromNow, span, token)
            XCTAssertEqual(r.reminderDate, minutes(total), token)
            XCTAssertEqual(r.title, "Call", token)
            XCTAssertNil(r.reminderOffsetMinutes, token)
        }
    }

    /// "Call mom 5pm !15m" (typed at 2:30 pm) is due at 5 pm and reminds at 2:45 pm: the "b" is what makes
    /// it count back from the time.
    func testFromNowBesideADueTimeStillCountsFromNow() {
        let r = parser.parse("Call mom 5pm !15m")
        assertDate(r.dueDate, 2026, 10, 21, 17, 0)
        XCTAssertTrue(r.hasDueTime)
        XCTAssertEqual(r.reminderDate, minutes(15))
        XCTAssertNil(r.reminderOffsetMinutes)
        XCTAssertEqual(r.tokens.map(\.kind), [.time, .reminder])
        let tomorrow = parser.parse("Dentist tomorrow !1h")
        assertDate(tomorrow.dueDate, 2026, 10, 22)
        XCTAssertEqual(tomorrow.reminderDate, minutes(60), "from now, not from the due day")
    }

    // MARK: Before the due time

    func testBeforeForms() {
        let cases: [(String, Int)] = [
            ("!15mb", 15), ("!5MB", 5), ("!1hb", 60), ("!2hb", 120), ("!1db", 1440), ("!3db", 4320),
            ("!90mb", 90), ("!1h30mb", 90), ("!0", 0), ("!at", 0), ("!AT", 0),
        ]
        for (token, minutes) in cases {
            XCTAssertEqual(ReminderPhrase(token: token), .beforeDue(minutes: minutes), token)
            XCTAssertEqual(ReminderOffset.minutes(fromToken: token), minutes, token)
            let r = parser.parse("Call 5pm \(token)")
            XCTAssertEqual(r.reminderOffsetMinutes, minutes, token)
            XCTAssertNil(r.reminderDate, token)
            XCTAssertNil(r.reminderFromNow, token)
            XCTAssertEqual(r.title, "Call", token)
        }
    }

    func testAFromNowWordIsNotAnOffset() {
        for token in ["!15m", "!2h", "!1d", "!1h30m"] {
            XCTAssertNil(ReminderOffset.minutes(fromToken: token), token)
        }
    }

    func testBeforeTheDueTimeStillNeedsATime() {
        for text in ["Pack !1hb", "Pack tomorrow !1db", "Pack !at", "Pack !0", "Pack !1h30mb"] {
            let r = parser.parse(text)
            XCTAssertNil(r.reminderOffsetMinutes, text)
            XCTAssertNil(r.reminderDate, text)
            XCTAssertFalse(r.tokens.contains { $0.kind == .reminder }, text)
            XCTAssertTrue(r.title.hasPrefix("Pack !"), text)
        }
    }

    // MARK: Which one counts

    func testALaterFromNowOverridesAnEarlierOne() {
        let r = parser.parse("Call !15m !1h")
        XCTAssertEqual(r.reminderDate, minutes(60))
        XCTAssertEqual(r.title, "Call !15m")
        XCTAssertEqual(r.tokens.filter(\.isSuperseded).map(\.text), ["!15m"])
    }

    func testALaterBeforeOverridesAnEarlierOne() {
        let r = parser.parse("Call 5pm !15mb !1hb")
        XCTAssertEqual(r.reminderOffsetMinutes, 60)
        XCTAssertEqual(r.title, "Call !15mb")
    }

    func testOneFromNowAndOneBeforeLiveSideBySide() {
        for text in ["Call 5pm !15m !1hb", "Call 5pm !1hb !15m"] {
            let r = parser.parse(text)
            XCTAssertEqual(r.reminderDate, minutes(15), text)
            XCTAssertEqual(r.reminderOffsetMinutes, 60, text)
            XCTAssertEqual(r.title, "Call", text)
            XCTAssertFalse(r.tokens.contains(where: \.isSuperseded), text)
            XCTAssertEqual(r.tokens.filter { $0.kind == .reminder }.count, 2, text)
        }
        // Without a time the "before" one is title text and the "from now" one still counts.
        let r = parser.parse("Call !1hb !15m")
        XCTAssertEqual(r.title, "Call !1hb")
        XCTAssertEqual(r.reminderDate, minutes(15))
        XCTAssertNil(r.reminderOffsetMinutes)
    }

    func testSwitchingOffAFromNowLeavesItAsTitleText() {
        let key = QuickAddTokenKey(kind: .reminder, text: "!15m")
        let r = parser.parse("Call mom !15m", disabling: [key])
        XCTAssertEqual(r.title, "Call mom !15m")
        XCTAssertNil(r.reminderDate)
        XCTAssertTrue(r.tokens.isEmpty)
        // Switching off the later one brings the earlier one back.
        let back = parser.parse("Call !15m !1h", disabling: [QuickAddTokenKey(kind: .reminder, text: "!1h")])
        XCTAssertEqual(back.reminderDate, minutes(15))
        XCTAssertEqual(back.title, "Call !1h")
    }

    // MARK: Not reminders

    func testMalformedWordsStayInTheTitle() {
        for token in ["!", "!m", "!h", "!d", "!0m", "!0h", "!0d", "!00", "!15", "!15x", "!-5m", "!+5m", "!1.5h",
                      "!30m15h", "!1h1h", "!1h30", "!15bm", "!15mbb", "!b", "!29d", "!at5", "!att", "!m15",
                      "!9999999999999999d", "!999999999999999999h", "!9223372036854775807m", "!1d9999999999999999m"] {
            XCTAssertNil(ReminderPhrase(token: token), token)
            let r = parser.parse("Fix sink 5pm \(token)")
            XCTAssertNil(r.reminderDate, token)
            XCTAssertNil(r.reminderOffsetMinutes, token)
            XCTAssertEqual(r.title, "Fix sink \(token)", token)
            XCTAssertEqual(r.tokens.map(\.kind), [.time], token)
        }
        XCTAssertEqual(parser.parse("x !!2").priority, .p2, "\"!!2\" is a priority")
        XCTAssertNil(parser.parse("x !!2").reminderDate)
    }

    func testFourWeeksIsTheLongest() {
        XCTAssertEqual(ReminderPhrase(token: "!28d"), .fromNow(ReminderSpan(days: 28)))
        XCTAssertEqual(ReminderPhrase(token: "!672h"), .fromNow(ReminderSpan(minutes: 672 * 60)))
        XCTAssertNil(ReminderPhrase(token: "!28d1m"))
        XCTAssertNil(ReminderPhrase(token: "!673h"))
        XCTAssertNil(ReminderPhrase(token: "!28d1mb"))
    }

    // MARK: Midnight and daylight saving

    func testAcrossMidnight() {
        let late = Fixed.date(2026, 10, 21, 23, 50)
        let p = QuickAddParser(now: late, calendar: Fixed.calendar)
        assertDate(p.parse("Bins !15m").reminderDate, 2026, 10, 22, 0, 5)
        assertDate(p.parse("Bins !1h30m").reminderDate, 2026, 10, 22, 1, 20)
        assertDate(p.parse("Bins !1d").reminderDate, 2026, 10, 22, 23, 50)
        // Tomorrow 7am is the due time; the reminder is still 15 minutes from now.
        let r = p.parse("Bins tomorrow 7am !15m")
        assertDate(r.dueDate, 2026, 10, 22, 7, 0)
        assertDate(r.reminderDate, 2026, 10, 22, 0, 5)
    }

    /// Minutes and hours are real time (an hour from 1:30 am on the spring-forward night is 3:30 am, and on
    /// the fall-back night the second 1:30 am); a day is the same clock time on the next day, 23 or 25 hours on.
    func testAcrossDaylightSavingChanges() throws {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            ny.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }
        // Spring forward: 2026-03-08 at 2:00 am EST becomes 3:00 am EDT.
        let spring = QuickAddParser(now: at(2026, 3, 8, 1, 30), calendar: ny)
        let hour = try XCTUnwrap(spring.parse("Pills !1h").reminderDate)
        XCTAssertEqual(hour.timeIntervalSince(at(2026, 3, 8, 1, 30)), 3600)
        XCTAssertEqual(ny.dateComponents([.hour, .minute], from: hour), DateComponents(hour: 3, minute: 30))
        let springDay = QuickAddParser(now: at(2026, 3, 7, 10, 0), calendar: ny)
        let day = try XCTUnwrap(springDay.parse("Pills !1d").reminderDate)
        XCTAssertEqual(day, at(2026, 3, 8, 10, 0), "the same clock time tomorrow")
        XCTAssertEqual(day.timeIntervalSince(at(2026, 3, 7, 10, 0)), 23 * 3600)
        // Fall back: 2026-11-01 at 2:00 am EDT becomes 1:00 am EST.
        let fallStart = at(2026, 11, 1, 0, 45)
        let fall = QuickAddParser(now: fallStart, calendar: ny)
        let twoHours = try XCTUnwrap(fall.parse("Pills !2h").reminderDate)
        XCTAssertEqual(twoHours.timeIntervalSince(fallStart), 7200)
        XCTAssertEqual(ny.dateComponents([.hour, .minute], from: twoHours), DateComponents(hour: 1, minute: 45))
        let fallDay = QuickAddParser(now: at(2026, 10, 31, 18, 0), calendar: ny)
        let next = try XCTUnwrap(fallDay.parse("Pills !1d").reminderDate)
        XCTAssertEqual(next, at(2026, 11, 1, 18, 0))
        XCTAssertEqual(next.timeIntervalSince(at(2026, 10, 31, 18, 0)), 25 * 3600)
    }

    // MARK: While typing (live) and at Confirm (final)

    /// Brief 48 (George: "only checks/adds a highlight after the user presses space instead of while they're
    /// typing it"): in a live parse a "!" word is plain until whitespace follows it; the final parse, at
    /// Confirm, takes the end of the text as complete.
    func testABangWordLightsUpOnlyOnceASpaceFollowsIt() {
        let typing = parser.parse("Call mom !15m", mode: .live)
        XCTAssertTrue(typing.tokens.isEmpty)
        XCTAssertEqual(typing.title, "Call mom !15m")
        XCTAssertNil(typing.reminderDate)
        XCTAssertNil(typing.reminderFromNow)

        let spaced = parser.parse("Call mom !15m ", mode: .live)
        XCTAssertEqual(spaced.tokens.map(\.text), ["!15m"])
        XCTAssertEqual(spaced.title, "Call mom")
        XCTAssertEqual(spaced.reminderDate, minutes(15))

        let confirmed = parser.parse("Call mom !15m", mode: .final)
        XCTAssertEqual(confirmed.tokens.map(\.text), ["!15m"])
        XCTAssertEqual(confirmed.reminderDate, minutes(15))
        XCTAssertEqual(parser.parse("Call mom !15m"), confirmed, "final is the default")
    }

    func testEveryStageOfTypingAReminderStaysPlainUntilTheSpace() {
        for typed in ["Call 5pm !", "Call 5pm !1", "Call 5pm !15", "Call 5pm !15m", "Call 5pm !15mb"] {
            let r = parser.parse(typed, mode: .live)
            XCTAssertEqual(r.tokens.map(\.kind), [.time], typed)
            XCTAssertNil(r.reminderDate, typed)
            XCTAssertNil(r.reminderOffsetMinutes, typed)
            XCTAssertEqual(r.title, "Call " + typed.split(separator: " ").last!, typed)
        }
        let before = parser.parse("Call 5pm !15mb ", mode: .live)
        XCTAssertEqual(before.reminderOffsetMinutes, 15)
        XCTAssertNil(before.reminderDate, "with the b it counts back from 5 pm")
        XCTAssertEqual(before.tokens.map(\.kind), [.time, .reminder])
    }

    func testOnlyTheWordAtTheEndWaits() {
        // A "!" word with more text after it is complete, wherever the caret is.
        let middle = parser.parse("Call !15m about the car", mode: .live)
        XCTAssertEqual(middle.reminderDate, minutes(15))
        XCTAssertEqual(middle.title, "Call about the car")
        // Other words light up as they are typed, as before.
        XCTAssertEqual(parser.parse("Call tomorrow", mode: .live).tokens.map(\.text), ["tomorrow"])
        XCTAssertEqual(parser.parse("Call p1", mode: .live).priority, .p1)
        // A later reminder still being typed doesn't override the finished one yet.
        let two = parser.parse("Call !15m !1h", mode: .live)
        XCTAssertEqual(two.reminderDate, minutes(15))
        XCTAssertEqual(two.title, "Call !1h")
        XCTAssertFalse(two.tokens.contains(where: \.isSuperseded))
        // Tabs and line breaks finish a word too.
        XCTAssertEqual(parser.parse("Call !15m\t", mode: .live).reminderDate, minutes(15))
    }

    /// "!!1" is a "!" command as well: it waits for the space like the reminders.
    func testABangPriorityWaitsToo() {
        let typing = parser.parse("Call !!1", mode: .live)
        XCTAssertEqual(typing.priority, .p4)
        XCTAssertEqual(typing.title, "Call !!1")
        XCTAssertEqual(parser.parse("Call !!1 ", mode: .live).priority, .p1)
        XCTAssertEqual(parser.parse("Call !!1").priority, .p1)
    }

    func testTheLiveParseHonoursSwitchedOffPhrases() {
        let off: Set<QuickAddTokenKey> = [QuickAddTokenKey(kind: .reminder, text: "!15m")]
        let r = parser.parse("Call !15m !1h", disabling: off, mode: .live)
        XCTAssertNil(r.reminderDate, "the first is switched off and the second not finished")
        XCTAssertEqual(r.title, "Call !15m !1h")
        XCTAssertEqual(parser.parse("Call !15m !1h", disabling: off, mode: .final).reminderDate, minutes(60))
        let text = "Call !15m !1h"
        let phrase = QuickAddDisabledPhrase(key: off.first!, start: 5, length: 4)
        XCTAssertNil(parser.parse(text, switchedOff: [phrase], mode: .live).reminderDate)
        XCTAssertEqual(parser.parse(text, switchedOff: [phrase], mode: .final).reminderDate, minutes(60))
        XCTAssertEqual(parser.parse(text + " ", switchedOff: [phrase], mode: .live).reminderDate, minutes(60))
    }

    // MARK: Words and tokens

    func testSpanWordingAndTokens() {
        XCTAssertEqual(ReminderSpan(minutes: 15).text, "15 min")
        XCTAssertEqual(ReminderSpan(minutes: 60).text, "1 hour")
        XCTAssertEqual(ReminderSpan(minutes: 90).text, "1 hr 30 min")
        XCTAssertEqual(ReminderSpan(days: 1).text, "1 day")
        XCTAssertEqual(ReminderSpan(days: 2, minutes: 60).text, "2 days 1 hr")
        XCTAssertEqual(ReminderSpan(minutes: 15).token, "!15m")
        XCTAssertEqual(ReminderSpan(minutes: 60).token, "!1h")
        XCTAssertEqual(ReminderSpan(minutes: 90).token, "!90m")
        XCTAssertEqual(ReminderSpan(days: 1).token, "!1d")
        XCTAssertEqual(ReminderSpan(days: 1, minutes: 30).token, "!1d30m")
        for span in [ReminderSpan(minutes: 1), ReminderSpan(minutes: 15), ReminderSpan(minutes: 60), ReminderSpan(minutes: 90),
                     ReminderSpan(minutes: 600), ReminderSpan(days: 1), ReminderSpan(days: 2, minutes: 195), ReminderSpan(days: 28)] {
            XCTAssertEqual(ReminderPhrase(token: span.token), .fromNow(span), span.token)
        }
    }
}
