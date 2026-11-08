import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// Brief 62, item 3: shared tasks in your lists. A shared row opens its editor through the popouts (one task at a
/// time, drawn by the list that opened it), its list's section header carries the two-person marker, and its row is
/// the height of a row of yours. In-memory stores only.
@MainActor
final class SharedListsTests: XCTestCase {
    private let ref = SharedTaskRef(taskID: UUID(), listID: UUID())

    private func controller() -> PopoutController {
        PopoutController(draftDefaults: UserDefaults(suiteName: "SharedListsTests-\(UUID())")!, center: NotificationCenter())
    }

    // MARK: - Popouts

    func testASharedTaskIsOneMorePopoutAndOpeningItClosesTheOthers() {
        var state = PopoutState()
        state.openQuickAdd(.today)
        state.openSharedTask(ref)
        XCTAssertNil(state.quickAdd, "one popout at a time")
        XCTAssertEqual(state.sharedTask, ref)
        XCTAssertTrue(state.isSharedTaskOpen)
        XCTAssertFalse(state.showsAddButton, "the floating + hides while it is open")

        state.openTask(UUID())
        XCTAssertNil(state.sharedTask, "opening a task of yours closes it")
        state.openSharedTask(ref)
        XCTAssertNil(state.taskID)
        state.openQuickAdd(.inbox)
        XCTAssertNil(state.sharedTask, "so does the quick add")
        state.openSharedTask(ref)
        state.closeAll()
        XCTAssertFalse(state.isSharedTaskOpen)
        XCTAssertTrue(state.showsAddButton)
    }

    func testOnlyTheListThatOpenedItDrawsTheEditor() {
        let popouts = controller()
        let today = UUID(), group = UUID()
        popouts.openShared(ref, owner: today)
        XCTAssertEqual(popouts.sharedTask(for: today), ref)
        XCTAssertNil(popouts.sharedTask(for: group), "a list under it on the stack never presents it too")
        popouts.closeSharedTask()
        XCTAssertNil(popouts.sharedTask(for: today))
        XCTAssertNil(popouts.state.sharedTask)
    }

    func testSelectingASharedRowOpensItsEditorAndKeepsTheRowSelected() {
        let popouts = controller()
        let owner = UUID()
        let selection = popouts.listSelection(owner: owner)
        selection.wrappedValue = .shared(ref)
        XCTAssertEqual(popouts.sharedTask(for: owner), ref)
        XCTAssertEqual(selection.wrappedValue, .shared(ref), "highlighted while open")
        XCTAssertNil(popouts.listSelection(owner: UUID()).wrappedValue, "another list's rows stay plain")
        selection.wrappedValue = nil
        XCTAssertNil(popouts.state.sharedTask)
    }

    func testSelectingATaskOfYoursClosesASharedEditorAndAnAccountSwitchClosesBoth() throws {
        let container = ModelContainerFactory.preview()
        let task = TaskItem(title: "Call Sam")
        container.mainContext.insert(task)
        let popouts = controller()
        let owner = UUID()
        popouts.openShared(ref, owner: owner)
        popouts.listSelection(owner: owner).wrappedValue = .task(task)
        XCTAssertNil(popouts.sharedTask(for: owner))
        XCTAssertEqual(popouts.task?.id, task.id)
        XCTAssertEqual(popouts.listSelection(owner: owner).wrappedValue, .task(task))

        popouts.openShared(ref, owner: owner)
        XCTAssertNil(popouts.task, "a shared task replaces the open task of yours")
        popouts.accountDidSwitch()
        XCTAssertNil(popouts.sharedTask(for: owner), "another Apple account sees nothing the previous one opened")
    }

    func testDeletingASharedTaskAsksFirstWhenTheSettingSaysSo() {
        let popouts = controller()
        var deleted = false
        popouts.requestDelete(title: "Book the cabin") { deleted = true }
        if Preferences.value(Preferences.confirmDelete, default: Preferences.confirmDeleteDefault) {
            XCTAssertEqual(popouts.pendingDelete?.title, "Book the cabin")
            popouts.confirmPendingDelete()
        }
        XCTAssertTrue(deleted)
    }

