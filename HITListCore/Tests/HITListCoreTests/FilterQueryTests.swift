import XCTest
@testable import HITListCore

final class FilterQueryTests: XCTestCase {
    // Today: Wed 2026-10-21 14:30
    let tasks: [PlainTask] = [
        PlainTask(title: "Overdue p1", priority: 1, dueDate: Fixed.date(2026, 10, 19), projectName: "Work", labelNames: ["urgent"]),
        PlainTask(title: "Earlier today timed", priority: 3, dueDate: Fixed.date(2026, 10, 21, 9), hasDueTime: true, projectName: "Work"),
        PlainTask(title: "Later today timed", priority: 2, dueDate: Fixed.date(2026, 10, 21, 18), hasDueTime: true, projectName: "Home"),
        PlainTask(title: "Today no time", priority: 4, dueDate: Fixed.date(2026, 10, 21)),
        PlainTask(title: "Tomorrow", priority: 2, dueDate: Fixed.date(2026, 10, 22), projectName: "Home", labelNames: ["errand", "waiting"]),
        PlainTask(title: "Saturday", priority: 4, dueDate: Fixed.date(2026, 10, 24), projectName: "Home Repairs"),
        PlainTask(title: "Next Tuesday", priority: 1, dueDate: Fixed.date(2026, 10, 27), projectName: "Work"),
        PlainTask(title: "Next month dentist", notes: "Dr. Smith", priority: 3, dueDate: Fixed.date(2026, 11, 10), labelNames: ["health"]),
        PlainTask(title: "Someday", priority: 4, projectName: "Work"),
        PlainTask(title: "Done yesterday", priority: 1, dueDate: Fixed.date(2026, 10, 20), isCompleted: true, projectName: "Work"),
        PlainTask(title: "Water plants", priority: 4, dueDate: Fixed.date(2026, 10, 21), isRecurring: true),
    ]

    func titles(_ query: String, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        do {
            let q = try FilterQuery(query, calendar: Fixed.calendar, now: Fixed.now)
            return q.apply(to: tasks, now: Fixed.now, calendar: Fixed.calendar).map(\.filterTitle)
        } catch {
            XCTFail("\(query): \(error)", file: file, line: line)
            return []
        }
    }

    func testPriority() {
        XCTAssertEqual(Set(titles("p1")), ["Overdue p1", "Next Tuesday"])
        XCTAssertEqual(Set(titles("priority <= 2")), ["Overdue p1", "Later today timed", "Tomorrow", "Next Tuesday"])
        XCTAssertEqual(Set(titles("priority > 3")), ["Today no time", "Saturday", "Someday", "Water plants"])
        XCTAssertEqual(Set(titles("no priority")), ["Today no time", "Saturday", "Someday", "Water plants"])
        XCTAssertEqual(Set(titles("priority != 4 & !p1")), ["Earlier today timed", "Later today timed", "Tomorrow", "Next month dentist"])
    }

    func testDateKeywords() {
        XCTAssertEqual(Set(titles("today")), ["Earlier today timed", "Later today timed", "Today no time", "Water plants"])
        XCTAssertEqual(Set(titles("tomorrow")), ["Tomorrow"])
        XCTAssertEqual(Set(titles("overdue")), ["Overdue p1", "Earlier today timed"])
        XCTAssertEqual(Set(titles("no date")), ["Someday"])
        XCTAssertEqual(Set(titles("has time")), ["Earlier today timed", "Later today timed"])
        XCTAssertEqual(Set(titles("today & no time")), ["Today no time", "Water plants"])
        XCTAssertEqual(Set(titles("weekend")), ["Saturday"])
        XCTAssertEqual(Set(titles("next 7 days")), ["Earlier today timed", "Later today timed", "Today no time", "Tomorrow", "Saturday", "Next Tuesday", "Water plants"])
        XCTAssertEqual(Set(titles("3 days")), ["Earlier today timed", "Later today timed", "Today no time", "Tomorrow", "Saturday", "Water plants"])
        XCTAssertEqual(Set(titles("this week")), ["Overdue p1", "Earlier today timed", "Later today timed", "Today no time", "Tomorrow", "Saturday", "Water plants"])
        XCTAssertEqual(Set(titles("next week")), ["Next Tuesday"])
        XCTAssertEqual(Set(titles("next month")), ["Next month dentist"])
        XCTAssertEqual(Set(titles("this month & p1")), ["Overdue p1", "Next Tuesday"])
    }

    func testDueExpressions() {
        XCTAssertEqual(Set(titles("due: next tue")), ["Next Tuesday"])
        XCTAssertEqual(Set(titles("due: 2026-11-10")), ["Next month dentist"])
        XCTAssertEqual(Set(titles("due: sat")), ["Saturday"])
        XCTAssertEqual(Set(titles("due before: tomorrow")), ["Overdue p1", "Earlier today timed", "Later today timed", "Today no time", "Water plants"])
        XCTAssertEqual(Set(titles("due after: sat")), ["Next Tuesday", "Next month dentist"])
        XCTAssertEqual(Set(titles("due after: today & due before: next week")), ["Tomorrow", "Saturday"])
    }

