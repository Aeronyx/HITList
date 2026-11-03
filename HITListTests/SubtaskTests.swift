import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Subtasks (brief 32): one level deep, a checklist inside a task. Title and done only; they take their
/// parent's Group and are never rows of their own.
@MainActor
final class SubtaskTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let cal = Calendar.current

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func task(_ title: String, project: Project? = nil, due: Date? = nil, recurrence: RecurrenceRule? = nil) throws -> TaskItem {
        let t = TaskItem(title: title, dueDate: due, project: project, recurrence: recurrence)
        context.insert(t)
        try context.save()
        return t
    }

    private func tomorrow() -> Date { cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))! }

    /// "Pack for trip" with Socks, Charger, Passport.
    private func trip(project: Project? = nil, recurrence: RecurrenceRule? = nil) throws -> TaskItem {
        let parent = try task("Pack for trip", project: project, due: recurrence == nil ? nil : tomorrow(), recurrence: recurrence)
        for title in ["Socks", "Charger", "Passport"] { try TaskActions.addSubtask(title, to: parent, in: context) }
        return parent
    }

    // MARK: Adding

    func testAddingSubtasksAppendsThemInOrderInTheParentsGroup() throws {
        let home = Project(name: "Home")
        context.insert(home)
        let parent = try trip(project: home)
        XCTAssertEqual(parent.orderedSubtasks.map(\.title), ["Socks", "Charger", "Passport"])
        for subtask in parent.orderedSubtasks {
            XCTAssertEqual(subtask.parent?.id, parent.id)
            XCTAssertEqual(subtask.project?.name, "Home", "a subtask takes its parent's Group")
            XCTAssertNil(subtask.dueDate)
            XCTAssertEqual(subtask.priority, 4)
            XCTAssertEqual(subtask.labels ?? [], [])
            XCTAssertNil(subtask.reminderOffsetMinutes, "subtasks have no reminders")
        }
    }

    func testABlankSubtaskIsRefusedAndALongOneIsTrimmedToOneLine() throws {
        let parent = try task("Pack")
        XCTAssertThrowsError(try TaskActions.addSubtask("   ", to: parent, in: context))
        let added = try TaskActions.addSubtask("  Socks\nand shoes  ", to: parent, in: context)
        XCTAssertEqual(added.title, "Socks and shoes")
        XCTAssertEqual(parent.subtasks?.count, 1)
    }

    func testASubtaskAddedToASubtaskGoesToItsParent() throws {
        let parent = try trip()
        let socks = try XCTUnwrap(parent.orderedSubtasks.first)
        let added = try TaskActions.addSubtask("Wool ones", to: socks, in: context)
        XCTAssertEqual(added.parent?.id, parent.id, "one level only")
        XCTAssertEqual(socks.subtasks ?? [], [])
    }

    // MARK: One level

    func testOnlyATaskInItsOwnRightCanTakeSubtasks() throws {
        let parent = try trip()
        let socks = try XCTUnwrap(parent.orderedSubtasks.first)
        let loose = try task("Loose")
        let other = try task("Other")
        XCTAssertTrue(TaskActions.canNest(loose, under: other))
        XCTAssertFalse(TaskActions.canNest(loose, under: socks), "a subtask cannot get subtasks")
        XCTAssertFalse(TaskActions.canNest(parent, under: other), "a task with subtasks cannot become one")
        XCTAssertFalse(TaskActions.canNest(other, under: other))
        XCTAssertFalse(TaskActions.makeSubtask(parent, of: other, in: context))
        XCTAssertNil(parent.parent)
    }

    func testMakingATaskASubtaskStripsWhatSubtasksDoNotHave() throws {
        let work = Project(name: "Work")
        context.insert(work)
        let parent = try task("Release", project: work)
        let loose = try task("Write notes", due: tomorrow(), recurrence: .daily)
        loose.priority = 1
        loose.reminderOffsetMinutes = 15
        loose.labels = [try TaskActions.findOrCreateLabel(named: "docs", in: context)]
        XCTAssertTrue(TaskActions.makeSubtask(loose, of: parent, in: context))
        XCTAssertEqual(loose.parent?.id, parent.id)
        XCTAssertEqual(loose.project?.name, "Work")
        XCTAssertNil(loose.dueDate)
        XCTAssertFalse(loose.hasDueTime)
        XCTAssertNil(loose.recurrence)
        XCTAssertNil(loose.reminderOffsetMinutes)
        XCTAssertEqual(loose.priority, 4)
        XCTAssertEqual(loose.labels ?? [], [])
    }

    // MARK: Completion

    func testCompletingTheParentCompletesItsOpenSubtasksAndUndoReopensThem() throws {
        let parent = try trip()
        let socks = parent.orderedSubtasks[0], charger = parent.orderedSubtasks[1], passport = parent.orderedSubtasks[2]
        TaskActions.toggleCompletion(socks, in: context)
        let socksDoneAt = try XCTUnwrap(socks.completedAt)

        TaskActions.toggleCompletion(parent, in: context)
        XCTAssertTrue(parent.isCompleted)
        XCTAssertTrue(charger.isCompleted && passport.isCompleted)
        XCTAssertEqual(socks.completedAt, socksDoneAt, "one done before keeps its own time")

        TaskActions.toggleCompletion(parent, in: context)  // the toast's Undo, or the Completed list
        XCTAssertFalse(parent.isCompleted)
        XCTAssertFalse(charger.isCompleted || passport.isCompleted, "the ones the parent closed open again")
        XCTAssertTrue(socks.isCompleted, "the one ticked by hand stays ticked")
    }

    func testThePopoutsUndoToastReopensTheSubtasks() throws {
        let parent = try trip()
        let suite = "HITListTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let popouts = PopoutController(draftDefaults: UserDefaults(suiteName: suite)!)
        popouts.open(parent)
        popouts.complete(parent, in: context)
        XCTAssertTrue(parent.orderedSubtasks.allSatisfy(\.isCompleted))
        popouts.undoCompletions(in: context)
        XCTAssertFalse(parent.isCompleted)
        XCTAssertTrue(parent.orderedSubtasks.allSatisfy { !$0.isCompleted })
    }

    func testCompletingTheLastSubtaskLeavesTheParentOpen() throws {
        let parent = try trip()
        for subtask in parent.orderedSubtasks { TaskActions.toggleCompletion(subtask, in: context) }
        XCTAssertTrue(parent.orderedSubtasks.allSatisfy(\.isCompleted))
        XCTAssertFalse(parent.isCompleted, "Todoist's rule: ticking the checklist doesn't finish the task")
    }

    func testARepeatingParentRollingOverResetsItsChecklist() throws {
        let parent = try trip(recurrence: .daily)
        let due = try XCTUnwrap(parent.dueDate)
        for subtask in parent.orderedSubtasks.prefix(2) { TaskActions.toggleCompletion(subtask, in: context) }
        TaskActions.toggleCompletion(parent, in: context)
        XCTAssertGreaterThan(try XCTUnwrap(parent.dueDate), due, "it rolled over")
        XCTAssertFalse(parent.isCompleted)
        XCTAssertTrue(parent.orderedSubtasks.allSatisfy { !$0.isCompleted && $0.completedAt == nil }, "the next one starts fresh")
        XCTAssertEqual(parent.subtasks?.count, 3)
    }

    // MARK: Deleting, moving, ordering

    func testDeletingTheParentDeletesItsSubtasks() throws {
        let parent = try trip()
        _ = try task("Unrelated")
        TaskActions.delete(parent, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title), ["Unrelated"])
    }

    func testDeletingASubtaskLeavesTheRest() throws {
        let parent = try trip()
        TaskActions.delete(parent.orderedSubtasks[1], in: context)
        XCTAssertEqual(parent.orderedSubtasks.map(\.title), ["Socks", "Passport"])
    }

    func testMovingTheParentToAGroupMovesItsChecklist() throws {
        let parent = try trip()
        let home = Project(name: "Home")
        context.insert(home)
        TaskActions.setProject(home, of: parent, in: context)
        XCTAssertEqual(parent.project?.name, "Home")
        XCTAssertTrue(parent.orderedSubtasks.allSatisfy { $0.project?.name == "Home" })
        TaskActions.setProject(nil, of: parent, in: context)
        XCTAssertTrue(parent.orderedSubtasks.allSatisfy { $0.project == nil })
    }

    func testReorderingASubtaskRenumbersTheChecklist() throws {
        let parent = try trip()
        let passport = parent.orderedSubtasks[2]
        TaskActions.moveSubtask(passport, to: 0, in: context)
        XCTAssertEqual(parent.orderedSubtasks.map(\.title), ["Passport", "Socks", "Charger"])
        TaskActions.moveSubtask(passport, to: 5, in: context)
        XCTAssertEqual(parent.orderedSubtasks.map(\.title), ["Socks", "Charger", "Passport"], "past the end is the end")
        XCTAssertEqual(parent.orderedSubtasks.map(\.sortOrder), [0, 1, 2])
    }

    func testProgressCountsDoneSubtasks() throws {
        XCTAssertNil(try task("Plain").subtaskProgress, "no checklist, no count")
        let parent = try trip()
        TaskActions.toggleCompletion(parent.orderedSubtasks[0], in: context)
        TaskActions.toggleCompletion(parent.orderedSubtasks[2], in: context)
        XCTAssertEqual(parent.subtaskProgress, SubtaskProgress(done: 2, total: 3))
        XCTAssertEqual(parent.subtaskProgress?.compactText, "2/3")
        XCTAssertEqual(parent.subtaskProgress?.text, "2 of 3")
    }

    // MARK: Lists

    func testNoListShowsASubtaskAsARow() throws {
        let parent = try trip()
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertTrue(parent.orderedSubtasks.allSatisfy(\.filterIsSubtask))
        XCTAssertFalse(parent.filterIsSubtask)
        XCTAssertEqual(TaskOrdering.inbox(tasks).map(\.title), ["Pack for trip"])
        XCTAssertEqual(try FilterQuery("no date").apply(to: tasks).map(\.title), ["Pack for trip"])
        XCTAssertEqual(TaskOrdering.search(tasks, text: "socks").count, 0)
    }

    // MARK: Rows

    /// A parent's row says how far through its checklist it is ("2/3" by a checklist glyph); a task
    /// without sub-tasks says nothing, and the count alone gives an undated task a second line.
    func testTheRowShowsTheChecklistCount() throws {
        let plain = try task("Plain")
        XCTAssertNil(TaskRow.checklistText(for: plain))
        XCTAssertFalse(TaskRow.hasMeta(plain, hidesDay: false, showProject: true))

        let parent = try trip()
        TaskActions.toggleCompletion(parent.orderedSubtasks[0], in: context)
        TaskActions.toggleCompletion(parent.orderedSubtasks[1], in: context)
        XCTAssertEqual(TaskRow.checklistText(for: parent), "2/3")
        XCTAssertTrue(TaskRow.hasMeta(parent, hidesDay: true, showProject: false))
    }
}