    // MARK: - Section headers

    private func list(_ title: String, in store: SharedTasksStore) throws -> SharedList {
        try store.createList(title: title, colorHex: "#F2A65A")
    }

    private func sharedStore() -> SharedTasksStore {
        let store = SharedTasksStore(persistence: .memory)
        store.setMe("_me000000000000000000000000000000")
        return store
    }

    func testASharedListsSectionIsHeadedByItsNameWithThePeopleMarker() throws {
        let trip = try list("Trip", in: sharedStore())
        let heading = RowSectionHeading.make(for: .group(.shared(trip.id)), count: 2, projects: [], sharedLists: [trip])
        XCTAssertTrue(heading.isShared)
        XCTAssertEqual(heading.heading.title, "Trip")
        XCTAssertNil(heading.heading.dot, "the marker stands where a Group's dot is")
        XCTAssertEqual(heading.sharedColor, Color(hex: "#F2A65A"))
        XCTAssertEqual(String(heading.heading.label.characters), "Trip · 2", "name and count as one run, one font")
        XCTAssertEqual(heading.accessibilityLabel, "Trip, shared list, 2 tasks")
    }

    func testGroupUngroupedAndDaySectionsAreHeadedAsBefore() throws {
        let container = ModelContainerFactory.preview()
        let work = Project(name: "Work")
        container.mainContext.insert(work)
        let projects = [work]
        let now = Date()
        for (key, plain) in [(ListSectionKey<ListRowGroup>.group(.group(work.id)), ListSectionKey<UUID>.group(work.id)),
                             (.ungrouped, .ungrouped), (.due(.tomorrow), .due(.tomorrow)), (.all, .all)] {
            let heading = RowSectionHeading.make(for: key, count: 3, projects: projects, sharedLists: [], now: now)
            XCTAssertFalse(heading.isShared)
            XCTAssertEqual(heading.heading, GroupSectionHeading.make(for: plain, count: 3, projects: projects, now: now))
        }
    }

    func testAListThatJustWentKeepsAnUntitledSection() {
        let heading = RowSectionHeading.make(for: .group(.shared(UUID())), count: 1, projects: [], sharedLists: [])
        XCTAssertEqual(heading.heading.title, SharedRow.untitled)
        XCTAssertTrue(heading.isShared)
    }

    // MARK: - The row

    #if os(macOS)
    /// A shared row is drawn from `TaskRow`'s parts: the same height for the same title and second line, so the two
    /// kinds line up in one list.
    func testASharedRowIsTheHeightOfARowOfYours() throws {
        let container = ModelContainerFactory.preview()
        let project = Project(name: "Trip")
        container.mainContext.insert(project)
        let now = Date()
        let due = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now))!
        let mine = TaskItem(title: "Book the cabin", dueDate: due)
        mine.project = project
        container.mainContext.insert(mine)
        try container.mainContext.save()

        let store = sharedStore()
        let trip = try list("Trip", in: store)
        let task = try store.addTask(to: trip.id, title: "Book the cabin", due: SharedDue(date: due, hasTime: false))
        let shared = SharedRow(task: task, list: try XCTUnwrap(store.list(trip.id)))

        func height<V: View>(_ view: V) -> CGFloat {
            NSHostingView(rootView: view.frame(width: 420).modelContainer(container)).fittingSize.height
        }
        let own = height(TaskRow(task: mine, now: now, onToggleCompletion: {}))
        let theirs = height(SharedTaskListRow(row: shared, now: now, onToggleCompletion: {}))
        XCTAssertEqual(theirs, own, accuracy: 0.5)
        // An empty second line (under its own list's header, the day in the day's header) keeps the height an empty
        // line of yours has.
        let emptyOwn = height(TaskRow(task: mine, now: now, showProject: false, hidesDay: true, onToggleCompletion: {}))
        let emptyShared = height(SharedTaskListRow(row: shared, now: now, showList: false, hidesDay: true, onToggleCompletion: {}))
        XCTAssertEqual(emptyShared, emptyOwn, accuracy: 0.5)
    }
    #endif
}
