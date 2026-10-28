import XCTest
import SwiftData
import SwiftUI
import HITListCore
@testable import HITList

/// `TaskActions.create(from:)` fed by the real `QuickAddParser`.
@MainActor
final class QuickAddCreateTests: XCTestCase {
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

    private func parse(_ text: String) -> QuickAddResult { QuickAddParser().parse(text) }

    @discardableResult
    private func create(_ text: String, project: Project? = nil, label: TaskLabel? = nil) throws -> TaskItem {
        try TaskActions.create(from: parse(text), defaultProject: project, defaultLabel: label, in: context)
    }

    private func fetch<M: PersistentModel>(_ type: M.Type) throws -> [M] { try context.fetch(FetchDescriptor<M>()) }

    func testCreatesProjectAndLabelsOnDemand() throws {
        let parsed = parse("Pay rent tomorrow 5pm p1 #Finance @bills @home every month")
        let task = try TaskActions.create(from: parsed, defaultProject: nil, defaultLabel: nil, in: context)

        XCTAssertEqual(task.title, "Pay rent")
        XCTAssertEqual(task.priority, 1)
        XCTAssertEqual(task.dueDate, parsed.dueDate)
        XCTAssertTrue(task.hasDueTime)
        XCTAssertEqual(task.recurrence, RecurrenceRule.monthly.encoded)
        XCTAssertEqual(task.project?.name, "Finance")
        XCTAssertEqual(Set(task.labelList.map(\.name)), ["bills", "home"])
        XCTAssertEqual(try fetch(Project.self).count, 1)
        XCTAssertEqual(try fetch(TaskLabel.self).count, 2)
        XCTAssertFalse(context.hasChanges, "create saves")
    }

    func testReusesExistingProjectByCaseInsensitiveName() throws {
        let existing = Project(name: "Finance")
        context.insert(existing)
        let task = try create("Pay rent #finance")
        XCTAssertEqual(task.project?.id, existing.id)
        XCTAssertEqual(try fetch(Project.self).count, 1)
    }

    func testReusesExistingLabelByCaseInsensitiveName() throws {
        let existing = TaskLabel(name: "Bills")
        context.insert(existing)
        let task = try create("Pay rent @BILLS")
        XCTAssertEqual(task.labels?.map(\.id), [existing.id])
        XCTAssertEqual(try fetch(TaskLabel.self).count, 1)
    }

    func testTwoTasksShareANewlyCreatedProjectAndLabel() throws {
        let a = try create("One #Errands @car")
        let b = try create("Two #errands @Car")
        XCTAssertEqual(a.project?.id, b.project?.id)
        XCTAssertEqual(a.labels?.map(\.id), b.labels?.map(\.id))
        XCTAssertEqual(try fetch(Project.self).count, 1)
        XCTAssertEqual(try fetch(TaskLabel.self).count, 1)
    }

    func testNewProjectsGetSuccessiveSortOrdersAndPaletteColors() throws {
        try create("a #One")
        try create("b #Two")
        let projects = try fetch(Project.self).sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(projects.map(\.name), ["One", "Two"])
        XCTAssertEqual(projects.map(\.sortOrder), [0, 1])
        XCTAssertEqual(projects.map(\.colorHex), [Color.palette[0].hex, Color.palette[1].hex])
    }

    func testDefaultProjectAppliesOnlyWithoutAHashtag() throws {
        let inbox = Project(name: "Inbox")
        context.insert(inbox)
        XCTAssertEqual(try create("Plain task", project: inbox).project?.id, inbox.id)
        XCTAssertEqual(try create("Tagged #Work", project: inbox).project?.name, "Work")
    }

    func testDefaultLabelIsAddedOnceAlongsideParsedLabels() throws {
        let waiting = TaskLabel(name: "waiting")
        context.insert(waiting)
        let plain = try create("Call Bob @phone", label: waiting)
        XCTAssertEqual(Set(plain.labelList.map(\.name)), ["phone", "waiting"])
        let dup = try create("Call Ann @Waiting", label: waiting)
        XCTAssertEqual(dup.labels?.map(\.id), [waiting.id])
    }

    func testEmptyTitleThrowsAndCreatesNothing() throws {
        XCTAssertThrowsError(try create("   ")) { error in
            XCTAssertEqual(error.localizedDescription, TaskActions.ActionError.emptyTitle.localizedDescription)
        }
        XCTAssertEqual(try fetch(TaskItem.self).count, 0)
    }

    func testEveryThreeDaysQuickAddCreatesRecurringTask() throws {
        let task = try create("Water plants every 3 days")
        XCTAssertEqual(task.recurrenceRule, RecurrenceRule(frequency: .daily, interval: 3))
        XCTAssertEqual(task.recurrence, "daily;3")
    }
}
