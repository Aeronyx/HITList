import XCTest
@testable import HITListCore

/// Brief 137: Todoist's words into what HITList holds, with a count of every choice made. The clock is `Fixed`:
/// Wednesday 2026-10-21 14:30 UTC.
final class TodoistMappingTests: XCTestCase {
    var reader: TodoistDateReader { TodoistDateReader(now: Fixed.now, calendar: Fixed.calendar) }

    // MARK: Dates and repeats

    func testDatesHITListAlreadyReads() throws {
        let day = try XCTUnwrap(reader.read("Nov 20"))
        assertDate(day.due, 2026, 11, 20)
        XCTAssertFalse(day.hasTime)
        XCTAssertNil(day.recurrence)
        let timed = try XCTUnwrap(reader.read("Nov 20 2:30 PM"))
        assertDate(timed.due, 2026, 11, 20, 14, 30)
        XCTAssertTrue(timed.hasTime)
        assertDate(reader.read("20 Nov 2027")?.due, 2027, 11, 20)
        assertDate(reader.read("2026-11-20")?.due, 2026, 11, 20)
        XCTAssertEqual(reader.read("every weekday")?.recurrence, .weekdays)
        XCTAssertEqual(reader.read("every 2 weeks")?.recurrence, RecurrenceRule(frequency: .weekly, interval: 2))
        let list = try XCTUnwrap(reader.read("every mon, wed at 9am"))
        XCTAssertEqual(list.recurrence?.weekdays, [2, 4])
        XCTAssertTrue(list.hasTime)
        XCTAssertEqual(reader.read("every 15th")?.recurrence?.frequency, .monthly)
        XCTAssertEqual(reader.read("every last day")?.recurrence?.frequency, .monthly)
    }

    func testWhatTodoistWritesThatQuickAddDoesNot() throws {
        XCTAssertEqual(reader.read("ev week")?.recurrence, .weekly)
        let fromDone = try XCTUnwrap(reader.read("every! 3 days"))
        XCTAssertEqual(fromDone.recurrence, RecurrenceRule(frequency: .daily, interval: 3))
        XCTAssertEqual(fromDone.notes, ["Todoist repeated it from the day it was completed (every! 3 days)."])
        XCTAssertEqual(reader.read("after 2 weeks")?.recurrence, RecurrenceRule(frequency: .weekly, interval: 2))
        let until = try XCTUnwrap(reader.read("every day until Dec 31"))
        XCTAssertEqual(until.recurrence, .daily)
        XCTAssertEqual(until.notes, ["Todoist stopped the repeat: until Dec 31."])
        let starting = try XCTUnwrap(reader.read("every day starting Nov 1"))
        assertDate(starting.due, 2026, 11, 1)
        let iso = try XCTUnwrap(reader.read("2026-11-20 14:00"))
        assertDate(iso.due, 2026, 11, 20, 14)
        XCTAssertTrue(iso.hasTime)
    }

    func testADayWithoutAYearIsTheNextSuchDayUnlessJustPast() {
        assertDate(reader.read("Oct 10")?.due, 2026, 10, 10, "eleven days past: overdue, as Todoist showed it")
        assertDate(reader.read("Jun 3")?.due, 2027, 6, 3, "months past: next year's")
    }

    func testATimedDateIsReadInItsOwnTimeZone() {
        assertDate(reader.read("Nov 20 2pm", timeZone: "US/Eastern")?.due, 2026, 11, 20, 19)
        assertDate(reader.read("Nov 20", timeZone: "US/Eastern")?.due, 2026, 11, 20, "a day without a time stays the day")
    }

    func testWordsItCannotReadAreRefused() {
        XCTAssertNil(reader.read("every hour"))
        XCTAssertNil(reader.read("jeden Tag", language: "de"), "another language is kept as text")
        XCTAssertNil(reader.read("someday maybe"))
        XCTAssertNil(reader.read(""))
    }

    // MARK: The mapping

    static let csv = """
    TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,AUTHOR,RESPONSIBLE,DATE,DATE_LANG,TIMEZONE,DURATION,DURATION_UNIT,DEADLINE,DEADLINE_LANG
    task,Pay rent @home @bills,Due on the first,1,1,G (1),,every month,en,,,None,,
    note,Landlord prefers Zelle,,,,G (1),,,,,,,,
    task,* Big picture,,4,1,G (1),,,,,,,,
    section,Errands,,,,,,,,,,,,
    task,Groceries,,4,1,G (1),,Nov 20,en,,,None,Nov 25,en
    task,Bread,,4,2,G (1),,,,,,,,
    task,Sourdough,Ask for a starter,4,3,G (1),,,,,,,,
    task,Pick up dry cleaning,,4,2,G (1),,Nov 21,en,,,None,,
    task,Return library books,,3,1,G (1),Sam (2),someday-ish,en,,45,minute,,
    """

    func plan(existing: TodoistExisting = TodoistExisting(), options: TodoistImportOptions = TodoistImportOptions(),
              projects: [TodoistProject]? = nil) throws -> TodoistPlan {
        let project = try TodoistReader.read(csv: Self.csv, fileName: "Home [123].csv")
        return TodoistMapping.plan(projects ?? [project], existing: existing, options: options, dates: reader)
    }

