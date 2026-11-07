import XCTest
@testable import HITListCore

/// Brief 57: the Inbox's filter control writes a filter-language query; the list evaluates it.
final class ListFilterTests: XCTestCase {
    private let now = Fixed.now
    private let cal = Fixed.calendar

    private func matching(_ filter: ListFilter, _ tasks: [PlainTask]) throws -> [String] {
        guard let source = filter.query else { return tasks.map(\.filterTitle) }
        let query = try FilterQuery(source, calendar: cal, now: now)
        return tasks.filter { query.matches($0, now: now, calendar: cal) }.map(\.filterTitle)
    }

    private let tasks = [
        PlainTask(title: "work dated p1", priority: 1, dueDate: Fixed.date(2026, 10, 22), projectName: "Work"),
        PlainTask(title: "work undated", projectName: "Work", labelNames: ["waiting"]),
        PlainTask(title: "home dated", priority: 2, dueDate: Fixed.date(2026, 10, 21), projectName: "Home",
                  labelNames: ["errands"]),
        PlainTask(title: "loose undated", priority: 2, labelNames: ["waiting", "errands"]),
        PlainTask(title: "loose dated", dueDate: Fixed.date(2026, 10, 30)),
    ]

    func testAnEmptyFilterHasNoQueryAndNoChips() {
        let filter = ListFilter()
        XCTAssertTrue(filter.isEmpty)
        XCTAssertNil(filter.query)
        XCTAssertEqual(filter.chips, [])
    }

    func testOneGroupAndNoDate() throws {
        var filter = ListFilter()
        filter.toggle(.group("Work"))
        filter.toggle(.noDate)
        XCTAssertEqual(filter.query, "#\"Work\" & no date")
        XCTAssertEqual(try matching(filter, tasks), ["work undated"])
        XCTAssertEqual(filter.chips, [.group("Work"), .noDate])
    }

    func testChoicesWithinOneKindWidenAndKindsNarrow() throws {
        var filter = ListFilter()
        filter.toggle(.group("Work"))
        filter.toggle(.noGroup)
        filter.toggle(.priority(2))
        filter.toggle(.priority(1))
        XCTAssertEqual(filter.query, "(#\"Work\" | no project) & (p1 | p2)")
        XCTAssertEqual(try matching(filter, tasks), ["work dated p1", "loose undated"])
        XCTAssertEqual(filter.chips, [.group("Work"), .noGroup, .priority(1), .priority(2)], "priorities in order")
    }

    func testLabels() throws {
        var filter = ListFilter()
        filter.toggle(.label("waiting"))
        filter.toggle(.label("errands"))
        XCTAssertEqual(filter.query, "(@\"waiting\" | @\"errands\")")
        XCTAssertEqual(try matching(filter, tasks), ["work undated", "home dated", "loose undated"])
    }

    func testTogglingTwiceRemovesAndRemoveTakesOneChip() {
        var filter = ListFilter()
        filter.toggle(.group("Work"))
        filter.toggle(.group("Work"))
        XCTAssertTrue(filter.isEmpty)
        filter.toggle(.label("waiting"))
        filter.toggle(.noDate)
        XCTAssertTrue(filter.contains(.noDate))
        filter.remove(.noDate)
        XCTAssertFalse(filter.contains(.noDate))
        XCTAssertEqual(filter.chips, [.label("waiting")])
    }

    func testNamesWithQuotesSpacesAndBackslashesStayOneName() throws {
        var filter = ListFilter()
        filter.toggle(.group("Mom's \"big\" day \\ 2"))
        XCTAssertEqual(filter.query, #"#"Mom's \"big\" day \\ 2""#)
        let task = PlainTask(title: "party", projectName: "Mom's \"big\" day \\ 2")
        XCTAssertEqual(try matching(filter, [task, PlainTask(title: "other", projectName: "Mom's")]), ["party"])
    }

    func testChipTitles() {
        XCTAssertEqual(ListFilter.Chip.group("Work").title, "Work")
        XCTAssertEqual(ListFilter.Chip.noGroup.title, "No Group")
        XCTAssertEqual(ListFilter.Chip.label("waiting").title, "@waiting")
        XCTAssertEqual(ListFilter.Chip.priority(1).title, "P1")
        XCTAssertEqual(ListFilter.Chip.noDate.title, "No date")
    }

    func testSavedAsAFilterItKeepsTheInboxRule() throws {
        var filter = ListFilter()
        filter.toggle(.group("Work"))
        let source = try XCTUnwrap(filter.savedQuery(within: ListFilter.inboxQuery))
        XCTAssertEqual(source, "(has date | no project) & #\"Work\"")
        let query = try FilterQuery(source, calendar: cal, now: now)
        // "work undated" is a note in its Group, never in the Inbox, so the saved filter leaves it out too.
        XCTAssertEqual(query.apply(to: tasks, now: now, calendar: cal).map(\.filterTitle), ["work dated p1"])
        XCTAssertEqual(filter.suggestedName, "Inbox: Work")
        XCTAssertNil(ListFilter().savedQuery(within: ListFilter.inboxQuery))
    }

    func testTheInboxQueryMatchesTheInboxRule() throws {
        let query = try FilterQuery(ListFilter.inboxQuery, calendar: cal, now: now)
        for task in tasks {
            XCTAssertEqual(query.matches(task, now: now, calendar: cal), TaskOrdering.isInInbox(task), task.filterTitle)
        }
    }

    func testAGroupOrLabelThatIsGoneDropsOut() {
        var filter = ListFilter()
        filter.toggle(.group("Work"))
        filter.toggle(.group("Old"))
        filter.toggle(.label("gone"))
        filter.toggle(.noDate)
        filter.keep(groups: ["Work"], labels: ["waiting"])
        XCTAssertEqual(filter.chips, [.group("Work"), .noDate])
    }

    func testCodableRoundTrip() throws {
        var filter = ListFilter()
        filter.toggle(.group("Work"))
        filter.toggle(.label("waiting"))
        filter.toggle(.priority(3))
        filter.toggle(.noDate)
        filter.toggle(.noGroup)
        let decoded = try JSONDecoder().decode(ListFilter.self, from: JSONEncoder().encode(filter))
        XCTAssertEqual(decoded, filter)
    }
}
