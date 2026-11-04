import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Siri and Shortcuts (brief 46): the logic behind each App Intent, run against an in-memory container.
@MainActor
final class IntentsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    /// Wednesday 2026-11-04 10:00 local time.
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        IntentStore.reset()
        container = nil
        context = nil
    }

    private func fetch<M: PersistentModel>(_ type: M.Type) throws -> [M] { try context.fetch(FetchDescriptor<M>()) }

    private func day(_ offset: Int, hour: Int? = nil, minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        guard let hour else { return start }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start)!
    }

    // MARK: Add Task

    func testAddTaskParsesLikeTheQuickAddCard() throws {
        let added = try IntentActions.addTask("Buy milk tom 5pm p1 #Home @errands", group: nil, in: context, now: now)
        let task = try XCTUnwrap(try fetch(TaskItem.self).first)
        XCTAssertEqual(added.id, task.id)
        XCTAssertEqual(task.title, "Buy milk")
        XCTAssertEqual(task.priority, 1)
        XCTAssertEqual(task.dueDate, day(1, hour: 17))
        XCTAssertTrue(task.hasDueTime)
        XCTAssertEqual(task.project?.name, "Home")
        XCTAssertEqual(task.labelList.map(\.name), ["errands"])
        XCTAssertFalse(context.hasChanges, "the task is saved, so CloudKit mirrors it")
    }

    func testAddTaskDialogNamesTheTaskAndItsDay() throws {
        let timed = try IntentActions.addTask("Buy milk tomorrow 5pm", group: nil, in: context, now: now)
        let time = day(1, hour: 17).formatted(.dateTime.hour().minute())
        XCTAssertEqual(timed.dialog, "Added ‘Buy milk’ for tomorrow \(time)")
        let today = try IntentActions.addTask("Call Sam today", group: nil, in: context, now: now)
        XCTAssertEqual(today.dialog, "Added ‘Call Sam’ for today")
        let undated = try IntentActions.addTask("Read a book", group: nil, in: context, now: now)
        XCTAssertEqual(undated.dialog, "Added ‘Read a book’")
    }

    func testAddTaskUnderstandsDictatedTimes() throws {
        // Siri writes "5 PM" and "5:30 p.m."; the card's parser must read both.
        try IntentActions.addTask("Buy milk tomorrow at 5 PM", group: nil, in: context, now: now)
        try IntentActions.addTask("Pick up Sam tomorrow at 5:30 p.m.", group: nil, in: context, now: now)
        let tasks = try fetch(TaskItem.self).sorted { $0.title < $1.title }
        XCTAssertEqual(tasks.map(\.title), ["Buy milk", "Pick up Sam"])
        XCTAssertEqual(tasks.map(\.dueDate), [day(1, hour: 17), day(1, hour: 17, minute: 30)])
        XCTAssertTrue(tasks.allSatisfy(\.hasDueTime))
    }

    func testAddTaskPutsTheTaskInTheChosenGroupUnlessTheTextNamesOne() throws {
        let home = Project(name: "Home")
        let work = Project(name: "Work")
        context.insert(home)
        context.insert(work)
        try context.save()

        try IntentActions.addTask("Fix the tap", group: home.id, in: context, now: now)
        try IntentActions.addTask("Send report #Work", group: home.id, in: context, now: now)
        let tasks = try fetch(TaskItem.self)
        XCTAssertEqual(tasks.first { $0.title == "Fix the tap" }?.project?.id, home.id)
        XCTAssertEqual(tasks.first { $0.title == "Send report" }?.project?.id, work.id, "a typed #Group wins, as on the card")
        XCTAssertEqual(try fetch(Project.self).count, 2)
    }

    func testAddTaskWithoutATitleAddsNothing() throws {
        XCTAssertThrowsError(try IntentActions.addTask("   p1 tomorrow ", group: nil, in: context, now: now)) { error in
            XCTAssertEqual(error as? IntentFailure, .emptyTitle)
        }
        XCTAssertTrue(try fetch(TaskItem.self).isEmpty)
    }

    func testAddTaskWithAGroupThatIsGoneSaysSo() throws {
        XCTAssertThrowsError(try IntentActions.addTask("Fix the tap", group: UUID(), in: context, now: now)) { error in
            XCTAssertEqual(error as? IntentFailure, .groupNotFound)
        }
        XCTAssertTrue(try fetch(TaskItem.self).isEmpty)
    }

    func testIntentsUseTheAppsOwnContainer() throws {
        XCTAssertThrowsError(try IntentStore.context()) { error in
            XCTAssertEqual(error as? IntentFailure, .appNotReady)
        }
        IntentStore.register(container)
        XCTAssertTrue(try IntentStore.context() === container.mainContext,
                      "one container per store: intents write through the app's main context")
    }

    func testGroupQueryListsAndFindsGroups() throws {
        let home = Project(name: "Home", sortOrder: 1)
        let work = Project(name: "Work", sortOrder: 0)
        context.insert(home)
        context.insert(work)
        try context.save()
        XCTAssertEqual(try IntentActions.groups(in: context).map(\.name), ["Work", "Home"])
        XCTAssertEqual(try IntentActions.groups(matching: "ho", in: context).map(\.name), ["Home"])
        XCTAssertEqual(try IntentActions.groups(ids: [home.id], in: context).map(\.name), ["Home"])
    }
}
