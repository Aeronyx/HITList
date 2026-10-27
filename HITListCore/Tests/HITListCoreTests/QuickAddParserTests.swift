import XCTest
@testable import HITListCore

final class QuickAddParserTests: XCTestCase {
    let parser = QuickAddParser(now: Fixed.now, calendar: Fixed.calendar,
                                knownProjects: ["Finance", "Home Repairs", "Work"],
                                knownLabels: ["bills", "errand"])

    func testFullExample() {
        let r = parser.parse("Pay rent tomorrow 5pm p1 #Finance @bills every month")
        XCTAssertEqual(r.title, "Pay rent")
        assertDate(r.dueDate, 2026, 10, 22, 17, 0)
        XCTAssertTrue(r.hasDueTime)
        XCTAssertEqual(r.priority, .p1)
        XCTAssertEqual(r.projectName, "Finance")
        XCTAssertEqual(r.labelNames, ["bills"])
        XCTAssertEqual(r.recurrence, .monthly)
        XCTAssertEqual(r.tokens.map(\.kind), [.date, .time, .priority, .project, .label, .recurrence])
        XCTAssertEqual(r.tokens.map(\.text), ["tomorrow", "5pm", "p1", "#Finance", "@bills", "every month"])
    }

    func testPlainTitle() {
        let r = parser.parse("Call mom")
        XCTAssertEqual(r.title, "Call mom")
        XCTAssertNil(r.dueDate)
        XCTAssertEqual(r.priority, .p4)
        XCTAssertNil(r.projectName)
        XCTAssertTrue(r.labelNames.isEmpty)
        XCTAssertTrue(r.tokens.isEmpty)
    }

    func testDateInMiddleOfTitle() {
        let r = parser.parse("Submit report fri at 9 for the board")
        XCTAssertEqual(r.title, "Submit report for the board")
        assertDate(r.dueDate, 2026, 10, 23, 9, 0)
        XCTAssertTrue(r.hasDueTime)
    }

    func testProjectCanonicalCasingAndMultiWord() {
        XCTAssertEqual(parser.parse("Fix sink #finance").projectName, "Finance")
        let r = parser.parse("Fix sink #home repairs tomorrow")
        XCTAssertEqual(r.projectName, "Home Repairs")
        XCTAssertEqual(r.title, "Fix sink")
        assertDate(r.dueDate, 2026, 10, 22)
        let q = parser.parse("Fix sink #\"Home Repairs\"")
        XCTAssertEqual(q.projectName, "Home Repairs")
        XCTAssertEqual(q.title, "Fix sink")
        // Unknown project names pass through so the app can offer to create them.
        XCTAssertEqual(parser.parse("Plan trip #Travel").projectName, "Travel")
    }

    func testLabels() {
        let r = parser.parse("Buy stamps @errand @Errand @post")
        XCTAssertEqual(r.labelNames, ["errand", "post"])
        XCTAssertEqual(r.title, "Buy stamps")
    }

    func testPriorityForms() {
        XCTAssertEqual(parser.parse("x p2").priority, .p2)
        XCTAssertEqual(parser.parse("x !!3").priority, .p3)
        XCTAssertEqual(parser.parse("x P1").priority, .p1)
        XCTAssertEqual(parser.parse("x p5").priority, .p4)
        XCTAssertEqual(parser.parse("x p5").title, "x p5")
    }

    func testRecurrenceForms() {
        XCTAssertEqual(parser.parse("Gym every mon, wed and fri").recurrence, RecurrenceRule(frequency: .weekly, weekdays: [2, 4, 6]))
        XCTAssertEqual(parser.parse("Gym every mon, wed and fri").title, "Gym")
        XCTAssertEqual(parser.parse("Standup every weekday 9am").recurrence, .weekdays)
        XCTAssertEqual(parser.parse("Water plants every 3 days").recurrence, RecurrenceRule(frequency: .daily, interval: 3))
        XCTAssertEqual(parser.parse("Trash every other week").recurrence, RecurrenceRule(frequency: .weekly, interval: 2))
        XCTAssertEqual(parser.parse("Review daily").recurrence, .daily)
        XCTAssertEqual(parser.parse("Taxes yearly").recurrence, .yearly)
        // "every" with nothing recognizable stays in the title.
        XCTAssertNil(parser.parse("Thank every volunteer").recurrence)
        XCTAssertEqual(parser.parse("Thank every volunteer").title, "Thank every volunteer")
    }

    func testRecurrenceStartDate() {
        // Today is Wednesday. "every monday" with no explicit date starts next Monday.
        assertDate(parser.parse("Gym every monday").dueDate, 2026, 10, 26)
        // "every day" starts today.
        assertDate(parser.parse("Journal every day").dueDate, 2026, 10, 21)
        // Explicit date wins.
        assertDate(parser.parse("Journal every day starting jan 5").dueDate, 2027, 1, 5)
        assertDate(parser.parse("Standup every weekday 9am").dueDate, 2026, 10, 21, 9, 0)
    }

    func testTimeOnlyRollsToTomorrowWhenPassed() {
        assertDate(parser.parse("Call bank 9am").dueDate, 2026, 10, 22, 9, 0)
        assertDate(parser.parse("Call bank 4pm").dueDate, 2026, 10, 21, 16, 0)
    }

    func testNumbersInTitleAreNotDates() {
        let r = parser.parse("Read 5 pages of chapter 12")
        XCTAssertEqual(r.title, "Read 5 pages of chapter 12")
        XCTAssertNil(r.dueDate)
    }

    func testQuotedTitleTextIsPreserved() {
        let r = parser.parse("Email \"tomorrow\" agenda today")
        XCTAssertEqual(r.title, "Email tomorrow agenda")
        assertDate(r.dueDate, 2026, 10, 21)
    }

    func testTokenRangesCoverOriginalText() {
        let input = "Pay rent tomorrow 5pm p1 #Finance"
        let r = parser.parse(input)
        for token in r.tokens {
            XCTAssertEqual(String(input[token.range]), token.text)
        }
    }
}
