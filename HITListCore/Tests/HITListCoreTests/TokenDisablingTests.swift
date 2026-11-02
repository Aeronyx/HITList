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

    func testTheKeyIsCodable() throws {
        let keys: Set<QuickAddTokenKey> = [key(.date, "Tom"), key(.project, "#\"Home Repairs\"")]
        let data = try JSONEncoder().encode(keys)
        XCTAssertEqual(try JSONDecoder().decode(Set<QuickAddTokenKey>.self, from: data), keys)
    }
}