    func testProjectsLabelsSearch() {
        XCTAssertEqual(Set(titles("#Work")), ["Overdue p1", "Earlier today timed", "Next Tuesday", "Someday"])
        XCTAssertEqual(Set(titles("#work")), ["Overdue p1", "Earlier today timed", "Next Tuesday", "Someday"])
        XCTAssertEqual(Set(titles("#\"Home Repairs\"")), ["Saturday"])
        XCTAssertEqual(Set(titles("@waiting")), ["Tomorrow"])
        XCTAssertEqual(Set(titles("no project")), ["Today no time", "Next month dentist", "Water plants"])
        XCTAssertEqual(Set(titles("no labels & #Home")), ["Later today timed"])
        XCTAssertEqual(Set(titles("search: dentist")), ["Next month dentist"])
        XCTAssertEqual(Set(titles("search: dr. smith")), ["Next month dentist"])
        XCTAssertEqual(Set(titles("\"today\"")), ["Earlier today timed", "Later today timed", "Today no time"])
        XCTAssertEqual(Set(titles("recurring")), ["Water plants"])
    }

    func testBooleanLogicAndPrecedence() {
        // & binds tighter than |
        XCTAssertEqual(Set(titles("p1 | p2 & #Home")), ["Overdue p1", "Next Tuesday", "Later today timed", "Tomorrow"])
        XCTAssertEqual(Set(titles("(p1 | p2) & #Home")), ["Later today timed", "Tomorrow"])
        XCTAssertEqual(Set(titles("(p1 | p2) & next 7 days & !@waiting")), ["Later today timed", "Next Tuesday"])
        XCTAssertEqual(Set(titles("overdue | today")), ["Overdue p1", "Earlier today timed", "Later today timed", "Today no time", "Water plants"])
        XCTAssertEqual(Set(titles("!(today | tomorrow) & has date")), ["Overdue p1", "Saturday", "Next Tuesday", "Next month dentist"])
        XCTAssertEqual(Set(titles("p1, #Work")), ["Overdue p1", "Next Tuesday"])
        XCTAssertEqual(titles("all").count, 10)
    }

    func testCompletedHandling() {
        XCTAssertFalse(titles("all").contains("Done yesterday"))
        XCTAssertEqual(Set(titles("completed")), ["Done yesterday"])
        XCTAssertEqual(Set(titles("completed & #Work")), ["Done yesterday"])
        XCTAssertEqual(titles("!completed").count, 10)
        XCTAssertEqual(titles("completed | all").count, 11)
    }

    func testSorting() {
        let result = titles("all")
        XCTAssertEqual(result.first, "Overdue p1")
        XCTAssertEqual(result.last, "Someday") // undated last
        // Same day: timed tasks are ordered by time; untimed at day start come first.
        XCTAssertEqual(Array(result[1...4]), ["Today no time", "Water plants", "Earlier today timed", "Later today timed"])
    }

    func testErrors() {
        func err(_ q: String) -> FilterQueryError? {
            do { _ = try FilterQuery(q, calendar: Fixed.calendar, now: Fixed.now); return nil }
            catch let e as FilterQueryError { return e } catch { return nil }
        }
        XCTAssertEqual(err("")?.message, "Filter is empty")
        XCTAssertEqual(err("(p1 | p2")?.message, "Missing ')'")
        XCTAssertEqual(err("banana")?.message, "Unknown term 'banana'")
        XCTAssertEqual(err("banana")?.position, 0)
        XCTAssertEqual(err("p1 & banana")?.position, 5)
        XCTAssertEqual(err("due: purple")?.message, "Can't understand the date \"purple\"")
        XCTAssertEqual(err("\"unterminated")?.message, "Missing closing quote")
        XCTAssertEqual(err("p1 p2")?.message, "Unexpected 'p2'")
        XCTAssertEqual(err("priority 9")?.message, "Expected a priority 1-4 after 'priority'")
        XCTAssertNil(FilterQuery.validate("overdue | today"))
        XCTAssertNotNil(FilterQuery.validate("#"))
    }

    func testSavedFilterIsReEvaluatedAcrossDays() throws {
        let q = try FilterQuery("today", calendar: Fixed.calendar, now: Fixed.now)
        let tomorrowNow = Fixed.date(2026, 10, 22, 8)
        let names = q.apply(to: tasks, now: tomorrowNow, calendar: Fixed.calendar).map(\.filterTitle)
        XCTAssertEqual(names, ["Tomorrow"])
    }
}
