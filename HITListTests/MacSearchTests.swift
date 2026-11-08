import XCTest
import SwiftData
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 66: the Mac sidebar's search field (where typing, Escape and the sidebar take the window) and what its
/// results column lists, Browse's rule (`SearchIntent`) on real `TaskItem`s.
@MainActor
final class MacSearchTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Where the window goes

    func testTypingShowsTheResultsAndEmptyingGoesBackToTheScreenYouWereOn() {
        let search = SidebarSearch()
        let work = SidebarItem.project(UUID())
        search.text = "m"
        XCTAssertEqual(search.selection(afterTextChangeFrom: work), .search)
        search.text = "milk"
        XCTAssertEqual(search.selection(afterTextChangeFrom: .search), .search)
        XCTAssertEqual(search.returnTo, work, "more typing keeps the screen to go back to")
        search.clear()
        XCTAssertEqual(search.selection(afterTextChangeFrom: .search), work)
        XCTAssertNil(search.returnTo)
    }

    func testOnlySpacesIsNoSearch() {
        let search = SidebarSearch()
        search.text = "   "
        XCTAssertEqual(search.selection(afterTextChangeFrom: .inbox), .inbox)
        XCTAssertNil(search.returnTo)
    }

    func testEmptyingWithNowhereToGoBackToOpensToday() {
        let search = SidebarSearch()
        search.text = "milk"
        XCTAssertEqual(search.selection(afterTextChangeFrom: nil), .search)
        search.clear()
        XCTAssertEqual(search.selection(afterTextChangeFrom: .search), .today)
    }

    func testChoosingAnotherScreenInTheSidebarEndsTheSearch() {
        let search = SidebarSearch()
        search.text = "milk"
        _ = search.selection(afterTextChangeFrom: .today)
        search.selectionChanged(to: .search)
        XCTAssertEqual(search.text, "milk", "the results' own selection keeps the search")
        search.selectionChanged(to: .upcoming)
        XCTAssertEqual(search.text, "")
        XCTAssertNil(search.returnTo)
        // The field's change that follows stays on the screen chosen.
        XCTAssertEqual(search.selection(afterTextChangeFrom: .upcoming), .upcoming)
    }

    func testAFiltersBadgePutsItsQueryInTheFieldAndFocusesIt() {
        let search = SidebarSearch()
        let filter = SidebarItem.filter(UUID())
        search.show("(p1 | p2) & (overdue | today)")
        XCTAssertEqual(search.text, "(p1 | p2) & (overdue | today)")
        XCTAssertEqual(search.focusRequests, 1)
        XCTAssertEqual(search.selection(afterTextChangeFrom: filter), .search)
        search.clear()
        XCTAssertEqual(search.selection(afterTextChangeFrom: .search), filter, "Escape goes back to the filter")
    }

    func testCommandFFocusesTheField() {
        let search = SidebarSearch()
        search.focus()
        search.focus()
        XCTAssertEqual(search.focusRequests, 2)
    }

    func testTheSearchScreenIsNoSavedFiltersAndNotSettings() {
        XCTAssertNotEqual(SidebarItem.search, .settings)
        XCTAssertNotEqual(SidebarItem.search, .flipboard)
        if case .filter(let id) = SidebarItem.search {
            XCTAssertEqual(id, SeedIdentity.uuid(for: "SidebarItem/search"))
        } else {
            XCTFail("a reserved filter id, so TaskListView's switches stay exhaustive")
        }
    }

    // MARK: - What it lists

    private func project(_ name: String) -> Project {
        let p = Project(name: name, colorHex: "#6C9EFF", sortOrder: 0)
        context.insert(p)
        return p
    }

    @discardableResult
    private func task(_ title: String, notes: String = "", in project: Project? = nil, priority: Priority = .p4,
                      completed: Bool = false) -> TaskItem {
        let t = TaskItem(title: title)
        t.notes = notes
        t.project = project
        t.priority = priority.rawValue
        t.isCompleted = completed
        context.insert(t)
        return t
    }

    private func all() throws -> [TaskItem] {
        try context.save()
        return try context.fetch(FetchDescriptor<TaskItem>())
    }

    func testPlainTextLooksThroughTitlesAndDescriptionsCompletedTasksToo() throws {
        task("Buy milk")
        task("Groceries", notes: "oat milk, eggs")
        task("milk the cows", completed: true)
        task("Call mom")
        let model = SearchResultsModel(text: "milk", tasks: try all())
        XCTAssertEqual(model.kind, .text(unfinishedQuery: nil))
        XCTAssertEqual(Set(model.tasks.map(\.title)), ["Buy milk", "Groceries", "milk the cows"])
        XCTAssertNil(model.query)
        XCTAssertEqual(model.countLine, "3 tasks")
    }

    func testAFilterQueryFiltersAsItsSavedFilterWouldAndCanBeSaved() throws {
        let work = project("Work")
        task("Ship it", in: work, priority: .p1)
        task("Plan", in: work)
        task("Shipped", in: work, completed: true)
        task("Work out") // the word, not the Group
        let model = SearchResultsModel(text: " #Work ", tasks: try all())
        XCTAssertEqual(model.kind, .query("#Work"))
        XCTAssertEqual(model.query, "#Work")
        XCTAssertEqual(Set(model.tasks.map(\.title)), ["Ship it", "Plan"])

        let p1 = SearchResultsModel(text: "#Work & p1", tasks: try all())
        XCTAssertEqual(p1.tasks.map(\.title), ["Ship it"])
        XCTAssertEqual(p1.countLine, "1 task")
    }

    func testKeywordQueriesAreFilters() throws {
        let late = task("Late")
        late.dueDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())
        task("Undated")
        let model = SearchResultsModel(text: "overdue", tasks: try all())
        XCTAssertEqual(model.kind, .query("overdue"))
        XCTAssertEqual(model.tasks.map(\.title), ["Late"])
    }

    func testAnUnfinishedQuerySaysWhatIsMissing() throws {
        task("waiting on Sam")
        let model = SearchResultsModel(text: "@waiting &", tasks: try all())
        guard case .text(let unfinished?) = model.kind else { return XCTFail("\(model.kind)") }
        XCTAssertTrue(model.emptyMessage.hasPrefix("Not a filter yet: "))
        XCTAssertTrue(model.emptyMessage.hasSuffix(unfinished))
        XCTAssertNil(model.query)
    }

    func testNothingTypedListsNothing() throws {
        task("Buy milk")
        let model = SearchResultsModel(text: "  ", tasks: try all())
        XCTAssertEqual(model.kind, .empty)
        XCTAssertTrue(model.tasks.isEmpty)
    }
}
