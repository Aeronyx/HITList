import XCTest
@testable import HITListCore

final class FilterAutocompleteTests: XCTestCase {
    let projects = ["Work", "Home Repairs", "Client Work", "Finance"]
    let labels = ["waiting", "errand", "email"]

    private func suggest(_ text: String, cursor: Int? = nil) -> [FilterSuggestion] {
        AutocompleteEngine.filterSuggestions(text: text, cursor: cursor, projects: projects, labels: labels)
    }

    func testEmptyQueryOffersStarters() {
        let s = suggest("")
        XCTAssertEqual(s.first?.title, "today")
        XCTAssertTrue(s.contains { $0.title == "#" })
        XCTAssertTrue(s.allSatisfy { $0.range == 0..<0 })
    }

    func testKeywordPrefix() {
        let s = suggest("to")
        XCTAssertEqual(s.map(\.title), ["today", "tomorrow"])
        XCTAssertEqual(s.first?.range, 0..<2)
        let applied = s[0].applied(to: "to")
        XCTAssertEqual(applied.text, "today ")
        XCTAssertEqual(applied.cursor, 6)
    }

    func testKeywordAfterOperator() {
        let s = suggest("p1 & ov")
        XCTAssertEqual(s.map(\.title), ["overdue"])
        XCTAssertEqual(s.first?.range, 5..<7)
        XCTAssertEqual(s.first?.applied(to: "p1 & ov").text, "p1 & overdue ")
    }

    func testMultiWordKeywords() {
        let s = suggest("no ")
        XCTAssertEqual(Set(s.map(\.title)), ["no date", "no time", "no priority", "no project", "no labels"])
        XCTAssertEqual(s.first?.range, 0..<3)
        XCTAssertTrue(suggest("due b").contains { $0.replacement == "due before: " })
        XCTAssertTrue(suggest("next ").contains { $0.title == "next 7 days" })
    }

    func testOperatorsAfterCompleteTerm() {
        XCTAssertEqual(suggest("today ").map(\.replacement), ["& ", "| "])
        XCTAssertEqual(suggest("today").map(\.replacement), [" & ", " | "])
        XCTAssertEqual(suggest("(p1 | p2 ").map(\.title), ["&", "|", ")"])
        XCTAssertEqual(suggest("#Work ").map(\.title), ["&", "|"])
        XCTAssertEqual(suggest("(p1 | p2) & (today | overdue)").map(\.replacement), [" & ", " | "])
        XCTAssertEqual(suggest("(p1 | (p2) ").map(\.title), ["&", "|", ")"])
    }

    func testProjects() {
        let s = suggest("p1 & #w")
        XCTAssertEqual(s.map(\.title), ["#Work", "#Client Work"]) // prefix beats substring
        XCTAssertEqual(s[1].replacement, "#\"Client Work\" ")
        XCTAssertEqual(s[0].range, 5..<7)
        XCTAssertTrue(suggest("#").contains { $0.title == "#Inbox" })
        XCTAssertEqual(suggest("##Fin").first?.replacement, "##Finance ")
    }

    func testQuotedProjectName() {
        let s = suggest("#\"Home R")
        XCTAssertEqual(s.map(\.title), ["#Home Repairs"])
        XCTAssertEqual(s.first?.range, 0..<8)
        XCTAssertEqual(s.first?.applied(to: "#\"Home R").text, "#\"Home Repairs\" ")
    }

    func testLabelsKeepTheirSigil() {
        XCTAssertEqual(suggest("@e").map(\.replacement), ["@email ", "@errand "])
        XCTAssertEqual(suggest("%wa").map(\.replacement), ["%waiting "])
        XCTAssertTrue(suggest("@waiting").isEmpty) // fully typed
    }

    func testDatePhrasesAfterField() {
        let s = suggest("due before: ")
        XCTAssertEqual(s.first?.title, "today")
        XCTAssertEqual(s.first?.range, 12..<12)
        let ne = suggest("p1 & due after: ne")
        XCTAssertEqual(ne.map(\.title), ["next week", "next month", "next weekend"])
        XCTAssertEqual(ne.first?.range, 16..<18)
        XCTAssertEqual(suggest("created: -").map(\.title), ["-7 days", "-30 days"])
        XCTAssertEqual(suggest("due: tomorrow ").map(\.title), ["&", "|"])
    }

    func testNothingInsideSearchText() {
        XCTAssertTrue(suggest("search: gro").isEmpty)
        XCTAssertTrue(suggest("\"some text").isEmpty)
    }

    func testCursorInTheMiddle() {
        let text = "to & p1"
        let s = suggest(text, cursor: 2)
        XCTAssertEqual(s.first?.range, 0..<2)
        XCTAssertEqual(s.first?.applied(to: text).text, "today  & p1")
    }

    func testTypoFix() {
        let s = suggest("p1 & tomorow")
        XCTAssertEqual(s.map(\.title), ["tomorrow"])
        XCTAssertEqual(s.first?.range, 5..<12)
    }

    func testLimit() {
        XCTAssertEqual(AutocompleteEngine.filterSuggestions(text: "", projects: [], labels: [], limit: 3).count, 3)
    }
}
