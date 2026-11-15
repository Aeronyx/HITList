import XCTest
@testable import HITListCore

/// Brief 137: Todoist's CSV, read by the standard and then into project → sections → tasks → sub-tasks and notes.
/// Fixtures follow Todoist's documented columns (todoist.com/help/articles/360000748525): TYPE, CONTENT,
/// DESCRIPTION, PRIORITY, INDENT, AUTHOR, RESPONSIBLE, DATE, DATE_LANG, TIMEZONE, DURATION, DURATION_UNIT,
/// DEADLINE, DEADLINE_LANG, and a `meta` row.
final class TodoistReaderTests: XCTestCase {
    static let header = "TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT,AUTHOR,RESPONSIBLE,DATE,DATE_LANG,TIMEZONE,DURATION,DURATION_UNIT,DEADLINE,DEADLINE_LANG"

    // MARK: CSV by the standard

    func testCSVQuotesDoubledQuotesCommasAndLineBreaks() {
        let text = "a,\"b, with comma\",\"say \"\"hi\"\"\"\r\n\"two\r\nlines\",,last\r\n"
        XCTAssertEqual(TodoistCSV.rows(text), [["a", "b, with comma", "say \"hi\""], ["two\r\nlines", "", "last"]])
    }

    func testCSVByteOrderMarkAndNoFinalNewline() {
        XCTAssertEqual(TodoistCSV.rows("\u{FEFF}TYPE,CONTENT\ntask,Milk"), [["TYPE", "CONTENT"], ["task", "Milk"]])
    }

    func testCSVBlankLinesKeptAsEmptyRows() {
        XCTAssertEqual(TodoistCSV.rows("a,b\n\nc,d\n"), [["a", "b"], [""], ["c", "d"]])
    }

    // MARK: Todoist's rows

    func testSectionsTasksSubtasksAndNotes() throws {
        let csv = """
        \(Self.header)
        meta,view_style=list,,,,,,,,,,,,
        task,Inbox-ish top task @home,,1,1,George (1),,every day,en,US/Eastern,,None,,
        note,First comment,,,,George (1),,,,,,,,
        ,,,,,,,,,,,,,
        section,Errands,,,,,,,,,,,,
        task,Groceries,"Milk
        Eggs",4,1,George (1),,Nov 20,en,,,None,,
        task,Bread,,4,2,George (1),,,,,,,,
        task,Sourdough,,4,3,George (1),,,,,,,,
        note,Ask for the starter,,,,George (1),,,,,,,,
        task,Hardware store,,2,1,George (1),,,,,30,minute,Nov 30,en
        """
        let project = try TodoistReader.read(csv: csv, fileName: "Personal [2301234567].csv")
        XCTAssertEqual(project.name, "Personal")
        XCTAssertEqual(project.sections.map(\.name), [nil, "Errands"])
        let top = project.sections[0].tasks
        XCTAssertEqual(top.map(\.content), ["Inbox-ish top task @home"])
        XCTAssertEqual(top[0].priority, 1)
        XCTAssertEqual(top[0].date, "every day")
        XCTAssertEqual(top[0].timeZone, "US/Eastern")
        XCTAssertEqual(top[0].notes, ["First comment"])

        let errands = project.sections[1].tasks
        XCTAssertEqual(errands.map(\.content), ["Groceries", "Hardware store"])
        XCTAssertEqual(errands[0].description, "Milk\nEggs")
        XCTAssertEqual(errands[0].children.map(\.content), ["Bread"])
        XCTAssertEqual(errands[0].children[0].children.map(\.content), ["Sourdough"])
        XCTAssertEqual(errands[0].children[0].children[0].notes, ["Ask for the starter"], "a note belongs to the row above")
        XCTAssertEqual(errands[1].duration, "30")
        XCTAssertEqual(errands[1].durationUnit, "minute")
        XCTAssertEqual(errands[1].deadline, "Nov 30")
        XCTAssertEqual(project.taskCount, 5)
    }

    func testColumnsByNameInAnyOrderAndUnknownOnesSurvive() throws {
        let csv = """
        CONTENT,FUTURE_COLUMN,TYPE,INDENT,PRIORITY,DATE
        "Call ""Bob"", then Sue",whatever,task,1,2,tomorrow
        """
        let project = try TodoistReader.read(csv: csv, fileName: "Work.csv")
        XCTAssertEqual(project.name, "Work")
        let task = try XCTUnwrap(project.sections.first?.tasks.first)
        XCTAssertEqual(task.content, "Call \"Bob\", then Sue")
        XCTAssertEqual(task.priority, 2)
        XCTAssertEqual(task.date, "tomorrow")
        XCTAssertEqual(task.description, "")
    }

    func testAFileWithNoTasksReadsAsAnEmptyProject() throws {
        let project = try TodoistReader.read(csv: "\(Self.header)\nsection,Someday,,,,,,,,,,,,\n", fileName: "Empty [1].csv")
        XCTAssertEqual(project.taskCount, 0)
        XCTAssertEqual(project.sections.map(\.name), [nil, "Someday"])
    }

    func testNotATodoistFile() {
        XCTAssertThrowsError(try TodoistReader.read(csv: "name,email\nBob,bob@example.com", fileName: "people.csv")) { error in
            XCTAssertEqual(error as? TodoistReader.ReadError, .notTodoist)
        }
        XCTAssertThrowsError(try TodoistReader.read(csv: "", fileName: "blank.csv"))
    }

    func testAnIndentThatJumpsAttachesToTheDeepestTaskAbove() throws {
        let csv = "TYPE,CONTENT,INDENT\ntask,A,1\ntask,A1,3\ntask,B,1\n"
        let project = try TodoistReader.read(csv: csv, fileName: "x.csv")
        let tasks = project.sections[0].tasks
        XCTAssertEqual(tasks.map(\.content), ["A", "B"])
        XCTAssertEqual(tasks[0].children.map(\.content), ["A1"])
    }

    func testProjectNamesFromBackupFileNames() {
        XCTAssertEqual(TodoistReader.projectName(fromFileName: "Work [2301234567].csv"), "Work")
        XCTAssertEqual(TodoistReader.projectName(fromFileName: "Home [Renovation] [99].csv"), "Home [Renovation]")
        XCTAssertEqual(TodoistReader.projectName(fromFileName: "folder/Inbox [1].CSV"), "Inbox")
        XCTAssertEqual(TodoistReader.projectName(fromFileName: "Side project.csv"), "Side project")
    }
}
