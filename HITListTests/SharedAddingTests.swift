import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 64, item 6: adding to Shared Tasks from quick add (`#Shared`, the Group chip and card), from your task's Group
/// card, and on the Mac board (its card is the quick add). With one set of people the task goes there; with several, to
/// the one used last. In-memory stores only.
@MainActor
final class SharedAddingTests: XCTestCase {
    private let me = "_me000000000000000000000000000000"
    private let sam = "_sam00000000000000000000000000000"
    private let now = Date()

    private func makeStore() -> SharedTasksStore {
        let store = SharedTasksStore(persistence: .memory)
        store.setMe(me)
        return store
    }

    private func parse(_ text: String, groups: [String] = ["Work"]) -> QuickAddResult {
        QuickAddParser(now: now, knownProjects: groups + [SharedTasksGroup.name]).parse(text)
    }

    // MARK: - Quick add's words

    func testHashSharedAndTheChipNameSharedTasks() {
        for text in ["Milk #Shared", "Milk #shared tomorrow", "Milk #\"Shared Tasks\"", "Milk #Shared Tasks"] {
            let result = parse(text)
            XCTAssertEqual(SharedTasksGroup.resolve(result.projectName, groups: ["Work"]), .sharedTasks, text)
            XCTAssertEqual(result.title, "Milk", text)
        }
        XCTAssertEqual(SharedTasksGroup.resolve(parse("Milk #Work").projectName, groups: ["Work"]), .group("Work"))
    }

    func testTheGroupScreensCardAddsToSharedTasks() {
        var draft = QuickAddDraft(context: .sharedTasks)
        draft.text = "Book the cabin"
        let result = draft.result(QuickAddParser(now: now, knownProjects: [SharedTasksGroup.name]))
        XCTAssertEqual(SharedTasksGroup.resolve(result.projectName, groups: []), .sharedTasks)
        XCTAssertEqual(QuickAddContext.sharedTasks, .project(name: "Shared Tasks", id: SharedTasksGroup.id))
    }

    // MARK: - Where it goes

    func testWithOneSetOfPeopleItGoesThere() throws {
        let store = makeStore()
        let only = try store.createList(title: "Shared Tasks")
        let rows = SharedRows(store: { store })
        let row = try TaskActions.createShared(from: parse("Milk #Shared p2 tomorrow"), notes: "Oat", subtasks: [], in: rows)
        XCTAssertEqual(row.listID, only.id)
        let task = try XCTUnwrap(store.list(only.id)?.task(row.id))
        XCTAssertEqual(task.title.value, "Milk")
        XCTAssertEqual(task.notes.value, "Oat")
        XCTAssertEqual(task.priority.value, 2)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        XCTAssertEqual(task.due.value, SharedTasksStore.normalized(SharedDue(date: tomorrow, hasTime: false)), "tomorrow, kept as its day (brief 82)")
    }

    func testWithSeveralItGoesToTheOneUsedLast() throws {
        let store = makeStore()
        let first = try store.createList(title: "Shared Tasks")
        let second = try store.createList(title: "Shared Tasks")
        try store.addTask(to: second.id, title: "Tent")
        let rows = SharedRows(store: { store })
        XCTAssertEqual(try rows.listForNewTask().id, second.id, "the set I added to last")
        let moved = try rows.move(XCTUnwrap(rows.row(store.list(second.id)!.tasks[0].id)), to: first.id)
        XCTAssertEqual(moved.listID, first.id)
        XCTAssertEqual(try rows.listForNewTask().id, first.id, "moving one there with the people row counts as using it")
        XCTAssertEqual(try TaskActions.createShared(from: parse("Milk #Shared"), notes: "", subtasks: [], in: rows).listID, first.id)
    }

    func testTheFirstSharedTaskMakesTheSetItGoesIn() throws {
        let store = makeStore()
        let rows = SharedRows(store: { store })
        let row = try TaskActions.createShared(from: parse("Milk #Shared"), notes: "", subtasks: ["Oat", "Soy"], in: rows)
        XCTAssertEqual(store.lists.count, 1)
        XCTAssertEqual(store.lists[0].title, "Shared Tasks")
        XCTAssertEqual(store.list(row.listID)?.task(row.id)?.notes.value, "• Oat\n• Soy", "a shared task has no sub-tasks: they go in its description")
    }

    func testAViewOnlySetIsNeverTheOneItGoesTo() throws {
        let store = makeStore()
        let id = UUID()
        let t = SharedClock.stamp(now)
        store.applyServerList(SharedListFields(title: Stamped("Sam's", at: t), colorHex: Stamped("#4FD1E8", at: t), createdAt: t),
                              systemFields: nil, listID: id, scope: .joined, ownerName: sam)
        store.applyShare(SharedShareInfo(participants: [
            SharedParticipant(userID: sam, name: "Sam", contact: nil, role: .owner, status: .accepted, canWrite: true, isCurrentUser: false),
            SharedParticipant(userID: me, name: "George", contact: nil, role: .participant, status: .accepted, canWrite: false, isCurrentUser: true),
        ], url: nil, archive: nil), listID: id, scope: .joined, ownerName: sam)
        let rows = SharedRows(store: { store })
        let list = try rows.listForNewTask()
        XCTAssertNotEqual(list.id, id)
        XCTAssertTrue(list.isOwned, "a set of my own, made for it")
    }

    func testSwitchedOffItSaysWhereToSwitchItOn() {
        let rows = SharedRows(store: { nil })
        XCTAssertThrowsError(try TaskActions.createShared(from: parse("Milk #Shared"), notes: "", subtasks: [], in: rows)) { error in
            XCTAssertEqual(error as? SharedRows.Refusal, .off)
            XCTAssertEqual(error.localizedDescription, "Shared Tasks is off. Switch it on in the Shared Tasks Group.")
        }
    }

    // MARK: - A task of yours into Shared Tasks (its Group card)

    func testPickingSharedTasksForATaskOfYoursMovesItThere() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        let work = Project(name: "Work")
        context.insert(work)
        let day = Calendar.current.startOfDay(for: now)
        let task = TaskItem(title: "Book the cabin", notes: "Lake", priority: 1, dueDate: day.addingTimeInterval(3600 * 17),
                            hasDueTime: true, project: work)
        context.insert(task)
        try TaskActions.addSubtasks(["Call them"], to: task, in: context)
        try context.save()
        let store = makeStore()
        let rows = SharedRows(store: { store })

        let row = try TaskActions.moveToSharedTasks(task, in: context, rows: rows)
        let shared = try XCTUnwrap(store.list(row.listID)?.task(row.id))
        XCTAssertEqual(shared.title.value, "Book the cabin")
        XCTAssertEqual(shared.notes.value, "Lake\n\n• Call them")
        XCTAssertEqual(shared.priority.value, 1)
        XCTAssertEqual(shared.due.value, SharedDue(date: day.addingTimeInterval(3600 * 17), hasTime: true))
        let left = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertTrue(left.isEmpty, "it moved: yours and its sub-tasks are gone")
    }
}