    func testTasksLabelsPrioritiesNotesAndDates() throws {
        let plan = try plan()
        XCTAssertEqual(plan.tasks.map(\.title), ["Pay rent", "Big picture", "Groceries", "Pick up dry cleaning", "Return library books"])
        let rent = plan.tasks[0]
        XCTAssertEqual(rent.groupName, "Home")
        XCTAssertEqual(rent.labels, ["home", "bills"])
        XCTAssertEqual(rent.priority, .p1)
        XCTAssertEqual(rent.recurrence?.frequency, .monthly)
        XCTAssertEqual(rent.notes, "Due on the first\nLandlord prefers Zelle")

        let groceries = plan.tasks[2]
        XCTAssertEqual(groceries.labels, ["Errands"], "a section is a label")
        assertDate(groceries.due, 2026, 11, 20)
        assertDate(groceries.deadline, 2026, 11, 25)
        XCTAssertEqual(groceries.checklist, ["Bread", "Bread › Sourdough"])
        XCTAssertEqual(groceries.notes, "Bread › Sourdough: Ask for a starter")
        XCTAssertEqual(groceries.priority, .p4)

        let cleaning = plan.tasks[3]
        XCTAssertEqual(cleaning.notes, "Under: Groceries", "a sub-task with a date of its own is a task")
        XCTAssertEqual(cleaning.labels, ["Errands"])

        let books = plan.tasks[4]
        XCTAssertNil(books.due)
        XCTAssertEqual(books.priority, .p3)
        XCTAssertEqual(books.unreadDate, "someday-ish")
        XCTAssertEqual(books.notes, "Todoist date: someday-ish\nDuration in Todoist: 45 minutes\nAssigned in Todoist to Sam")
    }

    func testHeadingsAreLabelLessWithTheStarRemoved() throws {
        let heading = try plan().tasks[1]
        XCTAssertEqual(heading.title, "Big picture")
        XCTAssertEqual(heading.labels, [])
        XCTAssertEqual(heading.notes, "Heading in Todoist")
    }

    func testCounts() throws {
        let plan = try plan()
        XCTAssertEqual(plan.taskCount, 5)
        XCTAssertEqual(plan.checklistLineCount, 2)
        XCTAssertEqual(plan.subtasksAsTasks, 1)
        XCTAssertEqual(plan.repeatingCount, 1)
        XCTAssertEqual(plan.headingCount, 1)
        XCTAssertEqual(plan.unreadDates.map(\.title), ["Return library books"])
        XCTAssertEqual(plan.labelsToMake, ["home", "bills", "Errands"])
        XCTAssertEqual(plan.projects, [TodoistPlan.ProjectLine(name: "Home", destination: .newGroup("Home"), taskCount: 5)])
        XCTAssertFalse(plan.choices.isEmpty)
    }

    func testExistingGroupsLabelsAndTasksAreUsedAndNothingDoubles() throws {
        let existing = TodoistExisting(groupNames: ["home"], labelNames: ["Bills"],
                                       openTasks: [.init(title: "pay rent", groupName: "HOME")])
        let plan = try plan(existing: existing)
        XCTAssertEqual(plan.projects.first?.destination, .existingGroup("home"))
        XCTAssertEqual(plan.tasks.first?.groupName, "home")
        XCTAssertEqual(plan.skipped.map(\.title), ["Pay rent"])
        XCTAssertEqual(plan.taskCount, 4)
        XCTAssertEqual(plan.labelsToMake, ["Errands"], "home goes with Pay rent; Bills is there")
    }

    func testSectionsOffKeepsTheSectionInTheNotes() throws {
        let plan = try plan(options: TodoistImportOptions(sectionsAsLabels: false))
        XCTAssertEqual(plan.tasks[2].labels, [])
        XCTAssertTrue(plan.tasks[2].notes.hasSuffix("Section in Todoist: Errands"))
    }

    func testTodoistsInboxGoesToTheInbox() throws {
        let inbox = try TodoistReader.read(csv: "TYPE,CONTENT,PRIORITY\ntask,Call mum,4\n", fileName: "Inbox [1].csv")
        let plan = try plan(projects: [inbox])
        XCTAssertNil(plan.tasks.first?.groupName)
        XCTAssertEqual(plan.projects.first?.destination, .inbox)
    }

    func testNothingToImport() throws {
        let empty = try TodoistReader.read(csv: "TYPE,CONTENT\nsection,Later\n", fileName: "Empty.csv")
        XCTAssertTrue(try plan(projects: [empty]).isEmpty)
    }
}

private extension XCTestCase {
    func assertDate(_ actual: Date?, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ message: String,
                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual, Fixed.date(y, m, d, h), message, file: file, line: line)
    }
    func assertDate(_ actual: Date?, _ y: Int, _ m: Int, _ d: Int, _ message: String,
                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual, Fixed.date(y, m, d), message, file: file, line: line)
    }
}
