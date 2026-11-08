import XCTest
import HITListCore
@testable import HITList

/// Brief 62: shared tasks are rows of your lists. A shared task with its list (`SharedRow`) is a task to every list
/// rule, its list's name standing for a Group's. In-memory stores only: nothing here touches CloudKit or the task store.
@MainActor
final class SharedRowsTests: XCTestCase {
    private let me = "_me000000000000000000000000000000"
    private let sam = "_sam00000000000000000000000000000"
    private let now = Date()
    private var today: Date { Calendar.current.startOfDay(for: now) }

    private func makeStore() -> SharedTasksStore {
        let store = SharedTasksStore(persistence: .memory)
        store.setMe(me)
        return store
    }

    /// A list Sam owns, joined by me, as fetched; `canWrite` as Sam's share says.
    @discardableResult
    private func joinedList(_ title: String, in store: SharedTasksStore, canWrite: Bool = true) -> UUID {
        let id = UUID()
        let t = SharedClock.stamp(now)
        store.applyServerList(SharedListFields(title: Stamped(title, at: t), colorHex: Stamped("#4FD1E8", at: t), createdAt: t),
                              systemFields: nil, listID: id, scope: .joined, ownerName: sam)
        store.applyShare(SharedShareInfo(participants: [
            SharedParticipant(userID: sam, name: "Sam", contact: nil, role: .owner, status: .accepted, canWrite: true, isCurrentUser: false),
            SharedParticipant(userID: me, name: "George", contact: nil, role: .participant, status: .accepted, canWrite: canWrite,
                              isCurrentUser: true),
        ], url: nil, archive: nil), listID: id, scope: .joined, ownerName: sam)
        return id
    }

    private func due(_ days: Int, hour: Int? = nil) -> SharedDue {
        let day = Calendar.current.date(byAdding: .day, value: days, to: today)!
        guard let hour else { return SharedDue(date: day, hasTime: false) }
        return SharedDue(date: Calendar.current.date(byAdding: .hour, value: hour, to: day)!, hasTime: true)
    }

    // MARK: - A shared task as a task (item 1)

    func testASharedTaskIsATaskInItsListsGroup() throws {
        let store = makeStore()
        let trip = try store.createList(title: "Trip")
        let task = try store.addTask(to: trip.id, title: "Book the cabin", notes: "Two nights", priority: 2, due: due(0, hour: 9))
        let row = SharedRow(task: task, list: try XCTUnwrap(store.list(trip.id)))
        XCTAssertEqual(row.id, task.id)
        XCTAssertEqual(row.filterTitle, "Book the cabin")
        XCTAssertEqual(row.filterNotes, "Two nights")
        XCTAssertEqual(row.filterPriority, 2)
        XCTAssertEqual(row.filterDueDate, task.due.value?.date)
        XCTAssertTrue(row.filterHasDueTime)
        XCTAssertFalse(row.filterIsCompleted)
        XCTAssertEqual(row.filterProjectName, "Trip", "its list's name is its Group name")
        XCTAssertEqual(row.rowGroupID, trip.id)
        XCTAssertEqual(row.filterCreatedDate, task.createdAt)
        XCTAssertTrue(row.filterLabelNames.isEmpty)
        XCTAssertFalse(row.filterIsRecurring)
        XCTAssertFalse(row.filterIsSubtask)
        XCTAssertTrue(row.canWrite, "my own list")
        XCTAssertEqual(TaskListRow.shared(row).group, .shared(trip.id))
    }

    func testAnUntitledListStillNamesAGroupSoItsUndatedTasksStayInIt() throws {
        let store = makeStore()
        let list = joinedList("", in: store)
        let task = try store.addTask(to: list, title: "Someday")
        let row = SharedRow(task: task, list: try XCTUnwrap(store.list(list)))
        XCTAssertEqual(row.filterProjectName, SharedRow.untitled)
        XCTAssertFalse(TaskOrdering.isInInbox(row, now: now), "undated: only on its list's screen")
    }

    func testAMemberWhoCannotWriteGetsARowTheyCannotChange() throws {
        let store = makeStore()
        let list = joinedList("Groceries", in: store, canWrite: false)
        let t = SharedClock.stamp(now)
        store.applyServerTask(SharedTask(id: UUID(), title: Stamped("Milk", at: t), notes: Stamped("", at: t), priority: Stamped(4, at: t),
                                         due: Stamped(due(0), at: t), completion: Stamped(nil, at: t), createdAt: t,
                                         createdBy: sam, createdByName: "Sam"),
                              listID: list, scope: .joined, ownerName: sam)
        let shared = try XCTUnwrap(store.list(list))
        XCTAssertFalse(SharedRow(task: shared.tasks[0], list: shared).canWrite)
    }
}
