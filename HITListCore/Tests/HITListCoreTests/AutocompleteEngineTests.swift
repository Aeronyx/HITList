import XCTest
@testable import HITListCore

final class AutocompleteEngineTests: XCTestCase {
    let engine = AutocompleteEngine(
        tasks: [
            PlainTask(title: "Buy milk", priority: 4, projectName: "Groceries", labelNames: ["errand"]),
            PlainTask(title: "Buy milk", priority: 4, isCompleted: true, projectName: "Groceries", labelNames: ["errand"]),
            PlainTask(title: "Buy eggs", priority: 4, projectName: "Groceries", labelNames: ["errand"]),
            PlainTask(title: "Pay rent", priority: 1, projectName: "Finance", labelNames: ["bills"]),
            PlainTask(title: "Pay electric bill", priority: 2, projectName: "Finance", labelNames: ["bills"]),
            PlainTask(title: "Call plumber", priority: 2, projectName: "Home Repairs"),
        ],
        projects: ["Groceries", "Finance", "Home Repairs", "Work"],
        labels: ["errand", "bills", "waiting"]
    )

    func testProjectSuggestions() {
        let s = engine.suggestions(for: "Fix sink #h")
        XCTAssertEqual(s.map(\.text), ["Home Repairs"])
        XCTAssertEqual(s.first?.replacement, "#\"Home Repairs\"")
        XCTAssertEqual(engine.suggestions(for: "x #").map(\.text), ["Finance", "Groceries", "Home Repairs", "Work"])
        XCTAssertEqual(engine.suggestions(for: "x #ance").map(\.text), ["Finance"]) // substring match
    }

    func testLabelSuggestions() {
        XCTAssertEqual(engine.suggestions(for: "x @w").map(\.replacement), ["@waiting"])
        XCTAssertEqual(engine.suggestions(for: "x @").count, 3)
    }

    func testTitleSuggestions() {
        let s = engine.suggestions(for: "Buy m")
        XCTAssertEqual(s.first?.kind, .title)
        XCTAssertEqual(s.first?.text, "Buy milk")
        let both = engine.suggestions(for: "Buy")
        XCTAssertEqual(Set(both.map(\.text)), ["Buy milk", "Buy eggs"])
        // Frequency wins: "Buy milk" appeared twice.
        XCTAssertEqual(both.first?.text, "Buy milk")
        // Exactly-typed title is not re-suggested.
        XCTAssertFalse(engine.suggestions(for: "Buy milk").contains { $0.text == "Buy milk" })
    }

    func testKeywordSuggestions() {
        XCTAssertEqual(engine.suggestions(for: "Call mom tom").map(\.text), ["tomorrow"])
        XCTAssertTrue(engine.suggestions(for: "Call mom ev").map(\.text).contains("every day"))
        XCTAssertTrue(engine.suggestions(for: "Call mom t").isEmpty) // needs 2+ chars
    }

    func testAttributeAutofill() {
        let milk = engine.attributeSuggestion(forTitle: "Buy milk")
        XCTAssertEqual(milk?.projectName, "Groceries")
        XCTAssertEqual(milk?.labelNames, ["errand"])
        XCTAssertNil(milk?.priority)

        let rent = engine.attributeSuggestion(forTitle: "Pay the rent")
        XCTAssertEqual(rent?.projectName, "Finance")
        XCTAssertEqual(rent?.labelNames, ["bills"])
        // "pay" votes p1 once and p2 once, "rent" votes p1 once → p1 has 2 of 3 votes.
        XCTAssertEqual(rent?.priority, .p1)

        // Only one supporting task and no exact title → not enough evidence.
        XCTAssertNil(engine.attributeSuggestion(forTitle: "Call someone"))
        // Exact prior title with a single occurrence is enough.
        XCTAssertEqual(engine.attributeSuggestion(forTitle: "Call plumber")?.projectName, "Home Repairs")
        XCTAssertNil(engine.attributeSuggestion(forTitle: "Nothing matches here"))
        XCTAssertNil(engine.attributeSuggestion(forTitle: "a to"))
    }
}
