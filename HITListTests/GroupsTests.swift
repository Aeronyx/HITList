import XCTest
import SwiftData
import SwiftUI
import HITListCore
@testable import HITList

/// Briefs 57 and 61: the Inbox and Today sorted by Group or Date on real `TaskItem`s and `Project`s, their
/// section headings, and the remembered "Sort by".
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

    func testInboxSortedByGroupFollowsTheSidebarOrder() throws {
        let home = project("Home", order: 1), work = project("Work", order: 0)
        let tasks = [task("loose"), task("fix sink", in: home), task("ship it", in: work)]
        tasks.forEach { $0.dueDate = Date() } // dated, so the Grouped ones are in the Inbox too
        try context.save()
        let projects = try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.sortOrder)]))
        let inbox = TaskOrdering.inbox(try context.fetch(FetchDescriptor<TaskItem>()))
        let sections = GroupedOrdering.sections(inbox, by: .group, groupOrder: projects.map(\.id), now: Date()) { $0.project?.id }
        XCTAssertEqual(sections.map(\.key), [.group(work.id), .group(home.id), .ungrouped])
        XCTAssertEqual(sections.map { $0.tasks.map(\.title) }, [["ship it"], ["fix sink"], ["loose"]])
    }

    // MARK: - Headings

    func testAGroupHeadingCarriesItsDotNameAndCount() {
        let work = project("Work", color: "#6C9EFF", order: 0)
        let heading = GroupSectionHeading.make(for: .group(work.id), count: 3, projects: [work])
        XCTAssertEqual(heading.title, "Work")
        XCTAssertEqual(heading.dot, .filled(Color(hex: "#6C9EFF")))
        XCTAssertEqual(heading.count, 3)
        XCTAssertEqual(heading.accessibilityLabel, "Work, 3 tasks")
    }

    func testTheTitleAndCountAreOneRunOfTextWithTheCountInGrey() {
        // George, 0.8.0: "Priority 4 1 in different fonts". One Text, one font; only the count's colour differs.
        let work = project("Work", order: 0)
        let label = GroupSectionHeading.make(for: .group(work.id), count: 3, projects: [work]).label
        XCTAssertEqual(String(label.characters), "Work · 3")
        let runs = Array(label.runs)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(String(label[runs[0].range].characters), "Work")
        XCTAssertNil(runs[0].swiftUI.foregroundColor, "the title takes the header's colour")
        XCTAssertEqual(runs[1].swiftUI.foregroundColor, Theme.secondaryText)
        XCTAssertNil(runs[0].swiftUI.font, "the font is the header's, for both")
        XCTAssertNil(runs[1].swiftUI.font)
        let empty = GroupSectionHeading.make(for: .group(work.id), count: 0, projects: [work]).label
        XCTAssertEqual(String(empty.characters), "Work", "no count when nothing is open")
    }

    func testUngroupedIsHollow() {
        let heading = GroupSectionHeading.make(for: .ungrouped, count: 2, projects: [])
        XCTAssertEqual(heading.title, "Ungrouped")
        XCTAssertEqual(heading.dot, .hollow)
        XCTAssertEqual(String(heading.label.characters), "Ungrouped · 2")
        XCTAssertEqual(heading.accessibilityLabel, "Ungrouped, 2 tasks")
    }

    func testAGroupDeletedAMomentAgoReadsAsUngrouped() {
        let heading = GroupSectionHeading.make(for: .group(UUID()), count: 2, projects: [])
        XCTAssertEqual(heading.title, "Ungrouped")
    }

    func testDateHeadingsUseTheDueColoursAndNoDot() {
        let now = Date()
        let overdue = GroupSectionHeading.make(for: .due(.overdue), count: 2, projects: [], now: now)
        XCTAssertEqual(overdue.title, "Overdue")
        XCTAssertEqual(overdue.titleColor, HITColor.dueOverdue)
        XCTAssertNil(overdue.dot)
        let today = GroupSectionHeading.make(for: .due(.today), count: 1, projects: [], now: now)
        XCTAssertEqual(today.title, "Today")
        XCTAssertEqual(today.titleColor, HITColor.dueToday)
        XCTAssertEqual(GroupSectionHeading.make(for: .due(.tomorrow), count: 1, projects: [], now: now).title, "Tomorrow")
        XCTAssertEqual(GroupSectionHeading.make(for: .due(.later), count: 1, projects: [], now: now).title, "Later")
        XCTAssertEqual(GroupSectionHeading.make(for: .due(.noDate), count: 1, projects: [], now: now).title, "No date")

        // A day of the coming week by name, as the filter lists title it.
        let day = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 3, to: now)!)
        let named = GroupSectionHeading.make(for: .due(.day(day)), count: 1, projects: [], now: now)
        XCTAssertEqual(named.title, DueFormatter.sectionTitle(for: day, now: now))
        XCTAssertTrue(named.title.contains(day.formatted(.dateTime.weekday(.wide))), named.title)
        XCTAssertEqual(named.titleColor, Theme.secondaryText)
    }

    // MARK: - Group or label

    func testTheGuidanceSaysWhatAGroupAndALabelAre() {
        XCTAssertEqual(GroupGuidance.group, "A task lives in one Group: Work, Home, a project.")
        XCTAssertEqual(GroupGuidance.label, "A label is a tag any task can carry: @waiting, @errands.")
        let tip = HITTipKind.quickAddSyntax.message
        XCTAssertTrue(tip.contains("# picks its one Group") && tip.contains("@ adds any labels"), tip)
        let browse = HITTipKind.browse.message
        XCTAssertTrue(browse.contains("search that understands #Work"), "the Browse tip teaches filters in the search: \(browse)")
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

    // MARK: - Deleting a Group

    func testDeletingAGroupAsksOnlyWhenItHasTasksAndSaysWhereTheyGo() throws {
        let work = project("Work", order: 0), empty = project("Empty", order: 1)
        _ = task("a", in: work)
        _ = task("b", in: work, completed: true)
        _ = task("c", in: work)
        try context.save()
        XCTAssertNil(GroupDeletion(project: empty), "an empty Group goes without a question")
        let question = try XCTUnwrap(GroupDeletion(project: work))
        XCTAssertEqual(question.title, "Delete “Work”?")
        XCTAssertEqual(question.message, "Its 2 open tasks move to the Inbox. Completed ones stay completed.")
        _ = task("d", in: empty)
        XCTAssertEqual(GroupDeletion(project: empty)?.message, "Its 1 open task moves to the Inbox.")
    }

    // MARK: - Remembered per list

    func testSortByDefaultsToPriorityAndForgets080sGroupBy() {
        XCTAssertEqual(Preferences.listSortDefault, .priority, "the Inbox sorts by priority, as it always did")
        XCTAssertNotEqual(Preferences.inboxSort, Preferences.todaySort, "each list remembers its own")
        XCTAssertFalse(Preferences.inboxSort.hasPrefix("pref.grouping"), "0.8.0's Group by is not read")
        XCTAssertFalse(Preferences.todaySort.hasPrefix("pref.grouping"))
        XCTAssertEqual(Preferences.sort(nil, offered: ListSort.inbox), .priority)
        XCTAssertEqual(Preferences.sort("group", offered: ListSort.inbox), .group)
        XCTAssertEqual(Preferences.sort("date", offered: ListSort.inbox), .date)
        XCTAssertEqual(Preferences.sort("date", offered: ListSort.today), .priority, "Today has no Date sort")
        XCTAssertEqual(Preferences.sort("none", offered: ListSort.inbox), .priority, "0.8.0's None")
        XCTAssertEqual(Preferences.sort("someday", offered: ListSort.today), .priority, "a value from a later build")
    }
}
