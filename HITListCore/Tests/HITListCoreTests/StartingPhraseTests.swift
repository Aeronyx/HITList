import XCTest
@testable import HITListCore

/// Brief 98, item 1 (George, 2026-11-11: "Have quickadd ignore the word 'starting'"). "starting" joins a
/// repeat to its first day: the word is part of the date's highlight, the day after it is the first
/// occurrence, and it is not a title word. Wherever no date follows it, it stays a title word.
/// Typed on Wednesday 2026-10-21 at 14:30 (`Fixed.now`).
final class StartingPhraseTests: XCTestCase {
    let parser = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar)

    private func highlights(_ r: QuickAddResult) -> [String] {
        r.tokens.filter { !$0.isSuperseded }.map(\.text)
    }

    // MARK: What "starting" joins

    func testEvery3DaysStartingFriday() {
        let r = parser.parse("water plants every 3 days starting friday")
        XCTAssertEqual(r.title, "water plants")
        assertDate(r.dueDate, 2026, 10, 23)
        XCTAssertFalse(r.hasDueTime)
        XCTAssertEqual(r.recurrence?.encoded, "daily;3")
        XCTAssertEqual(highlights(r), ["every 3 days", "starting friday"])
        XCTAssertEqual(r.tokens.map(\.kind), [.recurrence, .date])
    }

    func testEvery2WeeksStartingNov24() {
        let r = parser.parse("every 2 weeks starting nov 24")
        XCTAssertEqual(r.title, "")
        assertDate(r.dueDate, 2026, 11, 24)
        XCTAssertEqual(r.recurrence?.encoded, "weekly;2")
        XCTAssertEqual(highlights(r), ["every 2 weeks", "starting nov 24"])
    }

    func testStartingMondayEveryWeekday() {
        let r = parser.parse("Standup starting monday every weekday")
        XCTAssertEqual(r.title, "Standup")
        assertDate(r.dueDate, 2026, 10, 26)
        XCTAssertEqual(r.recurrence, .weekdays)
        XCTAssertEqual(highlights(r), ["starting monday", "every weekday"])
    }

    func testStartingTomorrowAlone() {
        let r = parser.parse("take vitamins starting tomorrow")
        XCTAssertEqual(r.title, "take vitamins")
        assertDate(r.dueDate, 2026, 10, 22)
        XCTAssertNil(r.recurrence)
        XCTAssertEqual(highlights(r), ["starting tomorrow"])
    }

    func testStartingOnAndStartingFrom() {
        for typed in ["starting on friday", "starting from friday", "Starting On Fri", "starting from fri,"] {
            let r = parser.parse("yoga every day \(typed)")
            XCTAssertEqual(r.title, "yoga", typed)
            assertDate(r.dueDate, 2026, 10, 23)
            XCTAssertEqual(highlights(r), ["every day", typed], typed)
        }
    }

    func testOtherDatePhrasesAfterStarting() {
        let cases: [(String, (Int, Int, Int))] = [
            ("every day starting next monday", (2026, 10, 26)),
            ("every day starting in 3 days", (2026, 10, 24)),
            ("every day starting 11/24", (2026, 11, 24)),
            ("every day starting jan 5", (2027, 1, 5)),
            ("every day starting today", (2026, 10, 21)),
        ]
        for (typed, due) in cases {
            let r = parser.parse("Journal \(typed)")
            XCTAssertEqual(r.title, "Journal", typed)
            assertDate(r.dueDate, due.0, due.1, due.2)
        }
    }

    /// A day after "starting" that the rule does not fall on: the first occurrence on or after it, so
    /// "every monday starting nov 24" (a Tuesday) starts the next Monday, and "every month on the 28th
    /// starting dec 1" on Dec 28. A date typed without "starting" is kept as typed, as before.
    func testTheFirstOccurrenceOnOrAfterTheStart() {
        let monday = parser.parse("Gym every monday starting nov 24")
        assertDate(monday.dueDate, 2026, 11, 30)
        XCTAssertEqual(monday.title, "Gym")
        let placed = parser.parse("Rent every month on the 28th starting dec 1")
        assertDate(placed.dueDate, 2026, 12, 28)
        XCTAssertEqual(placed.recurrence?.encoded, "monthly;1;;28;;d28")
        let weekdays = parser.parse("Standup every weekday starting sat")
        assertDate(weekdays.dueDate, 2026, 10, 26)
        // On a day of the rule: that day.
        assertDate(parser.parse("Gym every monday starting nov 30").dueDate, 2026, 11, 30)
        // Without "starting": as typed (unchanged).
        assertDate(parser.parse("Gym every monday nov 24").dueDate, 2026, 11, 24)
    }

    func testWithATime() {
        let r = parser.parse("Standup every weekday starting tomorrow 9am")
        XCTAssertEqual(r.title, "Standup")
        assertDate(r.dueDate, 2026, 10, 22, 9, 0)
        XCTAssertEqual(r.recurrence?.encoded, "weekly;1;2,3,4,5,6;;09:00")
        // A bare hour right after the day, as after any date word.
        let bare = parser.parse("Pills every day starting tom 9")
        assertDate(bare.dueDate, 2026, 10, 22, 9, 0)
        XCTAssertEqual(highlights(bare), ["every day", "starting tom", "9"])
    }

    // MARK: Where "starting" stays a title word

    func testStartingWithNoDateAfterItIsATitleWord() {
        let plain: [(typed: String, title: String, highlights: [String])] = [
            ("email the starting lineup", "email the starting lineup", []),
            ("starting salary talk fri", "starting salary talk", ["fri"]),
            ("Fix the starting motor tomorrow", "Fix the starting motor", ["tomorrow"]),
            ("starting from scratch", "starting from scratch", []),
            ("starting", "starting", []),
            ("every day starting", "starting", ["every day"]),
            ("every day starting from", "starting from", ["every day"]),
            ("Write the starting on page", "Write the starting on page", []),
            ("game starting 5pm", "game starting", ["5pm"]),
            ("starting in 2 hours", "starting", ["in 2 hours"]),
            ("Read starting over sunday", "Read starting over", ["sunday"]),
        ]
        for case let (typed, title, lit) in plain {
            let r = parser.parse(typed)
            XCTAssertEqual(r.title, title, typed)
            XCTAssertEqual(highlights(r), lit, typed)
        }
    }

    // MARK: Switching off, overriding, typing

    func testSwitchingOffTheStartPutsItsWordsBack() {
        let typed = "water plants every 3 days starting friday"
        let start = parser.parse(typed).tokens.first { $0.kind == .date }!
        let r = parser.parse(typed, disabling: [start.key])
        XCTAssertEqual(r.title, "water plants starting friday")
        assertDate(r.dueDate, 2026, 10, 21)
        XCTAssertEqual(highlights(r), ["every 3 days"])
    }

    func testALaterDateOverridesTheStart() {
        let r = parser.parse("Journal every day starting fri tom")
        XCTAssertEqual(r.title, "Journal starting fri")
        assertDate(r.dueDate, 2026, 10, 22)
    }

    func testWhileTypingTheWordWaitsForItsDay() {
        XCTAssertEqual(parser.parse("every day starting", mode: .live).title, "starting")
        XCTAssertEqual(parser.parse("every day starting f", mode: .live).title, "starting f")
        XCTAssertEqual(parser.parse("every day starting fri", mode: .live).title, "")
    }
}
