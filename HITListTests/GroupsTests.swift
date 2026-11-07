import XCTest
import SwiftData
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 57: grouped Inbox and Today on real `TaskItem`s and `Project`s, their section headings, and the
/// remembered "Group by".
@MainActor
final class GroupsTests: XCTestCase {
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

    private func project(_ name: String, color: String = "#FF6B6B", order: Int) -> Project {
        let p = Project(name: name, colorHex: color, sortOrder: order)
        context.insert(p)
        return p
    }

    private func task(_ title: String, in project: Project? = nil, priority: Priority = .p4,
                      completed: Bool = false) -> TaskItem {
        let t = TaskItem(title: title)
        t.project = project
        t.priority = priority.rawValue
        t.isCompleted = completed
        context.insert(t)
        return t
    }

    // MARK: - Sections on real tasks

    func testInboxGroupedByGroupFollowsTheSidebarOrder() throws {
        let home = project("Home", order: 1), work = project("Work", order: 0)
        let tasks = [task("loose"), task("fix sink", in: home), task("ship it", in: work)]
        tasks.forEach { $0.dueDate = Date() } // dated, so the Grouped ones are in the Inbox too
        try context.save()
        let projects = try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.sortOrder)]))
        let inbox = TaskOrdering.inbox(try context.fetch(FetchDescriptor<TaskItem>()))
        let sections = GroupedOrdering.sections(inbox, by: .group, groupOrder: projects.map(\.id)) { $0.project?.id }
        XCTAssertEqual(sections.map(\.key), [.group(work.id), .group(home.id), .noGroup])
        XCTAssertEqual(sections.map { $0.tasks.map(\.title) }, [["ship it"], ["fix sink"], ["loose"]])
    }

    // MARK: - Headings

    func testAGroupHeadingCarriesItsDotNameCountAndOpensTheGroup() {
        let work = project("Work", color: "#6C9EFF", order: 0)
        let heading = GroupSectionHeading.make(for: .group(work.id), count: 3, projects: [work])
        XCTAssertEqual(heading.title, "Work")
        XCTAssertEqual(heading.dot, .filled(Color(hex: "#6C9EFF")))
        XCTAssertEqual(heading.count, 3)
        XCTAssertEqual(heading.opens, .project(work.id))
        XCTAssertEqual(heading.accessibilityLabel, "Work, 3 tasks")
    }

    func testNoGroupIsHollowAndOpensNothing() {
        let heading = GroupSectionHeading.make(for: .noGroup, count: 1, projects: [])
        XCTAssertEqual(heading.title, "No Group")
        XCTAssertEqual(heading.dot, .hollow)
        XCTAssertNil(heading.opens)
        XCTAssertEqual(heading.accessibilityLabel, "No Group, 1 task")
    }

    func testAGroupDeletedAMomentAgoReadsAsNoGroup() {
        let heading = GroupSectionHeading.make(for: .group(UUID()), count: 2, projects: [])
        XCTAssertEqual(heading.title, "No Group")
        XCTAssertNil(heading.opens)
    }

    func testPriorityHeadingsKeepTheirColoursAndNoDot() {
        let p1 = GroupSectionHeading.make(for: .priority(1), count: 2, projects: [])
        XCTAssertEqual(p1.title, "Priority 1")
        XCTAssertEqual(p1.titleColor, Priority.p1.color)
        XCTAssertNil(p1.dot)
        XCTAssertEqual(GroupSectionHeading.make(for: .priority(4), count: 2, projects: []).titleColor, Theme.secondaryText)
    }

    // MARK: - Title menu (iPhone)

    func testTitleMenuCountsOpenTopLevelTasksPerGroupAndLabel() throws {
        let work = project("Work", order: 0)
        let waiting = TaskLabel(name: "waiting")
        context.insert(waiting)
        let a = task("a", in: work), b = task("b", in: work)
        a.labels = [waiting]
        _ = b
        try context.save()
        let open = try context.fetch(FetchDescriptor<TaskItem>()).filter { !$0.isCompleted }
        let counts = GroupsTitleMenuCounts(open)
        XCTAssertEqual(counts.byProject[work.id], 2)
        XCTAssertEqual(counts.byLabel[waiting.id], 1)
        XCTAssertEqual(GroupsTitleMenuCounts.title("Work", count: 2), "Work · 2")
        XCTAssertEqual(GroupsTitleMenuCounts.title("Errands", count: 0), "Errands")
    }

    // MARK: - Group or label

    func testTheGuidanceSaysWhatAGroupAndALabelAre() {
        XCTAssertEqual(GroupGuidance.group, "A task lives in one Group: Work, Home, a project.")
        XCTAssertEqual(GroupGuidance.label, "A label is a tag any task can carry: @waiting, @errands.")
        let tip = HITTipKind.quickAddSyntax.message
        XCTAssertTrue(tip.contains("# picks its one Group") && tip.contains("@ adds any labels"), tip)
    }

    // MARK: - Reordering Groups

    func testMovingAGroupRenumbersEveryGroupInTheNewOrder() throws {
        let a = project("A", order: 0), b = project("B", order: 1), c = project("C", order: 2)
        try context.save()
        GroupReorder.move([a, b, c], from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual([a, b, c].map(\.sortOrder), [1, 2, 0])
        let sorted = try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(sorted.map(\.name), ["C", "A", "B"])
    }

    func testMovingRepairsDuplicateOrdersLeftByEarlierDeletesAndSyncs() {
        // Two Groups made on two devices before they synced share a sortOrder.
        let a = project("A", order: 3), b = project("B", order: 3), c = project("C", order: 7)
        let before = b.updatedAt
        GroupReorder.move([a, b, c], from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual([b, c, a].map(\.sortOrder), [0, 1, 2])
        XCTAssertGreaterThanOrEqual(b.updatedAt, before, "a changed Group is touched so the change syncs")
    }

    // MARK: - Remembered per list

    func testGroupByDefaultsAndStoredValues() {
        XCTAssertEqual(Preferences.inboxGroupingDefault, .priority, "the Inbox has grouped by priority since build 8")
        XCTAssertEqual(Preferences.todayGroupingDefault, .none)
        XCTAssertNotEqual(Preferences.inboxGrouping, Preferences.todayGrouping, "each list remembers its own")
        XCTAssertEqual(Preferences.grouping("group", default: .none), .group)
        XCTAssertEqual(Preferences.grouping(nil, default: .priority), .priority)
        XCTAssertEqual(Preferences.grouping("someday", default: .none), .none, "a value from a later build")
    }
}
