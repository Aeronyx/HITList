import XCTest
@testable import HITListCore

/// Brief 37 (George, 2026-11-04): a later phrase of the same kind overrides an earlier one ("let it"), and
/// tapping the winner off brings the earlier one back ("jan 6 zach fox [in a month]" → "[jan 6] zach fox
/// in a month"). The earlier phrase stays in the token list marked `isSuperseded`: no highlight, no
/// effect, its words plain title text like any other unhighlighted words.
final class SupersededPhraseTests: XCTestCase {
    let parser = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar, knownProjects: ["Finance", "Work"])

    private func key(_ kind: QuickAddToken.Kind, _ text: String) -> QuickAddTokenKey {
        QuickAddTokenKey(kind: kind, text: text)
    }

    private func active(_ r: QuickAddResult) -> [String] { r.tokens.filter { !$0.isSuperseded }.map(\.text) }
    private func superseded(_ r: QuickAddResult) -> [String] { r.tokens.filter(\.isSuperseded).map(\.text) }

    private func assertRangesMatch(_ r: QuickAddResult, in input: String, file: StaticString = #filePath, line: UInt = #line) {
        for token in r.tokens { XCTAssertEqual(String(input[token.range]), token.text, file: file, line: line) }
    }

    func testGeorgesExampleTheLaterDateWinsAndTheEarlierComesBack() {
        let input = "jan 6 zach fox in a month"
        let r = parser.parse(input)
        assertDate(r.dueDate, 2026, 11, 21)
        XCTAssertEqual(active(r), ["in a month"])
        XCTAssertEqual(superseded(r), ["jan 6"])
        XCTAssertEqual(r.title, "jan 6 zach fox", "the earlier phrase is plain text, so it is title text")
        assertRangesMatch(r, in: input)

        let off = parser.parse(input, disabling: [key(.date, "in a month")])
        assertDate(off.dueDate, 2027, 1, 6)
        XCTAssertFalse(off.hasDueTime)
        XCTAssertEqual(active(off), ["jan 6"])
        XCTAssertEqual(superseded(off), [])
        XCTAssertEqual(off.title, "zach fox in a month")
        assertRangesMatch(off, in: input)
    }

    func testThreeDatesDisablingTheLastLetsTheMiddleWin() {
        let input = "Call tomorrow or friday or jan 6"
        let r = parser.parse(input)
        assertDate(r.dueDate, 2027, 1, 6)
        XCTAssertEqual(active(r), ["jan 6"])
        XCTAssertEqual(superseded(r), ["tomorrow", "friday"])

        let lastOff = parser.parse(input, disabling: [key(.date, "jan 6")])
        assertDate(lastOff.dueDate, 2026, 10, 23)
        XCTAssertEqual(active(lastOff), ["friday"])
        XCTAssertEqual(superseded(lastOff), ["tomorrow"])
        XCTAssertEqual(lastOff.title, "Call tomorrow or or jan 6")
        assertRangesMatch(lastOff, in: input)

        let bothOff = parser.parse(input, disabling: [key(.date, "jan 6"), key(.date, "friday")])
        assertDate(bothOff.dueDate, 2026, 10, 22)
        XCTAssertEqual(active(bothOff), ["tomorrow"])
    }

    func testDisablingASupersededPhraseChangesNothingVisible() {
        let input = "Call tomorrow or friday or jan 6"
        let plain = parser.parse(input)
        let middleOff = parser.parse(input, disabling: [key(.date, "friday")])
        XCTAssertEqual(active(middleOff), active(plain), "the same highlight")
        XCTAssertEqual(middleOff.dueDate, plain.dueDate)
        XCTAssertEqual(middleOff.title, plain.title, "the middle was plain text before and after")
        XCTAssertEqual(superseded(middleOff), ["tomorrow"], "switched off, it is plain words, not a waiting phrase")
        // …and once the last goes too, the first comes back, not the switched-off middle.
        let alsoLastOff = parser.parse(input, disabling: [key(.date, "friday"), key(.date, "jan 6")])
        assertDate(alsoLastOff.dueDate, 2026, 10, 22)
        XCTAssertEqual(active(alsoLastOff), ["tomorrow"])
    }

    func testPrioritiesTheSameWay() {
        let input = "Ship p1 then p2 then p3"
        let r = parser.parse(input)
        XCTAssertEqual(r.priority, .p3)
        XCTAssertEqual(active(r), ["p3"])
        XCTAssertEqual(superseded(r), ["p1", "p2"])
        XCTAssertEqual(r.title, "Ship p1 then p2 then")

        let lastOff = parser.parse(input, disabling: [key(.priority, "p3")])
        XCTAssertEqual(lastOff.priority, .p2)
        XCTAssertEqual(active(lastOff), ["p2"])
        XCTAssertEqual(superseded(lastOff), ["p1"])

        let middleOff = parser.parse(input, disabling: [key(.priority, "p2")])
        XCTAssertEqual(middleOff.priority, .p3)
        XCTAssertEqual(active(middleOff), ["p3"])
        XCTAssertEqual(middleOff.title, r.title)

        XCTAssertEqual(parser.parse(input, disabling: [key(.priority, "p2"), key(.priority, "p3")]).priority, .p1)
    }

    func testADateAndATimeInSeparatePhrasesBothCount() {
        let r = parser.parse("test 2 p1 tom 4")
        XCTAssertEqual(r.title, "test 2")
        assertDate(r.dueDate, 2026, 10, 22, 4, 0)
        XCTAssertEqual(r.priority, .p1)
        XCTAssertEqual(active(r), ["p1", "tom", "4"])
        XCTAssertEqual(superseded(r), [])
        // So do a relative phrase and a typed time, a repeat and a date, and several labels.
        XCTAssertEqual(superseded(parser.parse("Call mum in 2 hours 5pm")), [])
        XCTAssertEqual(superseded(parser.parse("Journal every day starting jan 5")), [])
        let labels = parser.parse("Pay @bills @errand")
        XCTAssertEqual(labels.labelNames, ["bills", "errand"])
        XCTAssertEqual(superseded(labels), [])
    }

    func testEveryKindThatHoldsOneValueIsOverridden() {
        let project = parser.parse("Budget #Work then #Finance")
        XCTAssertEqual(project.projectName, "Finance")
        XCTAssertEqual(superseded(project), ["#Work"])
        XCTAssertEqual(parser.parse("Budget #Work then #Finance", disabling: [key(.project, "#Finance")]).projectName, "Work")

        let time = parser.parse("Dentist 5pm no 6pm")
        assertDate(time.dueDate, 2026, 10, 21, 18, 0)
        XCTAssertEqual(superseded(time), ["5pm"])
        assertDate(parser.parse("Dentist 5pm no 6pm", disabling: [key(.time, "6pm")]).dueDate, 2026, 10, 21, 17, 0)

        let repeats = parser.parse("Bins every day every week")
        XCTAssertEqual(repeats.recurrence?.frequency, .weekly)
        XCTAssertEqual(superseded(repeats), ["every day"])
        XCTAssertEqual(parser.parse("Bins every day every week", disabling: [key(.recurrence, "every week")]).recurrence?.frequency, .daily)

        let reminder = parser.parse("Ping 5pm !15mb !1hb")
        XCTAssertEqual(reminder.reminderOffsetMinutes, 60)
        XCTAssertEqual(superseded(reminder), ["!15mb"])
        XCTAssertEqual(parser.parse("Ping 5pm !15mb !1hb", disabling: [key(.reminder, "!1hb")]).reminderOffsetMinutes, 15)
    }

    func testARelativeMomentAndADateOverrideEachOther() {
        // A plain date after "in 2 hours" drops the moment: that day, all day.
        let day = parser.parse("Call in 2 hours or tomorrow")
        assertDate(day.dueDate, 2026, 10, 22)
        XCTAssertFalse(day.hasDueTime)
        XCTAssertEqual(superseded(day), ["in 2 hours"])
        // The other way round, the moment wins with its time.
        let moment = parser.parse("Call tomorrow or in 2 hours")
        assertDate(moment.dueDate, 2026, 10, 21, 16, 30)
        XCTAssertTrue(moment.hasDueTime)
        XCTAssertEqual(superseded(moment), ["tomorrow"])
        // Switching the moment off brings tomorrow back, all day.
        let back = parser.parse("Call tomorrow or in 2 hours", disabling: [key(.date, "in 2 hours")])
        assertDate(back.dueDate, 2026, 10, 22)
        XCTAssertFalse(back.hasDueTime)
    }

    func testCallTomTomorrowKeepsTheNameInTheTitle() {
        // Before: the first "tom" won and "tomorrow" was title text ("Call tomorrow").
        let r = parser.parse("Call tom tomorrow")
        assertDate(r.dueDate, 2026, 10, 22)
        XCTAssertEqual(r.title, "Call tom")
        XCTAssertEqual(active(r), ["tomorrow"])
    }

    func testSupersededRangesStayRightAroundWideCharacters() {
        let input = "Café 🎉 p1 ☕️ tom p2 fri"
        let r = parser.parse(input, disabling: [key(.date, "fri")])
        XCTAssertEqual(active(r), ["tom", "p2"])
        XCTAssertEqual(superseded(r), ["p1"])
        assertRangesMatch(r, in: input)
    }
}
