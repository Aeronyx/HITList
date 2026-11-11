import XCTest
@testable import HITListCore

/// Brief 98, item 2 (George, 2026-11-11: "add detection/support for multi-day phrases such as 'vacuum on
/// tuesday thursday and saturday'"). A task has one date, so several weekdays named together are a repeat:
/// weekly on those days, due on the next of them, one highlight over the whole phrase, with or without
/// "every". One weekday alone stays a date; two that are not a list stay what they are today.
/// Typed on Wednesday 2026-10-21 at 14:30 (`Fixed.now`; Thu 22, Fri 23, Sat 24, Sun 25, Mon 26, Tue 27).
final class WeekdayListTests: XCTestCase {
    let parser = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar)

    private func check(_ input: String, title: String, due: (Int, Int, Int), at time: (Int, Int)? = nil,
                       rule encoded: String, highlight: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        let r = parser.parse(input)
        XCTAssertEqual(r.title, title, "title", file: file, line: line)
        assertDate(r.dueDate, due.0, due.1, due.2, time?.0 ?? 0, time?.1 ?? 0, file: file, line: line)
        XCTAssertEqual(r.hasDueTime, time != nil, "has a time", file: file, line: line)
        XCTAssertEqual(r.recurrence?.encoded, encoded, "rule", file: file, line: line)
        let repeats = r.tokens.filter { $0.kind == .recurrence && !$0.isSuperseded }.map(\.text)
        XCTAssertEqual(repeats, [highlight], "highlight", file: file, line: line)
        XCTAssertFalse(r.tokens.contains { $0.kind == .date && !$0.isSuperseded }, "no date token", file: file, line: line)
    }

    // MARK: George's phrases

    func testVacuumOnTuesdayThursdayAndSaturday() {
        check("vacuum on tuesday thursday and saturday", title: "vacuum", due: (2026, 10, 22),
              rule: "weekly;1;3,5,7", highlight: "on tuesday thursday and saturday")
    }

    func testVacuumTueThuSat() {
        check("vacuum tue thu sat", title: "vacuum", due: (2026, 10, 22), rule: "weekly;1;3,5,7", highlight: "tue thu sat")
    }

    func testEveryMonWedAndFri() {
        // Today is a Wednesday: today.
        check("every mon, wed & fri", title: "", due: (2026, 10, 21), rule: "weekly;1;2,4,6", highlight: "every mon, wed & fri")
    }

    func testGymMonWedFri7am() {
        // 7 am has passed on Wednesday: Friday.
        let r = parser.parse("gym mon/wed/fri 7am")
        XCTAssertEqual(r.title, "gym")
        assertDate(r.dueDate, 2026, 10, 23, 7, 0)
        XCTAssertEqual(r.recurrence?.encoded, "weekly;1;2,4,6;;07:00")
        XCTAssertEqual(r.tokens.map(\.text), ["mon/wed/fri", "7am"])
        XCTAssertEqual(r.tokens.map(\.kind), [.recurrence, .time])
    }

    func testOnWeekdaysAndWeekends() {
        check("standup on weekdays", title: "standup", due: (2026, 10, 21), rule: "weekly;1;2,3,4,5,6", highlight: "on weekdays")
        check("standup weekdays", title: "standup", due: (2026, 10, 21), rule: "weekly;1;2,3,4,5,6", highlight: "weekdays")
        check("clean garage weekends", title: "clean garage", due: (2026, 10, 24), rule: "weekly;1;1,7", highlight: "weekends")
        check("long run on weekends", title: "long run", due: (2026, 10, 24), rule: "weekly;1;1,7", highlight: "on weekends")
        let timed = parser.parse("standup weekdays 9am")
        assertDate(timed.dueDate, 2026, 10, 22, 9, 0)
    }

    func testAnIntervalAndAStart() {
        let r = parser.parse("every 2 weeks on tue and thu starting dec 1")
        XCTAssertEqual(r.title, "")
        assertDate(r.dueDate, 2026, 12, 1)
        XCTAssertEqual(r.recurrence?.encoded, "weekly;2;3,5")
        XCTAssertEqual(r.tokens.map(\.text), ["every 2 weeks on tue and thu", "starting dec 1"])
        // Tue, Thu, then two weeks on.
        let cal = Fixed.calendar
        let second = r.recurrence!.nextOccurrence(after: r.dueDate!, calendar: cal)
        assertDate(second, 2026, 12, 3)
        assertDate(r.recurrence!.nextOccurrence(after: second, calendar: cal), 2026, 12, 15)
    }

    // MARK: More ways to say it

    func testMoreLists() {
        let cases: [(typed: String, due: (Int, Int, Int), rule: String)] = [
            ("tue and thu", (2026, 10, 22), "weekly;1;3,5"),
            ("mon, wed, fri", (2026, 10, 21), "weekly;1;2,4,6"),
            ("Monday, Wednesday and Friday", (2026, 10, 21), "weekly;1;2,4,6"),
            ("sat & sun", (2026, 10, 24), "weekly;1;1,7"),
            ("on mon/wed", (2026, 10, 21), "weekly;1;2,4"),
            ("mon,thu", (2026, 10, 22), "weekly;1;2,5"),
            ("TUE THU", (2026, 10, 22), "weekly;1;3,5"),
            ("every mon-fri", (2026, 10, 21), "weekly;1;2,3,4,5,6"),
            ("mon-fri", (2026, 10, 21), "weekly;1;2,3,4,5,6"),
            ("tue–thu", (2026, 10, 21), "weekly;1;3,4,5"),
            ("on tuesdays and thursdays", (2026, 10, 22), "weekly;1;3,5"),
            ("on mondays", (2026, 10, 26), "weekly;1;2"),
            ("every week on fri", (2026, 10, 23), "weekly;1;6"),
            ("weekly on mon and thu", (2026, 10, 22), "weekly;1;2,5"),
            ("every other week on mon, wed", (2026, 10, 21), "weekly;2;2,4"),
            ("every other tue and thu", (2026, 10, 22), "weekly;2;3,5"),
            ("every 3 weeks on sat", (2026, 10, 24), "weekly;3;7"),
        ]
        for case let (typed, due, rule) in cases {
            let r = parser.parse("chores \(typed)")
            XCTAssertEqual(r.title, "chores", typed)
            assertDate(r.dueDate, due.0, due.1, due.2)
            XCTAssertEqual(r.recurrence?.encoded, rule, typed)
            XCTAssertEqual(r.tokens.map(\.text), [typed], typed)
        }
    }

    func testFiveWeekdaysAreEveryWeekday() {
        XCTAssertEqual(parser.parse("standup mon tue wed thu fri").recurrence, .weekdays)
    }

    func testTheListSteps() {
        let r = parser.parse("vacuum tue thu sat")
        let cal = Fixed.calendar
        var due = r.dueDate!
        var seen: [Date] = [due]
        for _ in 0..<3 { due = r.recurrence!.nextOccurrence(after: due, calendar: cal); seen.append(due) }
        XCTAssertEqual(seen, [Fixed.date(2026, 10, 22), Fixed.date(2026, 10, 24), Fixed.date(2026, 10, 27), Fixed.date(2026, 10, 29)])
    }

    /// For the supervisor (brief 98 builds this rule; `RecurrenceRule.swift` is brief 97's): an every-other-week
    /// rule whose days straddle the calendar's week boundary steps wrong. With a Sunday-first week (US, as
    /// `Fixed.calendar`) "every other sat and sun" from Sat Oct 24 goes to Sun Nov 1, then Sat Nov 7, Sun Nov
    /// 15: the first weekend's Sunday is skipped and every Sunday falls in the off week, because the walk counts
    /// calendar weeks from the due date's own week. A Monday-first week gets it right. Every week (interval 1)
    /// and days inside one week (tue and thu) are unaffected.
    func testEveryOtherWeekendStepsByTheWeekendNotTheCalendarWeek() {
        let r = parser.parse("every other sat and sun")
        XCTAssertEqual(r.recurrence?.encoded, "weekly;2;1,7")
        assertDate(r.dueDate, 2026, 10, 24)
        let cal = Fixed.calendar
        XCTExpectFailure("RecurrenceRule's weekly walk counts calendar weeks (brief 97 owns RecurrenceRule.swift)")
        assertDate(r.recurrence?.nextOccurrence(after: r.dueDate!, calendar: cal), 2026, 10, 25)
    }

    // MARK: What stays as it is today

    func testDaysThatAreNotAListStayAsTheyAre() {
        // Not a list: the later date overrides the earlier one, as for any two dates (George, 2026-11-04).
        let apart = parser.parse("call mom fri about sunday")
        XCTAssertNil(apart.recurrence)
        XCTAssertEqual(apart.title, "call mom fri about")
        assertDate(apart.dueDate, 2026, 10, 25)

        let plain: [(typed: String, due: (Int, Int, Int)?)] = [
            ("call mom fri", (2026, 10, 23)),
            ("call mom on fri", (2026, 10, 23)),
            ("mon or tue", (2026, 10, 27)),
            ("either mon or tue", (2026, 10, 27)),
            ("decide between mon and fri", (2026, 10, 23)),
            ("weekend", (2026, 10, 24)),
            ("this weekend", (2026, 10, 24)),
            ("weekday lunch spot", nil),
            ("I hate mondays", nil),
            ("sun and moon poster", (2026, 10, 25)),
            ("fri, then sat", (2026, 10, 24)),
            ("next mon and tue", (2026, 10, 27)),
            ("fri 5 jan", (2027, 1, 5)),
        ]
        for case let (typed, due) in plain {
            let r = parser.parse(typed)
            XCTAssertNil(r.recurrence, typed)
            if let due { assertDate(r.dueDate, due.0, due.1, due.2) } else { XCTAssertNil(r.dueDate, typed) }
        }
        // "every month on fri": the plain repeat, then a date (brief 71's lookalike).
        XCTAssertEqual(parser.parse("every month on fri").tokens.map(\.text), ["every month", "on fri"])
    }

    // MARK: Switching off, typing

    func testTappingTheHighlightTurnsItBackIntoTitleWords() {
        let typed = "vacuum on tuesday thursday and saturday"
        let rule = parser.parse(typed).tokens.first { $0.kind == .recurrence }!
        let r = parser.parse(typed, disabling: [rule.key])
        XCTAssertEqual(r.title, typed)
        XCTAssertNil(r.recurrence)
        XCTAssertNil(r.dueDate)
        XCTAssertTrue(r.tokens.isEmpty)
    }

    func testAnAndStillBeingTypedIsATitleWord() {
        let r = parser.parse("vacuum tue thu and", mode: .live)
        XCTAssertEqual(r.title, "vacuum and")
        XCTAssertEqual(r.tokens.map(\.text), ["tue thu"])
    }

    func testALaterRepeatOverridesTheList() {
        let r = parser.parse("vacuum tue thu every day")
        XCTAssertEqual(r.recurrence, .daily)
        XCTAssertEqual(r.title, "vacuum tue thu")
    }
}
