import XCTest
import SwiftUI
import HITListCore
@testable import HITList

/// Brief 64, item 4: a shared task opens in the editor George knows, through the popouts on every platform (the
/// panel `PopoutHost` draws on the Mac, the same sheet on iPhone), with the Discard rules of a task of yours, and its
/// people row can move it to another set of people. In-memory stores only.
@MainActor
final class SharedEditorTests: XCTestCase {
    private let me = "_me000000000000000000000000000000"
    private let sam = "_sam00000000000000000000000000000"
    private let now = Date()

    private func makeStore() -> SharedTasksStore {
        let store = SharedTasksStore(persistence: .memory)
        store.setMe(me)
        return store
    }

    private func controller(_ rows: SharedRows) -> PopoutController {
        PopoutController(draftDefaults: UserDefaults(suiteName: "SharedEditorTests-\(UUID())")!, center: NotificationCenter(),
                         sharedRows: rows)
    }

    // MARK: - Through the popouts

    func testAnyListOpensTheOneEditorThePopoutsDraw() {
        let rows = SharedRows(store: { nil })
        let popouts = controller(rows)
        let ref = SharedTaskRef(taskID: UUID(), listID: UUID())
        popouts.listSelection.wrappedValue = .shared(ref)
        XCTAssertEqual(popouts.state.sharedTask, ref, "the host draws it, not the list")
        XCTAssertEqual(popouts.listSelection.wrappedValue, .shared(ref), "the row stays highlighted while it is open")
        popouts.listSelection.wrappedValue = nil
        XCTAssertNil(popouts.state.sharedTask)
        popouts.openShared(ref)
        XCTAssertEqual(popouts.state.sharedTask, ref)
        popouts.closeSharedTask()
        XCTAssertFalse(popouts.state.isSharedTaskOpen)
    }

    func testCompletingFromTheEditorShowsTheToastAndUndoReopensIt() throws {
        let store = makeStore()
        let list = try store.createList(title: "Shared Tasks")
        let task = try store.addTask(to: list.id, title: "Book the cabin")
        let rows = SharedRows(store: { store })
        let popouts = controller(rows)
        let row = try XCTUnwrap(rows.row(task.id))
        popouts.openShared(SharedTaskRef(row))
        try popouts.completeShared(row)
        XCTAssertTrue(try XCTUnwrap(store.list(list.id)?.task(task.id)).isCompleted)
        XCTAssertFalse(popouts.state.isSharedTaskOpen, "the editor closes with the toast")
        XCTAssertTrue(popouts.toast.isVisible)
        let container = ModelContainerFactory.preview()
        popouts.undoCompletions(in: container.mainContext)
        XCTAssertFalse(try XCTUnwrap(store.list(list.id)?.task(task.id)).isCompleted, "Undo reopens it for everyone")
    }

    // MARK: - The draft (Discard rules)

    func testTypingAsksDiscardAndPickedValuesDoNot() throws {
        let store = makeStore()
        let list = try store.createList(title: "Shared Tasks")
        let task = try store.addTask(to: list.id, title: "Book the cabin", notes: "Two nights")
        var draft = SharedTaskDraft(task: task)
        XCTAssertFalse(draft.hasPendingChanges(for: task))
        XCTAssertEqual(draft.closeStep(for: task, asking: false), .close)
        draft.title = "Book the cabin by Friday"
        XCTAssertTrue(draft.hasPendingChanges(for: task))
        XCTAssertEqual(draft.closeStep(for: task, asking: false), .askDiscard)
        XCTAssertEqual(draft.closeStep(for: task, asking: true), .close, "× again is the Discard")
        draft.title = "   "
        XCTAssertFalse(draft.hasPendingChanges(for: task), "a blank title keeps the stored one")
        draft.notes = "Two nights "
        XCTAssertFalse(draft.hasPendingChanges(for: task), "trailing space isn't a change")
    }

    func testConfirmSavesTheTypingThroughTheSharedStore() throws {
        let store = makeStore()
        let list = try store.createList(title: "Shared Tasks")
        let task = try store.addTask(to: list.id, title: "Book the cabin")
        let rows = SharedRows(store: { store })
        var draft = SharedTaskDraft(task: task)
        draft.title = "Book the cabin\nfor two"
        draft.notes = "  The one by the lake "
        XCTAssertTrue(try draft.commit(to: XCTUnwrap(rows.row(task.id)), in: rows))
        let saved = try XCTUnwrap(store.list(list.id)?.task(task.id))
        XCTAssertEqual(saved.title.value, "Book the cabin for two", "one line, as yours")
        XCTAssertEqual(saved.notes.value, "The one by the lake")
        XCTAssertFalse(try draft.commit(to: XCTUnwrap(rows.row(task.id)), in: rows), "nothing new: nothing written")
    }

    // MARK: - The date row and the people row

    func testTheDateRowSetsADayAndATimeAndTakesThemAway() throws {
        let store = makeStore()
        let list = try store.createList(title: "Shared Tasks")
        let task = try store.addTask(to: list.id, title: "Book the cabin")
        let rows = SharedRows(store: { store })
        let day = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: now))!
        try rows.reschedule(XCTUnwrap(rows.row(task.id)), to: day)
        try rows.setTime(XCTUnwrap(rows.row(task.id)), hour: 17, minute: 30)
        let due = try XCTUnwrap(store.list(list.id)?.task(task.id)?.due.value)
        XCTAssertTrue(due.hasTime)
        XCTAssertEqual(Calendar.current.dateComponents([.hour, .minute], from: due.date), DateComponents(hour: 17, minute: 30))
        XCTAssertTrue(Calendar.current.isDate(due.date, inSameDayAs: day))
        try rows.clearTime(XCTUnwrap(rows.row(task.id)))
        XCTAssertEqual(store.list(list.id)?.task(task.id)?.due.value, SharedTasksStore.normalized(SharedDue(date: day, hasTime: false)))
        try rows.setTime(XCTUnwrap(rows.row(task.id)), hour: 9, minute: 0)
        try rows.reschedule(XCTUnwrap(rows.row(task.id)), to: nil)
        XCTAssertNil(store.list(list.id)?.task(task.id)?.due.value)
    }

    func testThePeopleRowMovesATaskToAnotherSetOfPeople() throws {
        let store = makeStore()
        let mine = try store.createList(title: "Shared Tasks")
        let other = try store.createList(title: "Shared Tasks")
        let day = Calendar.current.startOfDay(for: now)
        let task = try store.addTask(to: mine.id, title: "Book the cabin", notes: "Lake", priority: 2,
                                     due: SharedDue(date: day, hasTime: false))
        let rows = SharedRows(store: { store })
        let moved = try rows.move(XCTUnwrap(rows.row(task.id)), to: other.id)
        XCTAssertNil(store.list(mine.id)?.task(task.id), "gone from the first set")
        let copy = try XCTUnwrap(store.list(other.id)?.task(moved.id))
        XCTAssertEqual(copy.title.value, "Book the cabin")
        XCTAssertEqual(copy.notes.value, "Lake")
        XCTAssertEqual(copy.priority.value, 2)
        XCTAssertEqual(copy.due.value, SharedTasksStore.normalized(SharedDue(date: day, hasTime: false)))
        XCTAssertEqual(moved.listID, other.id)
        XCTAssertEqual(try rows.move(XCTUnwrap(rows.row(moved.id)), to: other.id).id, moved.id, "already there: nothing moves")
    }
}
