import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// Briefs 62 and 64: shared tasks in your lists. A shared row opens its editor through the popouts (one task at a time,
/// drawn by the popout host as yours is), Shared Tasks' section header is a Group's, and its row is the height of a
/// row of yours. In-memory stores only.
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

    func testSelectingATaskOfYoursClosesASharedEditorAndAnAccountSwitchClosesBoth() throws {
        let container = ModelContainerFactory.preview()
        let task = TaskItem(title: "Call Sam")
        container.mainContext.insert(task)
        let popouts = controller()
        popouts.openShared(ref)
        popouts.listSelection.wrappedValue = .task(task)
        XCTAssertNil(popouts.state.sharedTask)
        XCTAssertEqual(popouts.task?.id, task.id)
        XCTAssertEqual(popouts.listSelection.wrappedValue, .task(task))

        popouts.openShared(ref)
        XCTAssertNil(popouts.task, "a shared task replaces the open task of yours")
        popouts.accountDidSwitch()
        XCTAssertNil(popouts.state.sharedTask, "another Apple account sees nothing the previous one opened")
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

    func testSharedTasksSectionIsHeadedLikeAnyGroupWithItsDot() {
        // Brief 64: one forced Group, its dot where any Group's sits, never the two-person marker.
        let heading = GroupSectionHeading.make(row: .group(.sharedTasks), count: 2, projects: [])
        XCTAssertEqual(heading.title, "Shared Tasks")
        XCTAssertEqual(heading.dot, .filled(Color(hex: SharedTasksGroup.colorHex)))
        XCTAssertEqual(heading.titleColor, HITColor.text)
        XCTAssertEqual(String(heading.label.characters), "Shared Tasks · 2", "name and count as one run, one font")
        XCTAssertEqual(heading.accessibilityLabel, "Shared Tasks, 2 tasks")
    }

    func testGroupUngroupedAndDaySectionsAreHeadedAsBefore() throws {
        let container = ModelContainerFactory.preview()
        let work = Project(name: "Work")
        container.mainContext.insert(work)
        let projects = [work]
        let now = Date()
        for (key, plain) in [(ListSectionKey<ListRowGroup>.group(.group(work.id)), ListSectionKey<UUID>.group(work.id)),
                             (.ungrouped, .ungrouped), (.due(.tomorrow), .due(.tomorrow)), (.all, .all)] {
            let heading = GroupSectionHeading.make(row: key, count: 3, projects: projects, now: now)
            XCTAssertEqual(heading, GroupSectionHeading.make(for: plain, count: 3, projects: projects, now: now))
        }
    }

    // MARK: - The row

    #if os(macOS)
    /// A shared row is drawn from `TaskRow`'s parts (brief 64): the same height as a row of yours with the same fields,
    /// the people's pictures in the label slot's height, "Shared Tasks" and its dot where your Group sits.
    func testASharedRowIsTheHeightOfARowOfYours() throws {
        let container = ModelContainerFactory.preview()
        let project = Project(name: "Trip")
        container.mainContext.insert(project)
        let now = Date()
        let due = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now))!
        let mine = TaskItem(title: "Book the cabin", dueDate: due)
        mine.project = project
        container.mainContext.insert(mine)
        let label = TaskLabel(name: "errands")
        container.mainContext.insert(label)
        mine.labels = [label]
        try container.mainContext.save()

        let store = sharedStore()
        let trip = try list("Trip", in: store)
        let task = try store.addTask(to: trip.id, title: "Book the cabin", due: SharedDue(date: due, hasTime: false))
        let sam = SharedPerson(id: "sam", name: "Sam Rivera", avatar: nil, isOwner: true, isMe: false, isPending: false, memberID: "sam")
        let alex = SharedPerson(id: "alex", name: "Alex Kim", avatar: nil, isOwner: false, isMe: false, isPending: false, memberID: "alex")
        let shared = SharedRow(task: task, list: try XCTUnwrap(store.list(trip.id)), people: [sam, alex])

        func height<V: View>(_ view: V) -> CGFloat {
            NSHostingView(rootView: view.frame(width: 420).modelContainer(container)).fittingSize.height
        }
        let own = height(TaskRow(task: mine, now: now, onToggleCompletion: {}))
        let theirs = height(SharedTaskListRow(row: shared, now: now, onToggleCompletion: {}))
        XCTAssertEqual(theirs, own, accuracy: 0.5, "the pictures sit in the label slot's height")
        // An empty second line (under its own Group's header, the day in the day's header) keeps the height an empty
        // line of yours has.
        mine.labels = []
        let emptyOwn = height(TaskRow(task: mine, now: now, showProject: false, hidesDay: true, onToggleCompletion: {}))
        let alone = SharedRow(task: task, list: try XCTUnwrap(store.list(trip.id)), people: [])
        let emptyShared = height(SharedTaskListRow(row: alone, now: now, showGroup: false, hidesDay: true, onToggleCompletion: {}))
        XCTAssertEqual(emptyShared, emptyOwn, accuracy: 0.5)
    }

    func testTheAvatarsFillTheMetaLinesHeightAndNoMore() throws {
        let people = (0..<5).map { SharedPerson(id: "\($0)", name: "P\($0)", avatar: nil, isOwner: false, isMe: false,
                                                isPending: false, memberID: "\($0)") }
        let line = NSHostingView(rootView: Text(" ").font(HITType.taskMeta)).fittingSize.height
        let stack = NSHostingView(rootView: SharedRowPeople(people: people)).fittingSize
        XCTAssertEqual(stack.height, line, accuracy: 0.5)
        XCTAssertGreaterThan(stack.width, stack.height * 2, "three faces overlapped and a count")
    }
    #endif
}
