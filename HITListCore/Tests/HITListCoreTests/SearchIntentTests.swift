import XCTest
@testable import HITListCore

/// Brief 61: Browse's search field takes the filter language. Text that reads as a query filters; anything
/// else searches titles and notes, as before.
final class SearchIntentTests: XCTestCase {
    private func intent(_ text: String) -> SearchIntent {
        SearchIntent(text, calendar: Fixed.calendar, now: Fixed.now)
    }

    func testTheBriefsExamplesAreQueries() {
        for text in ["#Work", "@waiting & p1", "no date", "overdue"] {
            XCTAssertEqual(intent(text), .query(text), text)
        }
    }

    func testOtherQueriesWithTheLanguagesMarks() {
        for text in ["!#Work", "today | overdue", "(p1 | p2) & 7 days", "due before: friday", "priority <= 2",
                     "#\"Home Repairs\"", "search: send email", "\"dentist\"", "%errands", "today, p1"] {
            XCTAssertEqual(intent(text), .query(text), text)
        }
    }

    func testWholeKeywordsAreQueries() {
        for text in ["today", "Overdue", "P1", "friday", "7 days", "next 7 days", "this week", "no labels",
                     "recurring", "completed", "has time", "october"] {
            XCTAssertEqual(intent(text), .query(text), text)
        }
    }

    func testPlainWordsSearchTitlesAndNotes() {
        for text in ["milk", "call mom", "Dentist appointment", "Call mom!", "Buy 7 eggs"] {
            XCTAssertEqual(intent(text), .text(text), text)
        }
    }

    func testShortFormsAndLoneNumbersSearchToo() {
        // The parser reads these as dates, but in a search field they are a name or a number.
        for text in ["tom", "Tom", "tod", "mon", "jan 3", "7", "2026", "all", "allergy"] {
            XCTAssertEqual(intent(text), .text(text), text)
        }
    }

    func testTextIsTrimmedAndBlankIsEmpty() {
        XCTAssertEqual(intent("   "), .empty)
        XCTAssertEqual(intent(""), .empty)
        XCTAssertEqual(intent("  #Work \n"), .query("#Work"))
        XCTAssertEqual(intent("  milk "), .text("milk"))
    }

    func testAnUnfinishedQuerySearchesTextAndSaysWhatIsMissing() {
        guard case .text(let text, let problem?) = intent("@waiting &") else {
            return XCTFail("an unfinished query is text, with the parser's message")
        }
        XCTAssertEqual(text, "@waiting &")
        XCTAssertFalse(problem.isEmpty)
        XCTAssertEqual(intent("#").query, nil)
        guard case .text(_, let none) = intent("milk") else { return XCTFail() }
        XCTAssertNil(none, "plain words have nothing missing")
    }

    func testTheQueryFiltersAsASavedFilterDoes() throws {
        let tasks = [
            PlainTask(title: "ship it", priority: 1, dueDate: Fixed.date(2026, 10, 22), projectName: "Work"),
            PlainTask(title: "sweep", dueDate: Fixed.date(2026, 10, 20), projectName: "Home"),
            PlainTask(title: "Work out", priority: 2),
        ]
        let source = try XCTUnwrap(intent("#Work").query)
        let matched = try FilterQuery(source, calendar: Fixed.calendar, now: Fixed.now)
            .apply(to: tasks, now: Fixed.now, calendar: Fixed.calendar)
        XCTAssertEqual(matched.map(\.filterTitle), ["ship it"], "the Group, not the word in a title")
    }
}
