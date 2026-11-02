import XCTest
@testable import HITListCore

/// Brief 28 (A): tapping a highlighted token turns it off; the words stay in the title as plain text.
final class TokenDisablingTests: XCTestCase {
    let parser = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar,
                                knownProjects: ["Finance", "Home Repairs", "Work"],
                                knownLabels: ["bills", "errand"])

    private func key(_ kind: QuickAddToken.Kind, _ text: String) -> QuickAddTokenKey {
        QuickAddTokenKey(kind: kind, text: text)
    }

    /// Every token's range points at its own text in the input the user typed.
    private func assertRangesMatch(_ result: QuickAddResult, in input: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        for token in result.tokens {
            XCTAssertEqual(String(input[token.range]), token.text, file: file, line: line)
        }
    }

    func testCallTomBecomesATaskCalledCallTom() throws {
        let input = "Call Tom"
        let tom = try XCTUnwrap(parser.parse(input).tokens.first)
        XCTAssertEqual(tom.kind, .date, "\"Tom\" reads as tomorrow until it is switched off")

        let r = parser.parse(input, disabling: [tom.key])
        XCTAssertEqual(r.title, "Call Tom")
        XCTAssertNil(r.dueDate)
        XCTAssertFalse(r.hasDueTime)
        XCTAssertTrue(r.tokens.isEmpty)
    }

    func testNothingDisabledIsThePlainParse() {
        let input = "Pay rent tomorrow 5pm p1 #Finance @bills every month"
        XCTAssertEqual(parser.parse(input, disabling: []), parser.parse(input))
    }

    func testTheChoiceSurvivesTypingOn() {
        let input = "Call Tom about the 5pm meeting p2"
        let r = parser.parse(input, disabling: [key(.date, "Tom")])
        XCTAssertEqual(r.title, "Call Tom about the meeting")
        XCTAssertTrue(r.hasDueTime, "5pm is still a time")
        assertDate(r.dueDate, 2026, 10, 21, 17, 0)
        XCTAssertEqual(r.priority, .p2)
        XCTAssertEqual(r.tokens.map(\.kind), [.time, .priority])
        assertRangesMatch(r, in: input)
    }

    func testTheKeyIgnoresCaseAndSpacing() {
        XCTAssertEqual(key(.date, "Next  Friday"), key(.date, "next friday"))
        let r = parser.parse("Plan next friday party", disabling: [key(.date, "NEXT FRIDAY")])
        XCTAssertEqual(r.title, "Plan next friday party")
        XCTAssertNil(r.dueDate)
    }

    func testAMultiWordTokenStaysWholeAndALaterOneStillCounts() {
        let input = "Plan next friday party tomorrow"
        let r = parser.parse(input, disabling: [key(.date, "next friday")])
        XCTAssertEqual(r.title, "Plan next friday party")
        assertDate(r.dueDate, 2026, 10, 22)
        XCTAssertEqual(r.tokens.map(\.text), ["tomorrow"])
        assertRangesMatch(r, in: input)
    }

    func testEveryCopyOfTheWordsStaysPlain() {
        let r = parser.parse("tom and tom", disabling: [key(.date, "tom")])
        XCTAssertEqual(r.title, "tom and tom")
        XCTAssertNil(r.dueDate)
        XCTAssertTrue(r.tokens.isEmpty)
    }

    func testOnlyThatKindIsSwitchedOff() {
        // "p1" switched off as a priority; the date and group still count.
        let input = "Ship p1 build tomorrow #Work"
        let r = parser.parse(input, disabling: [key(.priority, "p1"), key(.date, "p1")])
        XCTAssertEqual(r.priority, .p4)
        XCTAssertEqual(r.title, "Ship p1 build")
        XCTAssertEqual(r.projectName, "Work")
        assertDate(r.dueDate, 2026, 10, 22)
        // A key of another kind with the same words does nothing.
        XCTAssertEqual(parser.parse(input, disabling: [key(.label, "p1")]), parser.parse(input))
    }

    func testEachKindCanBeSwitchedOff() {
        let cases: [(String, QuickAddToken.Kind, String)] = [
            ("Water plants every day", .recurrence, "every day"),
            ("Dentist at 5pm", .time, "at 5pm"),
            ("Dentist 5pm", .time, "5pm"),
            ("Budget #Finance", .project, "#Finance"),
            ("Fix sink #\"Home Repairs\"", .project, "#\"Home Repairs\""),
            ("Fix sink #Home Repairs", .project, "#Home Repairs"),
            ("Pay @bills", .label, "@bills"),
            ("Ping !15mb", .reminder, "!15mb"),
            ("Ship p1", .priority, "p1"),
        ]
        for (input, kind, text) in cases {
            let parsed = parser.parse(input)
            XCTAssertEqual(parsed.tokens.first?.kind, kind, input)
            XCTAssertEqual(parsed.tokens.first?.text, text, input)
            let r = parser.parse(input, disabling: [key(kind, text)])
            XCTAssertEqual(r.title, input, "the words stay in the title: \(input)")
            XCTAssertTrue(r.tokens.isEmpty, input)
            XCTAssertNil(r.dueDate, input)
            XCTAssertNil(r.projectName, input)
            XCTAssertTrue(r.labelNames.isEmpty, input)
            XCTAssertNil(r.recurrence, input)
            XCTAssertNil(r.reminderOffsetMinutes, input)
            XCTAssertEqual(r.priority, .p4, input)
        }
    }

    func testASecondPriorityTakesOverFromASwitchedOffFirst() {
        let r = parser.parse("Plan p1 then p2", disabling: [key(.priority, "p1")])
        XCTAssertEqual(r.priority, .p2)
        XCTAssertEqual(r.title, "Plan p1 then")
    }

    func testRangesStayRightAroundWideCharacters() {
        let input = "Café 🎉 tom 9am ☕️ p3"
        let r = parser.parse(input, disabling: [key(.date, "tom")])
        XCTAssertEqual(r.title, "Café 🎉 tom ☕️")
        XCTAssertEqual(r.tokens.map(\.text), ["9am", "p3"])
        assertRangesMatch(r, in: input)
    }

    /// Final review: switching tokens off with session 27's time rules. A bare hour is a time only right
    /// after a date word, so with the date switched off it is plain text again; with the hour switched off
    /// the date stays, all day.
    func testSwitchingOffTheDateOfTom13LeavesThe13AsText() throws {
        let input = "Call mom tom 13"
        XCTAssertEqual(parser.parse(input).tokens.map(\.text), ["tom", "13"])
        let noDate = parser.parse(input, disabling: [key(.date, "tom")])
        XCTAssertEqual(noDate.title, "Call mom tom 13")
        XCTAssertNil(noDate.dueDate)
        XCTAssertFalse(noDate.hasDueTime)
        XCTAssertTrue(noDate.tokens.isEmpty)

        let noTime = parser.parse(input, disabling: [key(.time, "13")])
        XCTAssertEqual(noTime.title, "Call mom 13")
        assertDate(noTime.dueDate, 2026, 10, 22)
        XCTAssertFalse(noTime.hasDueTime)
        XCTAssertEqual(noTime.tokens.map(\.text), ["tom"])
        assertRangesMatch(noTime, in: input)

        // "at 5" is 05:00 whatever is switched off around it; "5pm" is 17:00.
        let at5 = parser.parse("Run tom at 5", disabling: [key(.date, "tom")])
        XCTAssertEqual(at5.title, "Run tom")
        assertDate(at5.dueDate, 2026, 10, 22, 5, 0)
        XCTAssertEqual(parser.parse("Run fri 9 p1", disabling: [key(.priority, "p1")]).title, "Run p1")
        assertDate(parser.parse("Run fri 9 p1", disabling: [key(.priority, "p1")]).dueDate, 2026, 10, 23, 9, 0)
        // A repeat switched off: the time typed after today's is plain today/tomorrow again, not "next".
        let standup = parser.parse("Standup every weekday 9am", disabling: [key(.recurrence, "every weekday")])
        XCTAssertEqual(standup.title, "Standup every weekday")
        XCTAssertNil(standup.recurrence)
        assertDate(standup.dueDate, 2026, 10, 22, 9, 0)
    }

    func testTheKeyIsCodable() throws {
        let keys: Set<QuickAddTokenKey> = [key(.date, "Tom"), key(.project, "#\"Home Repairs\"")]
        let data = try JSONEncoder().encode(keys)
        XCTAssertEqual(try JSONDecoder().decode(Set<QuickAddTokenKey>.self, from: data), keys)
    }
}
