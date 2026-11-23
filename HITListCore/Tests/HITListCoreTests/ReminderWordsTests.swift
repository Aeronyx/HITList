import XCTest
@testable import HITListCore

/// Brief 175 (George, 2026-11-23: "I typed `!0mb` and it didn't register that I wanted a reminder, nor did spelling out
/// anything about a reminder … it shouldn't take me typing out the whole "!0mb" phrase and hitting space"): the list on
/// "!", the words it writes and the parser reading them back, reminders said in words, and times as people say them.
/// Fixed clock: Wednesday 2026-10-21 14:30 UTC.
final class ReminderWordsTests: XCTestCase {
    private let parser = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar)

    private func minutes(_ n: Int) -> Date { Fixed.now.addingTimeInterval(TimeInterval(n * 60)) }
    private func rows(hasTime: Bool, dueDate: Date? = nil, now: Date = Fixed.now) -> [ReminderSuggestion] {
        ReminderSuggestions.rows(hasTime: hasTime, dueDate: dueDate, now: now, calendar: Fixed.calendar)
    }
    private func reminderTokens(_ r: QuickAddResult) -> [String] {
        r.tokens.filter { $0.kind == .reminder && !$0.isSuperseded }.map(\.text)
    }

    // MARK: The list's rows

    func testTheTimedAndUntimedLists() {
        let timed = rows(hasTime: true)
        XCTAssertEqual(timed.map(\.label), ["At time of task", "10 minutes before", "30 minutes before", "45 minutes before",
                                            "1 hour before", "2 hours before", "3 hours before", "1 day before",
                                            "In 5 minutes", "In 15 minutes", "In 30 minutes", "Later"])
        XCTAssertEqual(timed.map(\.detail), ["!0mb", "!10mb", "!30mb", "!45mb", "!1hb", "!2hb", "!3hb", "!1db",
                                             "!5m", "!15m", "!30m", "6:00 PM"])
        XCTAssertEqual(timed.map(\.phrase), ["!At time of task", "!10 minutes before", "!30 minutes before",
                                             "!45 minutes before", "!1 hour before", "!2 hours before", "!3 hours before",
                                             "!1 day before", "!In 5 minutes", "!In 15 minutes", "!In 30 minutes", "!6:00 PM"])
        let untimed = rows(hasTime: false)
        XCTAssertEqual(untimed.map(\.label), ["In 5 minutes", "In 15 minutes", "In 30 minutes", "In 1 hour", "Later"])
        XCTAssertEqual(untimed.map(\.detail), ["!5m", "!15m", "!30m", "!1h", "6:00 PM"])
        XCTAssertEqual(untimed.map(\.kind), [.fromNow, .fromNow, .fromNow, .fromNow, .later])
        XCTAssertEqual(Set(timed.map(\.id)).count, timed.count, "ids are unique")
        XCTAssertEqual(timed[1].spokenLabel, "10 minutes before, exclamation 10 m b")
        XCTAssertEqual(timed[0].spokenLabel, "At time of task, exclamation 0 m b")
        XCTAssertEqual(untimed.last?.spokenLabel, "Later, 6:00 PM")
    }

    /// Every row of both lists reads back as what the row says, typed as its words or as its code, with a time typed
    /// and without: one highlight, the words out of the title.
    func testEveryRowParsesBackToWhatItSays() {
        for hasTime in [true, false] {
            for row in rows(hasTime: hasTime) {
                XCTAssertEqual(ReminderPhrase(token: row.phrase), row.reminder, row.phrase)
                let base = hasTime ? "Call mom 5pm " : "Call mom "
                for typed in [row.phrase, row.code] {
                    let r = parser.parse(base + typed)
                    XCTAssertEqual(r.title, "Call mom", typed)
                    XCTAssertEqual(reminderTokens(r), [typed], typed)
                    switch row.reminder {
                    case .beforeDue(let m):
                        XCTAssertEqual(r.reminderOffsetMinutes, m, typed)
                        XCTAssertNil(r.reminderDate, typed)
                    case .fromNow(let span):
                        XCTAssertEqual(r.reminderFromNow, span, typed)
                        XCTAssertEqual(r.reminderDate, minutes(span.totalMinutes), typed)
                        XCTAssertNil(r.reminderOffsetMinutes, typed)
                    case .at:
                        assertDate(r.reminderDate, 2026, 10, 21, 18, 0)
                        XCTAssertNil(r.reminderFromNow, typed)
                    }
                    // Picked, it ends in a space: lit at once in the card's live parse.
                    XCTAssertEqual(reminderTokens(parser.parse(base + typed + " ", mode: .live)), [typed], typed)
                }
            }
        }
    }

    // MARK: Later

    func testLaterIsThreeHoursOnRoundedUpOrNineTomorrow() {
        func later(_ h: Int, _ m: Int) -> Date { ReminderSuggestions.later(now: Fixed.date(2026, 10, 21, h, m), calendar: Fixed.calendar) }
        assertDate(later(13, 0), 2026, 10, 21, 16, 0)
        assertDate(later(13, 10), 2026, 10, 21, 17, 0)
        assertDate(later(14, 30), 2026, 10, 21, 18, 0)
        // Around 7 PM: 10 PM itself is not after 10 PM; a minute past 7 is.
        assertDate(later(18, 59), 2026, 10, 21, 22, 0)
        assertDate(later(19, 0), 2026, 10, 21, 22, 0)
        assertDate(later(19, 1), 2026, 10, 22, 9, 0)
        // Around 10 PM and after midnight.
        assertDate(later(21, 59), 2026, 10, 22, 9, 0)
        assertDate(later(22, 0), 2026, 10, 22, 9, 0)
        assertDate(later(23, 30), 2026, 10, 22, 9, 0)
        // After midnight: before 7 AM is 9:00 AM that morning (the review of brief 175, finding 11: 00:30 was 4:00 AM).
        assertDate(later(0, 30), 2026, 10, 21, 9, 0)
        assertDate(later(3, 0), 2026, 10, 21, 9, 0)
        assertDate(later(3, 59), 2026, 10, 21, 7, 0)
        assertDate(later(4, 0), 2026, 10, 21, 7, 0)
        assertDate(later(6, 30), 2026, 10, 21, 10, 0)
        let early = rows(hasTime: false, now: Fixed.date(2026, 10, 21, 0, 30)).last!
        XCTAssertEqual(early.detail, "9:00 AM")
        XCTAssertEqual(early.phrase, "!9:00 AM")
        // Seconds past the hour don't push it an hour on.
        XCTAssertEqual(ReminderSuggestions.later(now: Fixed.date(2026, 10, 21, 13, 0).addingTimeInterval(30), calendar: Fixed.calendar),
                       Fixed.date(2026, 10, 21, 16, 0))
    }

    func testLatersRowSaysWhenAndWritesWordsThatMeanIt() {
        let seven = Fixed.date(2026, 10, 21, 19, 0)
        let atSeven = rows(hasTime: false, now: seven).last!
        XCTAssertEqual(atSeven.detail, "10:00 PM")
        XCTAssertEqual(atSeven.phrase, "!10:00 PM")
        assertDate(QuickAddParser(now: seven, calendar: Fixed.calendar).parse("Bins " + atSeven.phrase).reminderDate, 2026, 10, 21, 22, 0)

        let evening = Fixed.date(2026, 10, 21, 19, 30)
        let late = rows(hasTime: true, dueDate: Fixed.date(2026, 10, 21, 21, 0), now: evening).last!
        XCTAssertEqual(late.detail, "Tomorrow 9:00 AM")
        XCTAssertEqual(late.phrase, "!Tomorrow 9:00 AM")
        XCTAssertEqual(late.code, "!9am")
        let r = QuickAddParser(now: evening, calendar: Fixed.calendar).parse("Bins 9pm " + late.phrase)
        assertDate(r.reminderDate, 2026, 10, 22, 9, 0)
        XCTAssertEqual(r.title, "Bins")

        // A task due on another day: a clock time alone would go off on that day, so Later says "Today".
        let friday = Fixed.date(2026, 10, 23, 9, 0)
        let other = rows(hasTime: true, dueDate: friday).last!
        XCTAssertEqual(other.detail, "6:00 PM")
        XCTAssertEqual(other.phrase, "!Today 6:00 PM")
        assertDate(parser.parse("Call mom friday 9am " + other.phrase).reminderDate, 2026, 10, 21, 18, 0)
        assertDate(parser.parse("Call mom friday 9am !6pm").reminderDate, 2026, 10, 23, 18, 0)
    }

    // MARK: Narrowing

    func testTypingNarrowsTheList() {
        let timed = rows(hasTime: true), untimed = rows(hasTime: false)
        func labels(_ rows: [ReminderSuggestion], _ q: String) -> [String] { ReminderSuggestions.narrowed(rows, by: q).map(\.label) }
        XCTAssertEqual(labels(timed, "1"), ["10 minutes before", "1 hour before", "1 day before", "In 15 minutes"])
        XCTAssertEqual(labels(untimed, "1"), ["In 15 minutes", "In 1 hour"])
        XCTAssertEqual(labels(timed, "h"), ["1 hour before", "2 hours before", "3 hours before"])
        XCTAssertEqual(labels(untimed, "h"), ["In 1 hour"])
        XCTAssertEqual(labels(timed, "in"), ["In 5 minutes", "In 15 minutes", "In 30 minutes"])
        XCTAssertEqual(labels(timed, "In"), ["In 5 minutes", "In 15 minutes", "In 30 minutes"])
        XCTAssertEqual(labels(timed, "at"), ["At time of task"])
        XCTAssertEqual(labels(timed, "10mb"), ["10 minutes before"])
        XCTAssertEqual(labels(timed, "30"), ["30 minutes before", "In 30 minutes"])
        XCTAssertEqual(labels(timed, "l"), ["Later"])
        XCTAssertEqual(labels(timed, "6"), ["Later"], "Later's code is !6pm at 14:30")
        XCTAssertEqual(labels(timed, ""), timed.map(\.label))
        XCTAssertEqual(labels(timed, "x"), [])
        XCTAssertEqual(labels(timed, "15mb"), [])
    }

    /// A word that is already a whole reminder ("!30m", "!1h", "!at", "!6pm") leaves only the rows that set that same
    /// reminder, so Return (the first row) writes what was typed, never a longer code of the other kind ("!30m" is In
    /// 30 minutes, never 30 minutes before). None: the list closes and Return adds the task as typed (the review of
    /// brief 175, finding 1).
    func testACompleteCodeTypedLeavesOnlyItsOwnReminder() {
        let timed = rows(hasTime: true), untimed = rows(hasTime: false)
        func narrowed(_ rows: [ReminderSuggestion], _ q: String) -> [ReminderSuggestion] { ReminderSuggestions.narrowed(rows, by: q) }
        XCTAssertEqual(narrowed(timed, "30m").map(\.label), ["In 30 minutes"])
        XCTAssertEqual(narrowed(timed, "30M").map(\.label), ["In 30 minutes"])
        for q in ["10m", "45m", "1h", "2h", "3h", "1d"] {
            XCTAssertEqual(narrowed(timed, q).map(\.label), [], "!\(q) is that long from now: no row before the time")
        }
        XCTAssertEqual(narrowed(untimed, "1h").map(\.label), ["In 1 hour"])
        XCTAssertEqual(narrowed(timed, "30mb").map(\.label), ["30 minutes before"])
        XCTAssertEqual(narrowed(timed, "1hb").map(\.label), ["1 hour before"])
        XCTAssertEqual(narrowed(timed, "at").map(\.label), ["At time of task"])
        XCTAssertEqual(narrowed(timed, "0").map(\.label), ["At time of task"])
        XCTAssertEqual(narrowed(timed, "6pm").map(\.label), ["Later"], "Later is 6:00 PM at 14:30")
        XCTAssertEqual(narrowed(timed, "4pm").map(\.label), [])
        // Later on another day than the one "!6pm" means (a task due Friday: "!6pm" is Friday 6 PM, Later today's).
        let friday = rows(hasTime: true, dueDate: Fixed.date(2026, 10, 23, 9, 0))
        XCTAssertEqual(narrowed(friday, "6pm").map(\.label), [])
        // Whatever row a whole code leaves first is the reminder typed.
        for list in [timed, untimed, friday] {
            for q in ["5m", "15m", "30m", "1h", "10m", "0mb", "10mb", "30mb", "1db", "at", "0", "6pm", "6p", "1d"] {
                guard let first = narrowed(list, q).first else { continue }
                XCTAssertEqual(first.reminder, ReminderPhrase(token: "!" + q), q)
            }
        }
    }

    // MARK: The "!" word at the caret, and a pick

    func testTheBangWordAtTheCaret() {
        func word(_ text: String, _ cursor: Int? = nil) -> ReminderSuggestions.BangWord? {
            ReminderSuggestions.bangWord(in: text, cursor: cursor ?? (text as NSString).length)
        }
        XCTAssertEqual(word("Call mom 9am !"), .init(range: NSRange(location: 13, length: 1), query: ""))
        XCTAssertEqual(word("Buy milk !1"), .init(range: NSRange(location: 9, length: 2), query: "1"))
        XCTAssertEqual(word("!in"), .init(range: NSRange(location: 0, length: 3), query: "in"))
        // The caret inside the word: the query runs to the caret, a pick replaces the whole word.
        XCTAssertEqual(word("Call !10mb about", 7), .init(range: NSRange(location: 5, length: 5), query: "1"))
        XCTAssertNil(word("Call !15m "), "a space ends it")
        XCTAssertNil(word("Call !!1"), "a priority")
        XCTAssertNil(word("Call x!"), "not at the word's start")
        XCTAssertNil(word("Call !15m", 5), "the caret before the !")
        XCTAssertNil(word("Call mom"))
        XCTAssertNil(word(""))
        XCTAssertNil(word("Call !", 99))
    }

    /// The caret inside a phrase already lit ("!1|0 minutes before"): a pick replaces the whole reminder the "!" word
    /// starts, never only the word, which left "!10 minutes before minutes before" (the review of brief 175, finding 6).
    func testAPickInsideALitPhraseReplacesTheWholePhrase() throws {
        let text = "Call 5pm !10 minutes before tomorrow"
        let word = try XCTUnwrap(ReminderSuggestions.bangWord(in: text, cursor: 11))
        XCTAssertEqual(word.query, "1")
        XCTAssertEqual(word.range, NSRange(location: 9, length: 18), "all of \"!10 minutes before\"")
        let picked = ReminderSuggestions.applying("!1 hour before", to: text, replacing: word.range)
        XCTAssertEqual(picked.text, "Call 5pm !1 hour before tomorrow")
        XCTAssertEqual(parser.parse(picked.text).reminderOffsetMinutes, 60)

        let lit = "Call 5pm !10 minutes before "
        let again = try XCTUnwrap(ReminderSuggestions.bangWord(in: lit, cursor: 11))
        XCTAssertEqual(ReminderSuggestions.applying("!10 minutes before", to: lit, replacing: again.range).text,
                       "Call 5pm !10 minutes before ")
        // "!At time of task", "!In 15 minutes", a clock with its day: each whole.
        XCTAssertEqual(ReminderSuggestions.bangWord(in: "Call 5pm !At time of task now", cursor: 11)?.range,
                       NSRange(location: 9, length: 16))
        XCTAssertEqual(ReminderSuggestions.bangWord(in: "Tea !In 15 minutes", cursor: 6)?.range, NSRange(location: 4, length: 14))
        XCTAssertEqual(ReminderSuggestions.bangWord(in: "Bins !Tomorrow 9:00 AM", cursor: 7)?.range, NSRange(location: 5, length: 17))
        // A word that starts no phrase is the word alone, as before.
        XCTAssertEqual(ReminderSuggestions.bangWord(in: "Buy !1 milk", cursor: 6)?.range, NSRange(location: 4, length: 2))
        XCTAssertEqual(ReminderSuggestions.bangWord(in: "Call !10mb about", cursor: 7)?.range, NSRange(location: 5, length: 5))
    }

    func testAPickReplacesTheTypedWordAndTheCaretSitsAfterASpace() {
        let picked = ReminderSuggestions.applying("!At time of task", to: "Call mom 9am !", replacing: NSRange(location: 13, length: 1))
        XCTAssertEqual(picked.text, "Call mom 9am !At time of task ")
        XCTAssertEqual(picked.cursor, (picked.text as NSString).length)
        let lit = parser.parse(picked.text, mode: .live)
        XCTAssertEqual(lit.reminderOffsetMinutes, 0, "lit at once: no space to type")
        XCTAssertEqual(reminderTokens(lit), ["!At time of task"])
        XCTAssertEqual(lit.title, "Call mom")

        let middle = ReminderSuggestions.applying("!In 15 minutes", to: "Buy !1 milk", replacing: NSRange(location: 4, length: 2))
        XCTAssertEqual(middle.text, "Buy !In 15 minutes milk")
        XCTAssertEqual(middle.cursor, 19, "after the space that was there")
        XCTAssertEqual(parser.parse(middle.text, mode: .live).reminderDate, minutes(15))
    }

    // MARK: The words (§2)

    func testTheWordsOfAReminder() {
        let cases: [(String, ReminderPhrase)] = [
            ("!At time of task", .beforeDue(minutes: 0)), ("!at time", .beforeDue(minutes: 0)),
            ("!at the time", .beforeDue(minutes: 0)), ("!At the time of the task", .beforeDue(minutes: 0)),
            ("!AT TIME OF TASK", .beforeDue(minutes: 0)),
            ("!10 minutes before", .beforeDue(minutes: 10)), ("!1 minute before", .beforeDue(minutes: 1)),
            ("!5 mins before", .beforeDue(minutes: 5)), ("!an hour before", .beforeDue(minutes: 60)),
            ("!two hours before", .beforeDue(minutes: 120)), ("!1 hr before", .beforeDue(minutes: 60)),
            ("!3 hrs before", .beforeDue(minutes: 180)), ("!1 day before", .beforeDue(minutes: 1440)),
            ("!2 days before", .beforeDue(minutes: 2880)), ("!a week before", .beforeDue(minutes: 10080)),
            ("!half an hour before", .beforeDue(minutes: 30)), ("!twelve minutes before", .beforeDue(minutes: 12)),
            ("!0 minutes before", .beforeDue(minutes: 0)), ("!10 Minutes Before,", .beforeDue(minutes: 10)),
            ("!In 5 minutes", .fromNow(ReminderSpan(minutes: 5))), ("!in an hour", .fromNow(ReminderSpan(minutes: 60))),
            ("!in half an hour", .fromNow(ReminderSpan(minutes: 30))), ("!in 2 days", .fromNow(ReminderSpan(days: 2))),
            ("!in a day", .fromNow(ReminderSpan(days: 1))), ("!In 90 minutes", .fromNow(ReminderSpan(minutes: 90))),
            ("!in 24 hours", .fromNow(ReminderSpan(minutes: 1440))), ("!in one week", .fromNow(ReminderSpan(days: 7))),
            ("!4pm", .at(ReminderClock(hour: 16, minute: 0))), ("!4:00 PM", .at(ReminderClock(hour: 16, minute: 0))),
            ("!4 p.m.", .at(ReminderClock(hour: 16, minute: 0))), ("!16:00", .at(ReminderClock(hour: 16, minute: 0))),
            ("!at 4pm", .at(ReminderClock(hour: 16, minute: 0))), ("!at 4", .at(ReminderClock(hour: 16, minute: 0))),
            ("!noon", .at(ReminderClock(hour: 12, minute: 0))), ("!9:30 a.m.", .at(ReminderClock(hour: 9, minute: 30))),
            ("!tomorrow 9am", .at(ReminderClock(hour: 9, minute: 0, day: 1))),
            ("!Tomorrow 9:00 AM", .at(ReminderClock(hour: 9, minute: 0, day: 1))),
            ("!today 6pm", .at(ReminderClock(hour: 18, minute: 0, day: 0))),
        ]
        for (text, phrase) in cases {
            XCTAssertEqual(ReminderPhrase(token: text), phrase, text)
            let words = String(text.dropFirst())
            XCTAssertEqual(ReminderPhrase(token: "remind me " + words), phrase, "remind me " + words)
            // "reminder" alone: only the forms measured from something; a clock time or a day is not its.
            if case .at = phrase {
                XCTAssertNil(ReminderPhrase(token: "Reminder " + words), "Reminder " + words)
            } else {
                XCTAssertEqual(ReminderPhrase(token: "Reminder " + words), phrase, "Reminder " + words)
            }
        }
        // The codes, as before.
        XCTAssertEqual(ReminderPhrase(token: "!0mb"), .beforeDue(minutes: 0))
        XCTAssertEqual(ReminderPhrase(token: "!15m"), .fromNow(ReminderSpan(minutes: 15)))
        XCTAssertEqual(ReminderPhrase(token: "!at"), .beforeDue(minutes: 0))
    }

    func testAPhraseIsOneTokenAndLeavesTheTitle() {
        let words = parser.parse("Call mom 5pm !10 minutes before")
        XCTAssertEqual(words.title, "Call mom")
        XCTAssertEqual(words.reminderOffsetMinutes, 10)
        XCTAssertEqual(words.tokens.map(\.text), ["5pm", "!10 minutes before"])

        let tea = parser.parse("Tea !In 10 minutes")
        XCTAssertEqual(tea.title, "Tea")
        XCTAssertEqual(tea.reminderFromNow, ReminderSpan(minutes: 10))
        XCTAssertEqual(tea.reminderDate, minutes(10))
        XCTAssertNil(tea.dueDate, "a reminder from now gives the task no date")

        // A clock time: today if still ahead, else tomorrow; on the due day when there is one and it is still to come.
        // ("Bins remind me at 4pm" is a due time since the review of brief 175: `testRemindMeWithAClockTimeAndNoDayIsTheDueTime`.)
        for text in ["Bins !4pm", "Bins !4:00 PM", "Bins !at 4pm", "Bins !4 p.m."] {
            let r = parser.parse(text)
            XCTAssertEqual(r.title, "Bins", text)
            assertDate(r.reminderDate, 2026, 10, 21, 16, 0)
            XCTAssertEqual(r.reminderClock, ReminderClock(hour: 16, minute: 0), text)
            XCTAssertNil(r.reminderFromNow, text)
            XCTAssertNil(r.dueDate, text)
        }
        assertDate(parser.parse("Bins !9am").reminderDate, 2026, 10, 22, 9, 0)
        assertDate(parser.parse("Bins friday !9am").reminderDate, 2026, 10, 23, 9, 0)
        assertDate(parser.parse("Bins yesterday !4pm").reminderDate, 2026, 10, 21, 16, 0)
        assertDate(parser.parse("Bins friday !tomorrow 9am").reminderDate, 2026, 10, 22, 9, 0)
        // The task's own moment: a later one, from now or a clock, wins over an earlier.
        let two = parser.parse("Bins !15m !4pm")
        assertDate(two.reminderDate, 2026, 10, 21, 16, 0)
        XCTAssertNil(two.reminderFromNow)
        XCTAssertEqual(two.title, "Bins !15m")
        // And one before the time stands beside it.
        let both = parser.parse("Bins 5pm !in 15 minutes !1 hour before")
        XCTAssertEqual(both.reminderDate, minutes(15))
        XCTAssertEqual(both.reminderOffsetMinutes, 60)
        XCTAssertEqual(both.title, "Bins")
    }

    func testAPhraseBeforeTheTimeStillNeedsATime() {
        for text in ["Pack !10 minutes before", "Pack !At time of task", "Pack tomorrow remind me 1 hour before", "Pack !at the time"] {
            let r = parser.parse(text)
            XCTAssertNil(r.reminderOffsetMinutes, text)
            XCTAssertEqual(reminderTokens(r), [], text)
            XCTAssertTrue(r.title.hasPrefix("Pack "), text)
            XCTAssertTrue(r.title.hasSuffix("before") || r.title.hasSuffix("task") || r.title.hasSuffix("time"), text)
        }
        var timed = parser
        timed.dueTimeIsSet = true
        XCTAssertEqual(timed.parse("Pack !1 hour before").reminderOffsetMinutes, 60, "the editor's task already has a time")
    }

    func testWordsThatAreNotReminders() {
        for text in ["Remind Sam about the party", "Reminder: pay rent", "remind me", "Call !10 minutes",
                     "Call !10 minutes after", "Call reminder", "Call !in", "Call !before", "remind me soon",
                     "Call !4", "Call !15", "Call ! 10 minutes before", "Call !In 5 days and more"] {
            let r = parser.parse(text)
            XCTAssertNil(r.reminderOffsetMinutes, text)
            if text != "Call !In 5 days and more" {
                XCTAssertNil(r.reminderDate, text)
                XCTAssertEqual(r.title, text, text)
                XCTAssertTrue(r.tokens.isEmpty, text)
            }
        }
        // "!In 5 days" is a phrase; the words after it are the title's.
        XCTAssertEqual(parser.parse("Call !In 5 days and more").title, "Call and more")
        XCTAssertNil(parser.parse("Call !in 29 days").reminderDate, "four weeks at most")
    }

    func testSwitchingOffAPhraseOfSeveralWordsKeepsAllItsWords() {
        let off = parser.parse("Call 5pm !10 minutes before", disabling: [QuickAddTokenKey(kind: .reminder, text: "!10 minutes before")])
        XCTAssertEqual(off.title, "Call !10 minutes before")
        XCTAssertNil(off.reminderOffsetMinutes)
        // Its inner words are not read as anything else: "at 4pm" stays the reminder's, not a due time.
        // ("remind me at 4pm" with no day of the task's own is its due time since the review of brief 175: a time token.)
        let spoken = parser.parse("Call remind me at 4pm", disabling: [QuickAddTokenKey(kind: .time, text: "remind me at 4pm")])
        XCTAssertEqual(spoken.title, "Call remind me at 4pm")
        XCTAssertNil(spoken.dueDate)
        XCTAssertNil(spoken.reminderDate)
        // By place too, as the card switches them off.
        let text = "Call 5pm !At time of task"
        let token = parser.parse(text).tokens.first { $0.kind == .reminder }!
        let place = QuickAddDisabledPhrase(token, in: text)!
        XCTAssertEqual(parser.parse(text, switchedOff: [place]).title, "Call !At time of task")
    }

    // MARK: Live

    func testAPhraseStillBeingTypedIsPlainText() {
        // (Since the review of brief 175, a shorter reading that ends before the word being typed stays lit: "!At time"
        // in "!At time of task", "!4:00" in "!4:00 PM"; `testAPhraseGrowingWordByWordNeverGoesDark`.)
        for typed in ["Call 5pm !10 minutes before", "Call remind me in an hour", "Call 5pm remind me 30 minutes before"] {
            let typing = parser.parse(typed, mode: .live)
            XCTAssertEqual(reminderTokens(typing), [], typed)
            XCTAssertNil(typing.reminderDate, typed)
            XCTAssertNil(typing.reminderOffsetMinutes, typed)
            XCTAssertEqual(reminderTokens(parser.parse(typed + " ", mode: .live)).count, 1, typed)
            XCTAssertEqual(reminderTokens(parser.parse(typed, mode: .final)).count, 1, typed)
        }
        // Being typed, "remind me in 30 minutes" doesn't make "in 30 minutes" the due time on the way.
        XCTAssertNil(parser.parse("Call remind me in 30 minutes", mode: .live).dueDate)
        // Half typed: "!At time" is whole and lights; "of" waits as a title word.
        let half = parser.parse("Call 5pm !At time of", mode: .live)
        XCTAssertEqual(half.reminderOffsetMinutes, 0)
        XCTAssertEqual(half.title, "Call of")
    }

    /// While a phrase grows word by word, the longest reading that ends before the word still being typed stays lit, so
    /// the highlight never goes dark on the way and comes back (the review of brief 175, finding 8: "!at time" went dark
    /// as "time" was typed, "remind me at 4" as "pm" was).
    func testAPhraseGrowingWordByWordNeverGoesDark() {
        func lit(_ text: String) -> [String] {
            // Reminder tokens, and "remind me at 4" that became the due time (a time token said in words).
            parser.parse(text, mode: .live).tokens.filter { !$0.isSuperseded && ($0.kind == .reminder || $0.isSaidInWords) }
                .map(\.text)
        }
        // ("Remind me in an hour to call mom": once lit, it stays lit through "to " and the title's first letter.)
        for full in ["Call 5pm !at time of task ", "Call mom remind me at 4 pm ", "Bins !at 4 pm ", "Bins !tomorrow 9:00 AM ",
                     "Call 5pm !At the time of the task ", "Tea !in half an hour ", "Pack 6pm remind me an hour before ",
                     "Remind me in an hour to call mom ", "Remind me at 5pm to call mom ", "Remind me to call mom "] {
            var seen = false
            for end in full.indices.dropFirst() + [full.endIndex] {
                let typed = String(full[..<end])
                let now = lit(typed)
                if seen { XCTAssertFalse(now.isEmpty, "went dark at \"\(typed)\"") }
                if !now.isEmpty { seen = true }
            }
            XCTAssertTrue(seen, full)
            XCTAssertEqual(lit(full).count, 1, full)
            XCTAssertTrue(full.contains(" " + lit(full)[0] + " ") || full.hasPrefix(lit(full)[0] + " "),
                          "the whole phrase: \(lit(full))")
        }
        // What is lit on the way is what the words so far say.
        XCTAssertEqual(lit("Call 5pm !at time"), ["!at"])
        XCTAssertEqual(lit("Call 5pm !at time of task"), ["!at time"])
        XCTAssertEqual(lit("Call mom remind me at 4 pm"), ["remind me at 4"])
        XCTAssertEqual(lit("Bins !at 4 pm"), ["!at 4"])
        XCTAssertEqual(lit("Bins !tomorrow 9:00 AM"), ["!tomorrow 9:00"])
        XCTAssertEqual(parser.parse("Bins !tomorrow 9:00 AM", mode: .live).title, "Bins AM")
    }

    // MARK: Said in words (§3)

    func testRemindMeToOpensTheTask() {
        let r = parser.parse("Remind me to call mom in 30 minutes.")
        XCTAssertEqual(r.title, "Call mom")
        XCTAssertEqual(r.dueDate, minutes(30))
        XCTAssertTrue(r.hasDueTime)
        XCTAssertEqual(r.reminderOffsetMinutes, 0, "at the time of the task")
        XCTAssertEqual(r.tokens.map(\.text), ["Remind me to", "in 30 minutes."])
        XCTAssertEqual(r.tokens.map(\.kind), [.reminder, .date])

        let plain = parser.parse("Remind me to buy milk")
        XCTAssertEqual(plain.title, "Buy milk")
        XCTAssertNil(plain.reminderOffsetMinutes, "no time: nothing to be at")
        XCTAssertNil(plain.dueDate)
        // Another reminder typed wins over the time of the task.
        XCTAssertEqual(parser.parse("Remind me to call mom tomorrow at 5 !1 hour before").reminderOffsetMinutes, 60)
        let fromNow = parser.parse("Remind me to call mom tomorrow at 5 !in 15 minutes")
        XCTAssertNil(fromNow.reminderOffsetMinutes)
        XCTAssertEqual(fromNow.reminderDate, minutes(15))
        // Switching it off puts the three words back, and the title as typed.
        let off = parser.parse("Remind me to call mom tomorrow at 5", disabling: [QuickAddTokenKey(kind: .reminder, text: "Remind me to")])
        XCTAssertEqual(off.title, "Remind me to call mom")
        XCTAssertNil(off.reminderOffsetMinutes)
        assertDate(off.dueDate, 2026, 10, 22, 17, 0)
        // Only at the start.
        let middle = parser.parse("Call mom, remind me to bring cake")
        XCTAssertEqual(middle.title, "Call mom, remind me to bring cake")
        XCTAssertTrue(middle.tokens.isEmpty)
        // A reminder phrase first, then "to": the "to" goes with it.
        let first = parser.parse("Remind me in 30 minutes to call mom")
        XCTAssertEqual(first.title, "Call mom")
        XCTAssertEqual(first.reminderDate, minutes(30))
        XCTAssertNil(first.dueDate)
        XCTAssertEqual(first.tokens.map(\.text), ["Remind me in 30 minutes to"])
        XCTAssertEqual(ReminderPhrase(token: "Remind me in 30 minutes to"), .fromNow(ReminderSpan(minutes: 30)))
        // Live: "Remind me to" lights once its space is typed: the title comes next (alone and read whole, it is the
        // title: finding 13 of the review).
        XCTAssertTrue(parser.parse("Remind me to", mode: .live).tokens.isEmpty)
        XCTAssertEqual(parser.parse("Remind me to ", mode: .live).tokens.map(\.text), ["Remind me to"])
        XCTAssertEqual(parser.parse("Remind me to c", mode: .live).tokens.map(\.text), ["Remind me to"])
        XCTAssertEqual(parser.parse("Remind me to ").title, "Remind me to")
    }

    /// "Remind me at 5pm to call mom": a clock time said with "remind me", with no day or time of the task's own, is when
    /// the task is due, reminded at the time (the review of brief 175, finding 4: it made an undated task). Its words are a
    /// time token (a date token with its day). "!4pm" stays a reminder moment of its own. Monday 2026-11-23, 14:10 Eastern.
    func testRemindMeWithAClockTimeAndNoDayIsTheDueTime() throws {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            ny.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
        }
        let p = QuickAddParser(now: at(11, 23, 14, 10), calendar: ny)

        let mom = p.parse("Remind me at 5pm to call mom")
        XCTAssertEqual(mom.title, "Call mom")
        XCTAssertEqual(mom.dueDate, at(11, 23, 17, 0))
        XCTAssertTrue(mom.hasDueTime)
        XCTAssertEqual(mom.reminderOffsetMinutes, 0, "at the time")
        XCTAssertNil(mom.reminderDate)
        XCTAssertNil(mom.reminderClock)
        XCTAssertEqual(mom.tokens.map(\.text), ["Remind me at 5pm to"])
        XCTAssertEqual(mom.tokens.map(\.kind), [.time])

        let bank = p.parse("Remind me tomorrow at 9 to call the bank")
        XCTAssertEqual(bank.title, "Call the bank")
        XCTAssertEqual(bank.dueDate, at(11, 24, 9, 0))
        XCTAssertEqual(bank.reminderOffsetMinutes, 0)
        XCTAssertEqual(bank.tokens.map(\.kind), [.date])

        let inside = p.parse("Call mom, remind me at 4")
        XCTAssertEqual(inside.title, "Call mom,")
        XCTAssertEqual(inside.dueDate, at(11, 23, 16, 0))
        XCTAssertEqual(inside.reminderOffsetMinutes, 0)

        let plants = p.parse("Remind me at 5 to water the plants every day")
        XCTAssertEqual(plants.title, "Water the plants")
        XCTAssertEqual(plants.recurrence?.frequency, .daily)
        XCTAssertEqual(plants.dueDate, at(11, 23, 17, 0), "a repeat's day: the afternoon")
        XCTAssertEqual(plants.reminderOffsetMinutes, 0)

        // Another reminder before the time typed with it is the one.
        let before = p.parse("Remind me at 5pm to call mom !10 minutes before")
        XCTAssertEqual(before.dueDate, at(11, 23, 17, 0))
        XCTAssertEqual(before.reminderOffsetMinutes, 10)

        // With a day or a time of the task's own, a reminder moment on it, as before.
        let friday = p.parse("Remind me at 4 to call mom friday")
        XCTAssertEqual(friday.title, "Call mom")
        XCTAssertEqual(friday.dueDate, at(11, 27, 0, 0))
        XCTAssertFalse(friday.hasDueTime)
        XCTAssertEqual(friday.reminderDate, at(11, 27, 16, 0))
        XCTAssertNil(friday.reminderOffsetMinutes)
        let timed = p.parse("Call mom 5pm remind me at 4pm")
        XCTAssertEqual(timed.dueDate, at(11, 23, 17, 0))
        XCTAssertEqual(timed.reminderDate, at(11, 23, 16, 0))
        var editor = p
        editor.dueDayIsSet = true
        XCTAssertNil(editor.parse("Call mom remind me at 4pm").dueDate, "the editor's task has its own day")
        XCTAssertEqual(editor.parse("Call mom remind me at 4pm").reminderClock, ReminderClock(hour: 16, minute: 0))
        // The code is a reminder moment of its own.
        let code = p.parse("Bins !4pm")
        XCTAssertNil(code.dueDate)
        XCTAssertEqual(code.reminderDate, at(11, 23, 16, 0))
    }

    /// Typical Siri and ring dictations (the second review of brief 175, finding 2): a short lead-in before "remind me"
    /// ("Can you", "Could you", "Would you", "Please", "Hey", "Hey Siri", "Ok") opens the text with it, so the title is
    /// the rest; and a day, and a part of the day, after the time belong to the clock ("at 5 tomorrow", "at 6 tomorrow
    /// morning"). Monday 2026-11-23, 14:10 Eastern.
    func testLeadInsAndADayAfterTheTimeOpenTheText() throws {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            ny.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
        }
        let p = QuickAddParser(now: at(11, 23, 14, 10), calendar: ny)
        let due: [(String, String, Date)] = [
            ("Can you remind me at 5 to call mom", "Call mom", at(11, 23, 17, 0)),
            ("Please remind me at 5 to call mom", "Call mom", at(11, 23, 17, 0)),
            ("Hey, remind me at 5 to call mom", "Call mom", at(11, 23, 17, 0)),
            ("Hey Siri, remind me at 5 to call mom", "Call mom", at(11, 23, 17, 0)),
            ("Would you remind me at 5 to call mom", "Call mom", at(11, 23, 17, 0)),
            ("Ok, remind me at 5 to call mom", "Call mom", at(11, 23, 17, 0)),
            ("Can you remind me tomorrow at 9 to call the vet", "Call the vet", at(11, 24, 9, 0)),
            ("Remind me at 5 tomorrow to call mom", "Call mom", at(11, 24, 17, 0)),
            ("Remind me at 6 tomorrow morning to stretch", "Stretch", at(11, 24, 6, 0)),
            ("Ok, can you please remind me to call mom at 5", "Call mom", at(11, 23, 17, 0)),
        ]
        for (text, title, date) in due {
            let r = p.parse(text)
            XCTAssertEqual(r.title, title, text)
            XCTAssertEqual(r.dueDate, date, text)
            XCTAssertEqual(r.reminderOffsetMinutes, 0, "reminded at the time: \(text)")
            XCTAssertNil(r.reminderDate, text)
        }
        let oven = p.parse("Could you remind me in 10 minutes to check the oven")
        XCTAssertEqual(oven.title, "Check the oven")
        XCTAssertEqual(oven.reminderDate, at(11, 23, 14, 20))
        XCTAssertNil(oven.dueDate)
        XCTAssertEqual(oven.tokens.map(\.text), ["Could you remind me in 10 minutes to"])
        XCTAssertEqual(ReminderPhrase(token: "Could you remind me in 10 minutes to"), .fromNow(ReminderSpan(minutes: 10)))
        // Not before "remind me", the words are the title's.
        XCTAssertEqual(p.parse("Can you call mom at 5").title, "Can you call mom")
        XCTAssertEqual(p.parse("Please call mom").title, "Please call mom")
        XCTAssertEqual(p.parse("Hey mom remind me at 5").title, "Hey mom")
        // A code keeps its day before the time, as the list writes it: "!4pm tomorrow" is a due day and a clock on it.
        let code = p.parse("Call mom !4pm tomorrow")
        XCTAssertEqual(code.dueDate, at(11, 24, 0, 0))
        XCTAssertEqual(code.reminderDate, at(11, 24, 16, 0))
    }

    func testPriorityInWords() {
        let cases: [(String, Priority)] = [("priority 1", .p1), ("Priority 2", .p2), ("priority three", .p3),
                                           ("priority four", .p4), ("priority one.", .p1)]
        for (words, priority) in cases {
            let r = parser.parse("Fix sink " + words)
            XCTAssertEqual(r.priority, priority, words)
            XCTAssertEqual(r.title, "Fix sink", words)
            XCTAssertEqual(r.tokens.map(\.kind), [.priority], words)
        }
        for text in ["Fix sink priority 5", "Fix sink priority", "Fix high priority sink"] {
            XCTAssertEqual(parser.parse(text).title, text, text)
            XCTAssertEqual(parser.parse(text).priority, .p4, text)
        }
    }

    /// "priority N" is said to the app only where it ends the words: at the end of the text, before punctuation, or
    /// before another phrase. In the middle of a sentence it is the sentence's (the review of brief 175, finding 9).
    func testPriorityInWordsOnlyWhereItEndsTheWords() {
        for text in ["Fix priority 1 bugs", "Discuss priority four with Sam", "Make it priority 2 for the team",
                     "Priority 1 customers first"] {
            let r = parser.parse(text)
            XCTAssertEqual(r.title, text, text)
            XCTAssertEqual(r.priority, .p4, text)
            XCTAssertTrue(r.tokens.isEmpty, text)
        }
        let cases: [(String, String, Priority)] = [
            ("Fix sink priority 1", "Fix sink", .p1),
            ("Fix sink priority 2, then paint", "Fix sink then paint", .p2),
            ("Fix sink priority 1: urgent", "Fix sink urgent", .p1),
            ("Fix sink priority three - then paint", "Fix sink - then paint", .p3),
            ("Fix sink priority 3 tomorrow", "Fix sink", .p3),
            ("Fix sink priority one #Home", "Fix sink", .p1),
            ("Fix sink priority 2 @calls", "Fix sink", .p2),
            ("Fix sink priority 2 !15m", "Fix sink", .p2),
            ("Fix sink priority 1 every day", "Fix sink", .p1),
            ("Fix sink priority 1 at 5pm", "Fix sink", .p1),
        ]
        for (text, title, priority) in cases {
            let r = parser.parse(text)
            XCTAssertEqual(r.title, title, text)
            XCTAssertEqual(r.priority, priority, text)
            XCTAssertTrue(r.tokens.contains { $0.kind == .priority }, text)
        }
        XCTAssertEqual(parser.parse("Fix sink priority 3 tomorrow").dueDate, Fixed.date(2026, 10, 22))
        XCTAssertEqual(parser.parse("Fix sink priority one #Home").projectName, "Home")
    }

    /// Words said in plain language that would leave no title are the title, and set nothing (the review of brief 175,
    /// finding 13): a task has a title. The rest of the text is read as usual.
    func testWordsThatWouldLeaveNoTitleAreTheTitle() {
        for text in ["Remind me in an hour", "Priority 3", "Remind me to", "remind me 30 minutes before", "Reminder in 10 minutes",
                     "Remind me at 4pm"] {
            let r = parser.parse(text)
            XCTAssertEqual(r.title, text, text)
            XCTAssertNil(r.reminderDate, text)
            XCTAssertNil(r.reminderFromNow, text)
            XCTAssertNil(r.reminderOffsetMinutes, text)
            XCTAssertNil(r.dueDate, text)
            XCTAssertEqual(r.priority, .p4, text)
            XCTAssertTrue(r.tokens.isEmpty, text)
        }
        let work = parser.parse("Remind me in an hour #Work")
        XCTAssertEqual(work.title, "Remind me in an hour")
        XCTAssertEqual(work.projectName, "Work")
        XCTAssertNil(work.reminderDate)
        let tomorrow = parser.parse("Priority 3 tomorrow")
        XCTAssertEqual(tomorrow.title, "Priority 3")
        XCTAssertEqual(tomorrow.dueDate, Fixed.date(2026, 10, 22))
        XCTAssertEqual(tomorrow.priority, .p4)
        // A code typed alone is still read: the words are the person's own.
        XCTAssertEqual(parser.parse("!15m").reminderFromNow, ReminderSpan(minutes: 15))
        XCTAssertEqual(parser.parse("p1").priority, .p1)
        // Switched off by the card, as before.
        let off = parser.parse("Call remind me in an hour", disabling: [QuickAddTokenKey(kind: .reminder, text: "remind me in an hour")])
        XCTAssertEqual(off.title, "Call remind me in an hour")
        XCTAssertEqual(parser.parse("Remind me in an hour", disabling: [QuickAddTokenKey(kind: .date, text: "x")]).title,
                       "Remind me in an hour")
        // Live: the same, once the phrase would light.
        XCTAssertEqual(parser.parse("Remind me in an hour ", mode: .live).title, "Remind me in an hour")
        XCTAssertTrue(parser.parse("Remind me in an hour ", mode: .live).tokens.isEmpty)
    }


    // MARK: Times as people say them (§4)

    func testTimesAsPeopleSayThem() {
        for text in ["Call 5 p.m.", "Call 5 P.M.", "Call 5 pm", "Call 5pm.", "Call 5p.m.", "Call 5 P.M", "Call at 5 p.m.",
                     "Call 5 p. m.", "Call at 5", "Call at 5:00", "Call 5PM,"] {
            let r = parser.parse(text)
            XCTAssertEqual(r.title, "Call", text)
            assertDate(r.dueDate, 2026, 10, 21, 17, 0)
        }
        assertDate(parser.parse("Run 9:30 a.m.").dueDate, 2026, 10, 22, 9, 30)
        assertDate(parser.parse("Run 9:30 A.M.").dueDate, 2026, 10, 22, 9, 30)
        assertDate(parser.parse("Call 2:15 p.m.").dueDate, 2026, 10, 22, 14, 15)
        XCTAssertEqual(parser.parse("Run 9:30 a.m.").title, "Run")
        // "at 1" to "at 4" with no day is the afternoon, tomorrow's once today's has gone; "at 5" and "at 6" the next
        // one to come (`testAShortHourReadsFromTheWholeText`); "at 7" on, a leading zero, am, and a bare hour after a
        // date word are as typed.
        assertDate(parser.parse("Lunch at 1").dueDate, 2026, 10, 22, 13, 0)
        assertDate(parser.parse("Lunch at 1:30").dueDate, 2026, 10, 22, 13, 30)
        assertDate(parser.parse("Lunch tomorrow at 1:30").dueDate, 2026, 10, 22, 13, 30)
        assertDate(parser.parse("Pick up at 6").dueDate, 2026, 10, 21, 18, 0)
        assertDate(parser.parse("Run at 7").dueDate, 2026, 10, 22, 7, 0)
        assertDate(parser.parse("Run at 06:00").dueDate, 2026, 10, 22, 6, 0)
        assertDate(parser.parse("Run at 6 am").dueDate, 2026, 10, 22, 6, 0)
        assertDate(parser.parse("Run tomorrow 5").dueDate, 2026, 10, 22, 5, 0)
        assertDate(parser.parse("Run friday 6").dueDate, 2026, 10, 23, 6, 0)
        assertDate(parser.parse("Run at 12").dueDate, 2026, 10, 22, 12, 0)
        assertDate(parser.parse("Lunch noon").dueDate, 2026, 10, 22, 12, 0)
        assertDate(parser.parse("Backup midnight").dueDate, 2026, 10, 22, 0, 0)
    }

    /// The brief's table, as the parser read those dictated lines on Monday 2026-11-23 at 14:10 Eastern and as it reads
    /// them now.
    func testTheDictatedLinesOfTheBrief() throws {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            ny.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
        }
        let now = at(11, 23, 14, 10)
        let p = QuickAddParser(now: now, calendar: ny)

        let mom = p.parse("Call mom tomorrow at 5 p.m.")
        XCTAssertEqual(mom.title, "Call mom", "was \"Call mom p.m.\"")
        XCTAssertEqual(mom.dueDate, at(11, 24, 17, 0), "was 05:00")

        let dentist = p.parse("Dentist appointment December 3rd at 2:15 p.m. priority 1")
        XCTAssertEqual(dentist.title, "Dentist appointment")
        XCTAssertEqual(dentist.dueDate, at(12, 3, 14, 15))
        XCTAssertEqual(dentist.priority, .p1)

        let sam = p.parse("Task: email Sam about the invoice next Tuesday at 9:30 a.m.")
        XCTAssertEqual(sam.title, "Task: email Sam about the invoice", "no \"a.m.\" left (\"Task:\" is the ring's, brief 176)")
        XCTAssertEqual(sam.dueDate, at(12, 1, 9, 30))

        let cleaning = p.parse("Pick up the dry cleaning at 6.")
        XCTAssertEqual(cleaning.title, "Pick up the dry cleaning")
        XCTAssertEqual(cleaning.dueDate, at(11, 23, 18, 0), "was tomorrow 06:00")

        let before = p.parse("Call mom tomorrow at 5 PM, remind me 30 minutes before.")
        XCTAssertEqual(before.title, "Call mom")
        XCTAssertEqual(before.dueDate, at(11, 24, 17, 0))
        XCTAssertEqual(before.reminderOffsetMinutes, 30)

        let remind = p.parse("Remind me to call mom in 30 minutes.")
        XCTAssertEqual(remind.title, "Call mom")
        XCTAssertEqual(remind.dueDate, at(11, 23, 14, 40))
        XCTAssertEqual(remind.reminderOffsetMinutes, 0, "at the time of the task")
    }

    /// "at 1" to "at 6" with no am or pm, read from the whole text (the supervisor's decision on the review of brief 175,
    /// finding 2, refined after it): "morning" or "night" among the words, as typed (24-hour); beside a day typed or a
    /// repeat's, the afternoon; with no day, 1 to 4 the afternoon and 5 or 6 the next one to come. Monday 2026-11-23,
    /// Eastern.
    func testAShortHourReadsFromTheWholeText() throws {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            ny.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
        }
        let p = QuickAddParser(now: at(11, 23, 14, 10), calendar: ny)

        // "morning" or "night": as typed.
        let meditate = p.parse("Meditate every morning at 6")
        XCTAssertEqual(meditate.title, "Meditate")
        XCTAssertEqual(meditate.recurrence?.frequency, .daily)
        XCTAssertEqual(meditate.dueDate, at(11, 24, 6, 0), "6 am, today's gone")
        let pills = p.parse("Take pills every night at 1")
        XCTAssertEqual(pills.title, "Take pills")
        XCTAssertEqual(pills.dueDate, at(11, 24, 1, 0))
        XCTAssertEqual(p.parse("Gym tomorrow morning at 6").dueDate, at(11, 24, 6, 0))
        XCTAssertEqual(p.parse("Catch the bus at 6 in the morning").dueDate, at(11, 24, 6, 0))
        let pray = p.parse("Pray at 5 every morning")
        XCTAssertEqual(pray.dueDate, at(11, 24, 5, 0))
        XCTAssertEqual(pray.recurrence?.frequency, .daily)

        // Beside a day typed, or a repeat's: the afternoon.
        XCTAssertEqual(p.parse("Call mom tomorrow at 5").dueDate, at(11, 24, 17, 0))
        XCTAssertEqual(p.parse("Call mom friday at 1").dueDate, at(11, 27, 13, 0))
        XCTAssertEqual(p.parse("Dinner tonight at 6").dueDate, at(11, 23, 18, 0), "tonight at 6 stays 6 pm")
        XCTAssertEqual(p.parse("Standup every weekday at 3").dueDate, at(11, 23, 15, 0))
        var editor = p
        editor.dueDayIsSet = true
        XCTAssertEqual(editor.parse("Call at 3").dueDate.map { ny.component(.hour, from: $0) }, 15, "the task's own day")

        // No day: 1 to 4 are the afternoon, today's if still ahead, else tomorrow's (nobody means 1 to 4 in the morning;
        // the supervisor on the review's fixes); 5 and 6 the next one to come, morning or afternoon ("Run at 5", "Wake up
        // at 6" can mean early morning).
        func parse(_ text: String, _ h: Int, _ min: Int) -> Date? { QuickAddParser(now: at(11, 23, h, min), calendar: ny).parse(text).dueDate }
        XCTAssertEqual(parse("Lunch at 1", 14, 30), at(11, 24, 13, 0), "1 pm gone: tomorrow's")
        XCTAssertEqual(parse("Call at 2", 9, 0), at(11, 23, 14, 0))
        XCTAssertEqual(parse("Pick up dry cleaning at 6", 14, 10), at(11, 23, 18, 0))
        XCTAssertEqual(parse("Wake up at 6", 22, 0), at(11, 24, 6, 0))
        XCTAssertEqual(parse("Run at 5", 3, 0), at(11, 23, 5, 0))
        XCTAssertEqual(parse("Run at 5", 14, 10), at(11, 23, 17, 0))
        XCTAssertEqual(parse("Call at 4:30", 3, 0), at(11, 23, 16, 30), "4:30 is the afternoon even before dawn")
        XCTAssertEqual(parse("Run at 6:30", 5, 0), at(11, 23, 6, 30))
        XCTAssertEqual(p.parse("Pick up the dry cleaning at 6").dueDate, at(11, 23, 18, 0))

        // A reminder's clock time reads the same way.
        XCTAssertEqual(p.parse("Bins friday remind me at 4").reminderDate, at(11, 27, 16, 0))
        XCTAssertEqual(p.parse("Gym tomorrow morning at 6 remind me at 5").reminderClock, ReminderClock(hour: 5, minute: 0))
        XCTAssertEqual(p.parse("Gym tomorrow morning at 6 remind me at 5").reminderDate, at(11, 24, 5, 0))
        XCTAssertEqual(p.parse("Bins !tomorrow at 4").reminderDate, at(11, 24, 16, 0))
        XCTAssertEqual(p.parse("Bins every night !at 1").reminderClock, ReminderClock(hour: 1, minute: 0))
        func remind(_ text: String, _ h: Int, _ min: Int) -> Date? {
            QuickAddParser(now: at(11, 23, h, min), calendar: ny).parse(text).reminderDate
        }
        XCTAssertEqual(remind("Bins !at 6", 22, 0), at(11, 24, 6, 0))
        XCTAssertEqual(remind("Bins !at 1", 14, 30), at(11, 24, 13, 0))
        XCTAssertEqual(remind("Bins !at 2", 9, 0), at(11, 23, 14, 0))
        XCTAssertEqual(remind("Bins !at 5", 3, 0), at(11, 23, 5, 0))
        XCTAssertEqual(remind("Bins !at 5", 14, 10), at(11, 23, 17, 0))
        // Said with "remind me" and no day, the due time (finding 4), read the same way.
        XCTAssertEqual(parse("Remind me at 2 to call the bank", 9, 0), at(11, 23, 14, 0))
        XCTAssertEqual(parse("Remind me at 5 to run", 3, 0), at(11, 23, 5, 0))
        // Alone, a phrase reads a short hour as the afternoon.
        XCTAssertEqual(ReminderPhrase(token: "!at 4"), .at(ReminderClock(hour: 16, minute: 0)))
    }

    /// Cues in the words decide the half of the day for "at 1" to "at 11" with no am or pm (the supervisor's decision on
    /// the second review of brief 175, finding 3). Morning cues (wake, waking, wake up, get up, breakfast, sunrise,
    /// dawn, early, morning): as typed. Evening cues (night, tonight, evening, dinner, supper): 5 to 11 the evening; 1 to
    /// 4 with "night" as typed, with the others the afternoon. No cue: the rule before (1 to 4 the afternoon, 5 and 6 the
    /// next to come with no day, 7 to 11 as typed). Monday 2026-11-23, Eastern.
    func testCuesInTheWordsDecideTheHalfOfTheDay() throws {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            ny.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
        }
        func due(_ text: String, _ h: Int = 14, _ min: Int = 10) -> Date? {
            QuickAddParser(now: at(11, 23, h, min), calendar: ny).parse(text).dueDate
        }
        // Morning cues.
        XCTAssertEqual(due("Wake up at 6 tomorrow"), at(11, 24, 6, 0))
        XCTAssertEqual(due("Breakfast at 6:30 tomorrow"), at(11, 24, 6, 30))
        XCTAssertEqual(due("Early flight at 6"), at(11, 24, 6, 0))
        XCTAssertEqual(due("Get up at 5 tomorrow"), at(11, 24, 5, 0))
        XCTAssertEqual(due("Sunrise hike at 6 friday"), at(11, 27, 6, 0))
        XCTAssertEqual(due("Breakfast meeting at 9"), at(11, 24, 9, 0))
        let wake = QuickAddParser(now: at(11, 23, 14, 10), calendar: ny).parse("Remind me at 5 to wake up")
        XCTAssertEqual(wake.title, "Wake up")
        XCTAssertEqual(wake.dueDate, at(11, 24, 5, 0))
        // Evening cues: 5 to 11 the evening.
        XCTAssertEqual(due("Game night at 6"), at(11, 23, 18, 0))
        XCTAssertEqual(due("Movie night Friday at 6"), at(11, 27, 18, 0))
        XCTAssertEqual(due("Dinner at 8"), at(11, 23, 20, 0))
        XCTAssertEqual(due("Call grandma tonight at 7"), at(11, 23, 19, 0), "tonight at 7 was 7 am")
        XCTAssertEqual(due("Supper at 6:30"), at(11, 23, 18, 30))
        XCTAssertEqual(due("Call at 9 this evening"), at(11, 23, 21, 0))
        let trash = QuickAddParser(now: at(11, 23, 14, 10), calendar: ny).parse("Remind me tonight at 9 to take out the trash")
        XCTAssertEqual(trash.title, "Take out the trash")
        XCTAssertEqual(trash.dueDate, at(11, 23, 21, 0))
        XCTAssertEqual(trash.reminderOffsetMinutes, 0)
        // 1 to 4: "night" as typed; "dinner" and "evening" the afternoon.
        XCTAssertEqual(due("Take pills every night at 1"), at(11, 24, 1, 0))
        XCTAssertEqual(due("Dinner at 4"), at(11, 23, 16, 0))
        XCTAssertEqual(due("Call at 3 this evening"), at(11, 23, 15, 0))
        // No cue: as last round.
        XCTAssertEqual(due("Lunch at 1", 14, 30), at(11, 24, 13, 0))
        XCTAssertEqual(due("Call at 2", 9, 0), at(11, 23, 14, 0))
        XCTAssertEqual(due("Pick up dry cleaning at 6"), at(11, 23, 18, 0))
        XCTAssertEqual(due("Wake up at 6", 22, 0), at(11, 24, 6, 0))
        XCTAssertEqual(due("Run at 5", 3, 0), at(11, 23, 5, 0))
        XCTAssertEqual(due("Run at 5"), at(11, 23, 17, 0))
        XCTAssertEqual(due("Run at 9"), at(11, 24, 9, 0))
        // As words only: a cue inside another word or a group's name is none.
        XCTAssertEqual(due("Nightly backup at 6"), at(11, 23, 18, 0), "no cue: the next 6 to come")
        XCTAssertEqual(due("Call #Dinner at 8"), at(11, 24, 8, 0))
        // Reminder clocks read the same way.
        func reminder(_ text: String) -> Date? { QuickAddParser(now: at(11, 23, 14, 10), calendar: ny).parse(text).reminderDate }
        XCTAssertEqual(reminder("Dinner !at 7"), at(11, 23, 19, 0))
        XCTAssertEqual(reminder("Breakfast !at 7"), at(11, 24, 7, 0))
        XCTAssertEqual(reminder("Game night friday !at 6"), at(11, 27, 18, 0))
        XCTAssertEqual(reminder("Pills every night !at 1"), at(11, 24, 1, 0))
        // Alone, a phrase reads 1 to 6 as the afternoon and 7 to 11 as typed.
        XCTAssertEqual(ReminderPhrase(token: "!at 4"), .at(ReminderClock(hour: 16, minute: 0)))
        XCTAssertEqual(ReminderPhrase(token: "!at 9"), .at(ReminderClock(hour: 9, minute: 0)))
    }

    /// "reminder" with no "me" and no "!" is weak evidence: plenty of titles hold the word. It takes only the relative
    /// forms (before, in, at the time), never a clock time or a day (the supervisor, round 36); "remind me" keeps them
    /// all. Monday 2026-11-23, 14:10 Eastern.
    func testABareReminderTakesOnlyTheRelativeForms() throws {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            ny.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
        }
        let now = at(11, 23, 14, 10)
        let p = QuickAddParser(now: now, calendar: ny)
        func noReminder(_ r: QuickAddResult, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertNil(r.reminderOffsetMinutes, text, file: file, line: line)
            XCTAssertNil(r.reminderDate, text, file: file, line: line)
            XCTAssertNil(r.reminderClock, text, file: file, line: line)
            XCTAssertFalse(r.tokens.contains { $0.kind == .reminder }, text, file: file, line: line)
        }

        let send = p.parse("Send reminder at 3pm")
        XCTAssertEqual(send.title, "Send reminder")
        XCTAssertEqual(send.dueDate, at(11, 23, 15, 0))
        noReminder(send, "Send reminder at 3pm")

        let bill = p.parse("Pay bill reminder tomorrow 9am")
        XCTAssertEqual(bill.title, "Pay bill reminder")
        XCTAssertEqual(bill.dueDate, at(11, 24, 9, 0))
        noReminder(bill, "Pay bill reminder tomorrow 9am")

        let email = p.parse("Email the reminder at 6")
        XCTAssertEqual(email.title, "Email the reminder")
        XCTAssertEqual(email.dueDate, at(11, 23, 18, 0), "at 6 is the afternoon")
        noReminder(email, "Email the reminder at 6")

        let dentist = p.parse("Dentist friday 3pm reminder 1 hour before")
        XCTAssertEqual(dentist.title, "Dentist")
        XCTAssertEqual(dentist.dueDate, at(11, 27, 15, 0))
        XCTAssertEqual(dentist.reminderOffsetMinutes, 60)

        // In the middle of the words, after a title word, it is the title's (finding 3 of the review): "in 10 minutes"
        // is the due time, as before brief 175. After punctuation it opens a clause and counts.
        let water = p.parse("Water plants reminder in 10 minutes")
        XCTAssertEqual(water.title, "Water plants reminder")
        XCTAssertEqual(water.dueDate, at(11, 23, 14, 20))
        noReminder(water, "Water plants reminder in 10 minutes")
        let watered = p.parse("Water plants, reminder in 10 minutes")
        XCTAssertEqual(watered.title, "Water plants,")
        XCTAssertEqual(watered.reminderFromNow, ReminderSpan(minutes: 10))
        XCTAssertEqual(watered.reminderDate, at(11, 23, 14, 20))
        XCTAssertNil(watered.dueDate, "a reminder from now, not a due time")

        let mom = p.parse("Call mom 5pm remind me at 4pm")
        XCTAssertEqual(mom.title, "Call mom")
        XCTAssertEqual(mom.dueDate, at(11, 23, 17, 0))
        XCTAssertEqual(mom.reminderClock, ReminderClock(hour: 16, minute: 0), "remind me keeps the clock form")
        XCTAssertEqual(mom.reminderDate, at(11, 23, 16, 0))

        // And at the time, as the relative forms do.
        XCTAssertEqual(p.parse("Standup 9:30am reminder at the time").reminderOffsetMinutes, 0)
    }

    /// Words in the middle of a sentence are the sentence's (the review of brief 175, finding 3): "reminder" alone is said
    /// to the app only where it opens the text, or after punctuation or another phrase, never after an article, a
    /// possessive or a verb; "remind me" never right after "to" (someone else is to do it). These read as they did
    /// before brief 175. Monday 2026-11-23, 14:10 Eastern.
    func testReminderWordsInTheMiddleOfASentenceStayItsWords() throws {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            ny.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
        }
        let p = QuickAddParser(now: at(11, 23, 14, 10), calendar: ny)
        let cases: [(String, String, Date, Bool)] = [
            ("Set a reminder in 10 minutes to check the oven", "Set a reminder to check the oven", at(11, 23, 14, 20), true),
            ("Send reminder in 2 days", "Send reminder", at(11, 25, 0, 0), false),
            ("Email reminder in 1 hour", "Email reminder", at(11, 23, 15, 10), true),
            ("Ask Sam to remind me in 2 days", "Ask Sam to remind me", at(11, 25, 0, 0), false),
            ("Tell Bob to remind me at 5pm about rent", "Tell Bob to remind me about rent", at(11, 23, 17, 0), true),
            ("Post my reminder in 10 minutes", "Post my reminder", at(11, 23, 14, 20), true),
            ("Check the reminder in an hour", "Check the reminder", at(11, 23, 15, 10), true),
        ]
        for (text, title, due, timed) in cases {
            let r = p.parse(text)
            XCTAssertEqual(r.title, title, text)
            XCTAssertEqual(r.dueDate, due, text)
            XCTAssertEqual(r.hasDueTime, timed, text)
            XCTAssertNil(r.reminderOffsetMinutes, text)
            XCTAssertNil(r.reminderDate, text)
            XCTAssertNil(r.reminderFromNow, text)
            XCTAssertFalse(r.tokens.contains { $0.kind == .reminder }, text)
        }

        // Where they are said to the app.
        let opens = p.parse("Reminder in 10 minutes to call mom")
        XCTAssertEqual(opens.title, "Call mom")
        XCTAssertEqual(opens.reminderDate, at(11, 23, 14, 20))
        XCTAssertNil(opens.dueDate)
        let afterStop = p.parse("Call mom. Reminder in an hour")
        XCTAssertEqual(afterStop.title, "Call mom.")
        XCTAssertEqual(afterStop.reminderDate, at(11, 23, 15, 10))
        XCTAssertEqual(p.parse("Call mom at 5pm, reminder 30 minutes before").reminderOffsetMinutes, 30)
        XCTAssertEqual(p.parse("Call mom at 5pm - reminder 30 minutes before").reminderOffsetMinutes, 30)
        XCTAssertEqual(p.parse("Dentist friday 3pm reminder 1 hour before").reminderOffsetMinutes, 60, "after a time")
        XCTAssertEqual(p.parse("Call mom remind me at 4pm").title, "Call mom")
        XCTAssertEqual(p.parse("Call mom remind me at 4pm").dueDate, at(11, 23, 16, 0), "no day of its own: the due time")
        XCTAssertEqual(p.parse("Call mom 5pm and remind me 30 minutes before").reminderOffsetMinutes, 30)
    }

    // MARK: What a pick writes

    func testTheWordsAPickWrites() {
        XCTAssertEqual(ReminderOffset.phrase(minutes: 0), "!At time of task")
        XCTAssertEqual(ReminderOffset.phrase(minutes: 1), "!1 minute before")
        XCTAssertEqual(ReminderOffset.phrase(minutes: 10), "!10 minutes before")
        XCTAssertEqual(ReminderOffset.phrase(minutes: 60), "!1 hour before")
        XCTAssertEqual(ReminderOffset.phrase(minutes: 90), "!90 minutes before")
        XCTAssertEqual(ReminderOffset.phrase(minutes: 120), "!2 hours before")
        XCTAssertEqual(ReminderOffset.phrase(minutes: 1440), "!1 day before")
        XCTAssertEqual(ReminderOffset.phrase(minutes: 2880), "!2 days before")
        for minutes in [0, 1, 5, 10, 15, 30, 45, 60, 90, 120, 180, 1440, 2880, 10_080, ReminderOffset.maxMinutes] {
            XCTAssertEqual(ReminderPhrase(token: ReminderOffset.phrase(minutes: minutes)), .beforeDue(minutes: minutes), "\(minutes)")
        }
        XCTAssertEqual(ReminderSpan(minutes: 15).phrase, "!In 15 minutes")
        XCTAssertEqual(ReminderSpan(minutes: 60).phrase, "!In 1 hour")
        XCTAssertEqual(ReminderSpan(minutes: 1).phrase, "!In 1 minute")
        XCTAssertEqual(ReminderSpan(days: 1).phrase, "!In 1 day")
        XCTAssertEqual(ReminderSpan(days: 2).phrase, "!In 2 days")
        XCTAssertEqual(ReminderSpan(days: 1, minutes: 30).phrase, "!1d30m", "no words for both: the code")
        for span in [ReminderSpan(minutes: 1), ReminderSpan(minutes: 15), ReminderSpan(minutes: 90), ReminderSpan(minutes: 1440),
                     ReminderSpan(days: 1), ReminderSpan(days: 28), ReminderSpan(days: 1, minutes: 30)] {
            XCTAssertEqual(ReminderPhrase(token: span.phrase), .fromNow(span), span.phrase)
        }
    }

    func testAClockReminder() {
        XCTAssertEqual(ReminderClock(hour: 16, minute: 0).text, "4:00 PM")
        XCTAssertEqual(ReminderClock(hour: 16, minute: 0).code, "!4pm")
        XCTAssertEqual(ReminderClock(hour: 9, minute: 30).text, "9:30 AM")
        XCTAssertEqual(ReminderClock(hour: 9, minute: 30).code, "!9:30am")
        XCTAssertEqual(ReminderClock(hour: 0, minute: 0).text, "12:00 AM")
        XCTAssertEqual(ReminderClock(hour: 12, minute: 0).code, "!12pm")
        for hour in 0..<24 {
            for minute in [0, 5, 30, 59] {
                let clock = ReminderClock(hour: hour, minute: minute)
                XCTAssertEqual(ReminderPhrase(token: "!" + clock.text), .at(clock), clock.text)
                XCTAssertEqual(ReminderPhrase(token: clock.code), .at(clock), clock.code)
            }
        }
        let four = ReminderClock(hour: 16, minute: 0)
        let friday = Fixed.date(2026, 10, 23)
        assertDate(four.date(dueDay: nil, now: Fixed.now, calendar: Fixed.calendar), 2026, 10, 21, 16, 0)
        assertDate(ReminderClock(hour: 9, minute: 0).date(dueDay: nil, now: Fixed.now, calendar: Fixed.calendar), 2026, 10, 22, 9, 0)
        assertDate(four.date(dueDay: friday, now: Fixed.now, calendar: Fixed.calendar), 2026, 10, 23, 16, 0)
        assertDate(four.date(dueDay: Fixed.date(2026, 10, 20), now: Fixed.now, calendar: Fixed.calendar), 2026, 10, 21, 16, 0)
        assertDate(ReminderClock(hour: 16, minute: 0, day: 1).date(dueDay: friday, now: Fixed.now, calendar: Fixed.calendar),
                   2026, 10, 22, 16, 0)
        // A day typed is that day, even gone.
        assertDate(ReminderClock(hour: 9, minute: 0, day: 0).date(dueDay: nil, now: Fixed.now, calendar: Fixed.calendar),
                   2026, 10, 21, 9, 0)
    }
}
