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

    // MARK: - The source (item 2)

    /// A task Sam added to `list`, as fetched.
    @discardableResult
    private func samsTask(_ title: String, in list: UUID, store: SharedTasksStore, due: SharedDue? = nil,
                          completedBy: SharedMemberID? = nil, id: UUID = UUID(), later: TimeInterval = 0) -> UUID {
        let t = SharedClock.stamp(now.addingTimeInterval(later))
        let completion = completedBy.map { SharedCompletion(at: t, by: $0, byName: "Sam") }
        store.applyServerTask(SharedTask(id: id, title: Stamped(title, at: t), notes: Stamped("", at: t), priority: Stamped(4, at: t),
                                         due: Stamped(due, at: t), completion: Stamped(completion, at: t), createdAt: t,
                                         createdBy: sam, createdByName: "Sam"),
                              listID: list, scope: .joined, ownerName: sam)
        return id
    }

    func testNothingWhileSharedTasksIsOff() {
        let rows = SharedRows(store: { nil })
        XCTAssertTrue(rows.rows.isEmpty)
        XCTAssertTrue(rows.lists.isEmpty)
        XCTAssertNil(rows.row(UUID()))
    }

    func testTheOffSwitchMeansNoStoreAndSoNoRows() {
        // The real source: a centre that is off (as every test's is) has no store.
        let center = SharedTasksCenter(defaults: UserDefaults(suiteName: "SharedRowsTests-\(UUID())")!, storeName: "HITList-test.store",
                                       isTesting: true)
        XCTAssertNil(center.store)
        XCTAssertTrue(SharedRows(store: { center.store }).rows.isEmpty)
    }

    func testEveryTaskOfEveryListIsARow() throws {
        let store = makeStore()
        let trip = try store.createList(title: "Trip")
        try store.addTask(to: trip.id, title: "Book the cabin", due: due(2))
        try store.addTask(to: trip.id, title: "Pack the tent")
        let groceries = joinedList("Groceries", in: store)
        samsTask("Milk", in: groceries, store: store, due: due(0))
        samsTask("Bread", in: groceries, store: store, completedBy: sam)

        let rows = SharedRows(store: { store })
        XCTAssertEqual(Set(rows.rows.map(\.filterTitle)), ["Book the cabin", "Pack the tent", "Milk", "Bread"])
        XCTAssertEqual(Set(rows.open.map(\.filterTitle)), ["Book the cabin", "Pack the tent", "Milk"])
        XCTAssertEqual(rows.lists.map(\.title), ["Groceries", "Trip"], "by name, as the Shared screen")
        XCTAssertEqual(rows.rows.first { $0.filterTitle == "Milk" }?.filterProjectName, "Groceries")
        XCTAssertTrue(rows.isList(groceries))
        XCTAssertFalse(rows.isList(UUID()))
    }

    func testRowsFollowTheStoreAndRedrawWhatReadsThem() throws {
        let store = makeStore()
        let groceries = joinedList("Groceries", in: store)
        let milk = samsTask("Milk", in: groceries, store: store, due: due(0))
        let rows = SharedRows(store: { store })
        XCTAssertEqual(rows.row(milk)?.task.isCompleted, false)

        // A view reading the rows is told when another member's completion arrives.
        let changed = expectation(description: "the rows' readers are told")
        withObservationTracking { _ = rows.rows } onChange: { changed.fulfill() }
        samsTask("Milk", in: groceries, store: store, due: due(0), completedBy: sam, id: milk, later: 5)
        wait(for: [changed], timeout: 1)
        XCTAssertEqual(rows.row(milk)?.task.isCompleted, true)

        // Leaving the list takes its rows away.
        try store.leave(groceries)
        XCTAssertTrue(rows.rows.isEmpty)
    }

    func testCompletingFromARowStampsItForTheOthersAndUndoReopensIt() throws {
        let store = makeStore()
        var sent: [SharedTasksStore.Change] = []
        store.onChanges = { sent += $0 }
        let groceries = joinedList("Groceries", in: store)
        let milk = samsTask("Milk", in: groceries, store: store, due: due(0))
        let rows = SharedRows(store: { store })

        try rows.setCompleted(true, try XCTUnwrap(rows.row(milk)))
        let done = try XCTUnwrap(store.list(groceries)?.task(milk))
        XCTAssertEqual(done.completion.value?.by, me, "who: me")
        XCTAssertTrue(sent.contains { if case .saveRecord(let ref) = $0 { ref.listID == groceries } else { false } },
                      "sent to the list's zone, so the others see it")

        try rows.setCompleted(false, try XCTUnwrap(rows.row(milk)))
        XCTAssertEqual(store.list(groceries)?.task(milk)?.isCompleted, false)
    }

    func testAViewOnlyMemberIsRefusedWithAWord() throws {
        let store = makeStore()
        let groceries = joinedList("Groceries", in: store, canWrite: false)
        let milk = samsTask("Milk", in: groceries, store: store, due: due(0))
        let rows = SharedRows(store: { store })
        let row = try XCTUnwrap(rows.row(milk))
        XCTAssertThrowsError(try rows.setCompleted(true, row)) { error in
            XCTAssertEqual(error as? SharedRows.Refusal, .cannotChange(list: "Groceries"))
            XCTAssertEqual(error.localizedDescription, "You can see “Groceries” but not change it.")
        }
        XCTAssertThrowsError(try rows.reschedule(row, to: Date()))
        XCTAssertEqual(store.list(groceries)?.task(milk)?.isCompleted, false)
    }

    func testATaskGoneElsewhereIsRefusedQuietly() throws {
        let store = makeStore()
        let trip = try store.createList(title: "Trip")
        let task = try store.addTask(to: trip.id, title: "Book the cabin", due: due(0))
        let rows = SharedRows(store: { store })
        let row = try XCTUnwrap(rows.row(task.id))
        try store.deleteTask(task.id, in: trip.id)
        XCTAssertThrowsError(try rows.setCompleted(true, row)) { XCTAssertEqual($0 as? SharedRows.Refusal, .gone) }
    }

    func testMovingToAnotherDayKeepsTheTimeOfDay() throws {
        let cal = Calendar.current
        let nine = due(0, hour: 9)
        let moved = SharedRows.due(movedTo: cal.date(byAdding: .day, value: 3, to: today)!, from: nine, calendar: cal)
        XCTAssertTrue(moved.hasTime)
        XCTAssertEqual(cal.component(.hour, from: moved.date), 9)
        XCTAssertEqual(cal.startOfDay(for: moved.date), cal.date(byAdding: .day, value: 3, to: today))

        let allDay = SharedRows.due(movedTo: cal.date(byAdding: .hour, value: 30, to: today)!, from: due(0), calendar: cal)
        XCTAssertEqual(allDay, SharedDue(date: cal.date(byAdding: .day, value: 1, to: today)!, hasTime: false))
        XCTAssertEqual(SharedRows.due(movedTo: today, from: nil, calendar: cal), SharedDue(date: today, hasTime: false))

        // Through the store: rescheduled, and nil removes the date.
        let store = makeStore()
        let trip = try store.createList(title: "Trip")
        let task = try store.addTask(to: trip.id, title: "Book the cabin", due: nine)
        let rows = SharedRows(store: { store })
        try rows.reschedule(try XCTUnwrap(rows.row(task.id)), to: cal.date(byAdding: .day, value: 1, to: today)!)
        XCTAssertEqual(store.list(trip.id)?.task(task.id)?.due.value?.hasTime, true)
        try rows.reschedule(try XCTUnwrap(rows.row(task.id)), to: nil)
        XCTAssertNil(store.list(trip.id)?.task(task.id)?.due.value)
    }

    // MARK: - Dragged to another day (item 4)

    func testADroppedSharedTaskMovesToTheDayKeepingItsTime() throws {
        let cal = Calendar.current
        let store = makeStore()
        let trip = try store.createList(title: "Trip")
        let cabin = try store.addTask(to: trip.id, title: "Book the cabin", due: due(0, hour: 9))
        let tent = try store.addTask(to: trip.id, title: "Pack the tent", due: due(1))
        let rows = SharedRows(store: { store })
        let friday = cal.date(byAdding: .day, value: 3, to: today)!

        let result = rows.drop([TaskRescheduling.dragPayload(for: cabin.id), "not a task", UUID().uuidString], on: friday, now: now,
                               calendar: cal)
        XCTAssertEqual(result.moved.map(\.id), [cabin.id], "only the shared task named in the drop")
        XCTAssertNil(result.refusal)
        let moved = try XCTUnwrap(store.list(trip.id)?.task(cabin.id)?.due.value)
        XCTAssertEqual(cal.startOfDay(for: moved.date), friday)
        XCTAssertEqual(cal.component(.hour, from: moved.date), 9, "its time of day kept")
        XCTAssertEqual(store.list(trip.id)?.task(tent.id)?.due.value, due(1), "the other task untouched")
    }

    func testADropOnItsOwnDayOrBeforeTodayMovesNothing() throws {
        let cal = Calendar.current
        let store = makeStore()
        var sent: [SharedTasksStore.Change] = []
        let trip = try store.createList(title: "Trip")
        let cabin = try store.addTask(to: trip.id, title: "Book the cabin", due: due(1))
        store.onChanges = { sent += $0 }
        let rows = SharedRows(store: { store })
        let payload = [TaskRescheduling.dragPayload(for: cabin.id)]

        XCTAssertTrue(rows.drop(payload, on: cal.date(byAdding: .day, value: 1, to: today)!, now: now, calendar: cal).moved.isEmpty,
                      "dropped back where it came from: nothing saved, nothing sent")
        XCTAssertTrue(rows.drop(payload, on: cal.date(byAdding: .day, value: -1, to: today)!, now: now, calendar: cal).moved.isEmpty,
                      "days before today are Overdue's")
        XCTAssertTrue(sent.isEmpty)
    }

    func testADropOnAViewOnlyListIsRefusedWithAWord() throws {
        let cal = Calendar.current
        let store = makeStore()
        let groceries = joinedList("Groceries", in: store, canWrite: false)
        let milk = samsTask("Milk", in: groceries, store: store, due: due(0))
        let rows = SharedRows(store: { store })

        let result = rows.drop([TaskRescheduling.dragPayload(for: milk)], on: cal.date(byAdding: .day, value: 2, to: today)!, now: now,
                               calendar: cal)
        XCTAssertTrue(result.moved.isEmpty)
        XCTAssertEqual(result.refusal, "You can see “Groceries” but not change it.")
        XCTAssertEqual(store.list(groceries)?.task(milk)?.due.value, due(0), "left where it was")
    }

    func testACompletedSharedTaskIsNotMovedByADrop() throws {
        let cal = Calendar.current
        let store = makeStore()
        let groceries = joinedList("Groceries", in: store)
        let bread = samsTask("Bread", in: groceries, store: store, due: due(0), completedBy: sam)
        let rows = SharedRows(store: { store })
        let result = rows.drop([TaskRescheduling.dragPayload(for: bread)], on: cal.date(byAdding: .day, value: 2, to: today)!, now: now,
                               calendar: cal)
        XCTAssertTrue(result.moved.isEmpty)
        XCTAssertNil(result.refusal)
    }

    // MARK: - Counts (item 4)

    func testTheSidebarCountsTakeTheSharedTasksTheListsShow() throws {
        let store = makeStore()
        let trip = try store.createList(title: "Trip")
        try store.addTask(to: trip.id, title: "today", due: due(0))
        try store.addTask(to: trip.id, title: "overdue", due: due(-2))
        try store.addTask(to: trip.id, title: "next week", due: due(7))
        try store.addTask(to: trip.id, title: "undated")
        let groceries = joinedList("Groceries", in: store)
        samsTask("done today", in: groceries, store: store, due: due(0), completedBy: sam)
        let rows = SharedRows(store: { store })
        XCTAssertEqual(rows.inboxCount(now: now), 3, "the dated open ones")
        XCTAssertEqual(rows.todayCount(now: now), 2, "today's and the overdue one")
        XCTAssertEqual(rows.openCount(in: trip.id), 4)
        XCTAssertEqual(rows.openCount(in: groceries), 0)
    }

    func testPriorityAndDeleteGoThroughTheStore() throws {
        let store = makeStore()
        let trip = try store.createList(title: "Trip")
        let task = try store.addTask(to: trip.id, title: "Book the cabin")
        let rows = SharedRows(store: { store })
        try rows.setPriority(1, try XCTUnwrap(rows.row(task.id)))
        XCTAssertEqual(store.list(trip.id)?.task(task.id)?.priority.value, 1)
        try rows.delete(try XCTUnwrap(rows.row(task.id)))
        XCTAssertNil(rows.row(task.id))
    }
}
