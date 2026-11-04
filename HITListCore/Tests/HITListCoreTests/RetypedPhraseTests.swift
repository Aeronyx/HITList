import XCTest
@testable import HITListCore

/// Brief 41 (George, 0.5.0): "if I type 'tom 3' and then click it to remove it, but then delete it fully and
/// type it again, it should still get highlighted." A switched-off phrase is known by its place in the text:
/// it is forgotten once its words are edited or deleted, and another copy typed elsewhere is highlighted.
final class RetypedPhraseTests: XCTestCase {
    let parser = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar, knownProjects: ["Home Repairs", "Work"])

    private func phrases(_ text: String, _ words: String...) -> Set<QuickAddDisabledPhrase> {
        Set(parser.parse(text).tokens.filter { words.contains($0.text) }.compactMap { QuickAddDisabledPhrase($0, in: text) })
    }

    /// Types `new` one change at a time from `old`, carrying the phrases along as the draft does.
    private func edit(_ phrases: Set<QuickAddDisabledPhrase>, _ steps: [String]) -> Set<QuickAddDisabledPhrase> {
        var current = phrases
        for (old, new) in zip(steps, steps.dropFirst()) { current = QuickAddDisabledPhrase.carried(current, from: old, to: new) }
        return current
    }

    func testOnlyTheSwitchedOffCopyStaysPlain() {
        let off = phrases("Call tom", "tom")
        let r = parser.parse("Call tom then tom", switchedOff: off)
        XCTAssertEqual(r.tokens.map(\.text), ["tom"])
        XCTAssertEqual(r.tokens.first?.range.lowerBound, "Call tom then tom".range(of: "tom", options: .backwards)?.lowerBound)
        XCTAssertEqual(r.title, "Call tom then")
        assertDate(r.dueDate, 2026, 10, 22)
    }

    func testDeletingThePhraseAndTypingItAgainHighlightsIt() {
        let off = phrases("Call tom 3", "tom", "3")
        XCTAssertTrue(parser.parse("Call tom 3", switchedOff: off).tokens.isEmpty)
        // Backspace to "Call ", then type "tom 3" again.
        let steps = ["Call tom 3", "Call tom ", "Call tom", "Call to", "Call t", "Call ", "Call t", "Call to", "Call tom",
                     "Call tom ", "Call tom 3"]
        let after = edit(off, steps)
        XCTAssertTrue(after.isEmpty, "both words were deleted: nothing is remembered")
        XCTAssertEqual(parser.parse("Call tom 3", switchedOff: after).tokens.map(\.text), ["tom", "3"])
    }

    func testEditingElsewhereKeepsItPlain() {
        let off = phrases("Call tom 3", "tom", "3")
        let after = edit(off, ["Call tom 3", "Calll tom 3", "Ring tom 3", "Ring tom 3 about", "Ring tom 3 about it p1"])
        XCTAssertEqual(after.count, 2)
        let r = parser.parse("Ring tom 3 about it p1", switchedOff: after)
        XCTAssertEqual(r.tokens.map(\.text), ["p1"])
        XCTAssertEqual(r.title, "Ring tom 3 about it")
        XCTAssertNil(r.dueDate)
    }

    func testTypingTheWordAgainLaterHighlightsOnlyTheNewOne() {
        let off = phrases("Call tom", "tom")
        let after = edit(off, ["Call tom", "Call tom ", "Call tom o", "Call tom or", "Call tom or ", "Call tom or t",
                               "Call tom or to", "Call tom or tom"])
        XCTAssertEqual(after, off, "the first tom has not moved")
        let r = parser.parse("Call tom or tom", switchedOff: after)
        XCTAssertEqual(r.tokens.map(\.text), ["tom"])
        XCTAssertEqual(r.title, "Call tom or")
    }

    func testTypingBeforeItMovesItAlong() {
        let off = phrases("tom", "tom")
        let after = edit(off, ["tom", "a tom", "Call a tom"])
        XCTAssertEqual(after.first?.start, 7)
        XCTAssertEqual(parser.parse("Call a tom", switchedOff: after).title, "Call a tom")
    }

    func testChangingAWordOfThePhraseForgetsIt() {
        let off = phrases("Plan next friday", "next friday")
        XCTAssertTrue(edit(off, ["Plan next friday", "Plan nex friday", "Plan next friday"]).isEmpty,
                      "a letter deleted inside it and typed back: it is a new phrase")
        XCTAssertTrue(edit(off, ["Plan next friday", ""]).isEmpty, "all the text deleted")
    }

    func testAPhraseIsCodable() throws {
        let off = phrases("Call tom 3 #\"Home Repairs\"", "tom", "#\"Home Repairs\"")
        let data = try JSONEncoder().encode(off)
        XCTAssertEqual(try JSONDecoder().decode(Set<QuickAddDisabledPhrase>.self, from: data), off)
    }
}
