import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 137: the bundled fixture written into a store: additive, nothing doubled, a backup first, undone exactly.
@MainActor
final class TodoistImportTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var receiptURL: URL!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
        receiptURL = FileManager.default.temporaryDirectory.appending(path: "todoist-receipt-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: receiptURL)
        container = nil
        context = nil
    }

    private func fetch<M: PersistentModel>(_ type: M.Type) throws -> [M] { try context.fetch(FetchDescriptor<M>()) }

    private func plan() throws -> TodoistPlan {
        TodoistMapping.plan(try TodoistFiles.projects(from: TodoistFixture.files), existing: try TodoistImporter.existing(in: context))
    }

    @discardableResult
    private func run(_ plan: TodoistPlan, backup: @escaping (ModelContext) throws -> Void = { _ in }) async throws -> TodoistImporter.Receipt {
        try await TodoistImporter.run(plan, in: context, backup: backup, receiptURL: receiptURL)
    }

    /// What the person had before: a Group "home base" (another spelling), a label, and a task.
    private func seedMine() throws -> TaskItem {
        let group = Project(name: "home base")
        context.insert(group)
        let label = TaskLabel(name: "Shop")
        context.insert(label)
        let mine = TaskItem(title: "My own task", project: group, labels: [label])
        context.insert(mine)
        try context.save()
        return mine
    }

    func testTheFixtureComesIn() async throws {
        let plan = try plan()
        XCTAssertEqual(plan.taskCount, 7, "six tasks and the sub-task with a repeat of its own")
        XCTAssertEqual(plan.checklistLineCount, 3)
        XCTAssertEqual(plan.subtasksAsTasks, 1)
        XCTAssertEqual(plan.unreadDates.map(\.title), ["Renew the passport"])
        try await run(plan)

        let top = try fetch(TaskItem.self).filter { $0.parent == nil }
        XCTAssertEqual(Set(top.map(\.title)), ["Call the dentist", "Read the lease", "Spring cleaning", "Water the plants",
                                              "Groceries", "Pick up the dry cleaning", "Renew the passport"])
        XCTAssertEqual(top.count, 7)
        let lease = try XCTUnwrap(top.first { $0.title == "Read the lease" })
        XCTAssertEqual(lease.notes, "Pages 3 to 5, the \"pets\" clause")
        let groceries = try XCTUnwrap(top.first { $0.title == "Groceries" })
        XCTAssertEqual(groceries.orderedSubtasks.map(\.title), ["Bread", "Bread › Sourdough", "Eggs"])
        XCTAssertEqual(Set(groceries.labelList.map(\.name)), ["shop", "Errands"])
        XCTAssertEqual(groceries.project?.name, "Home Base")
        let dentist = try XCTUnwrap(top.first { $0.title == "Call the dentist" })
        XCTAssertNil(dentist.project, "Todoist's Inbox is HITList's Inbox")
        XCTAssertNotNil(dentist.dueDate)
        let passport = try XCTUnwrap(top.first { $0.title == "Renew the passport" })
        XCTAssertNil(passport.dueDate)
        XCTAssertTrue(passport.notes.hasPrefix("Todoist date: when the photos come"))
        XCTAssertNotNil(passport.deadline)
        let cleaning = try XCTUnwrap(top.first { $0.title == "Pick up the dry cleaning" })
        XCTAssertNotNil(cleaning.recurrenceRule)
        XCTAssertTrue(cleaning.notes.contains("Under: Groceries"))
    }

    func testAnImportAddsOnlyAndASecondRunDoublesNothing() async throws {
        let mine = try seedMine()
        let first = try plan()
        try await run(first)
        XCTAssertEqual(mine.title, "My own task")
        XCTAssertEqual(mine.project?.name, "home base", "an existing Group is used, never renamed")
        XCTAssertEqual(try fetch(Project.self).count, 1, "Home Base went into the person's own home base")
        XCTAssertEqual(try fetch(TaskLabel.self).filter { $0.name.lowercased() == "shop" }.count, 1)
        let count = try fetch(TaskItem.self).count

        let second = try plan()
        XCTAssertEqual(second.taskCount, 0)
        XCTAssertEqual(second.skipped.count, 7)
        try await run(second)
        XCTAssertEqual(try fetch(TaskItem.self).count, count)
    }

    func testTheBackupRunsBeforeTheFirstRecordAndAFailedOneStopsIt() async throws {
        var tasksAtBackup = -1
        try await run(try plan()) { context in tasksAtBackup = try context.fetch(FetchDescriptor<TaskItem>()).count }
        XCTAssertEqual(tasksAtBackup, 0)

        try await run(try plan()) { _ in }
        struct Refused: Error {}
        let fresh = ModelContainerFactory.preview()
        context = fresh.mainContext
        do {
            try await run(try plan()) { _ in throw Refused() }
            XCTFail("a failed backup stops the import")
        } catch is Refused {}
        XCTAssertEqual(try fetch(TaskItem.self).count, 0)
        _ = fresh
    }

    func testUndoRemovesExactlyWhatWasMade() async throws {
        let mine = try seedMine()
        let receipt = try await run(try plan())
        XCTAssertEqual(TodoistImporter.loadReceipt(at: receiptURL), receipt)
        XCTAssertEqual(receipt.taskIDs.count, 7)
        XCTAssertEqual(receipt.groupIDs.count, 0)
        XCTAssertEqual(Set(try fetch(TaskLabel.self).filter { receipt.labelIDs.contains($0.id) }.map(\.name)), ["phone", "Errands"])

        // Something of the person's own on a label the import made: that label stays.
        let errands = try XCTUnwrap(try fetch(TaskLabel.self).first { $0.name == "Errands" })
        let later = TaskItem(title: "Added after", labels: [errands])
        context.insert(later)
        try context.save()

        let undone = try TodoistImporter.undo(receipt, in: context, receiptURL: receiptURL)
        XCTAssertEqual(undone, TodoistImporter.Undone(tasks: 7, groups: 0, labels: 1, kept: 1))
        XCTAssertEqual(Set(try fetch(TaskItem.self).map(\.title)), ["My own task", "Added after"])
        XCTAssertEqual(mine.labelList.map(\.name), ["Shop"])
        XCTAssertNil(TodoistImporter.loadReceipt(at: receiptURL))
    }

    func testAFewHundredTasksGoInBatchesOfFifty() async throws {
        let rows = (1...230).map { "task,Task number \($0),,4,1" }.joined(separator: "\n")
        let project = try TodoistReader.read(csv: "TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT\n\(rows)\n", fileName: "Big [1].csv")
        let plan = TodoistMapping.plan([project], existing: try TodoistImporter.existing(in: context))
        var reports: [Int] = []
        try await TodoistImporter.run(plan, in: context, backup: { _ in }, receiptURL: receiptURL) { reports.append($0) }
        XCTAssertEqual(reports, [50, 100, 150, 200, 230])
        let tasks = try fetch(TaskItem.self).sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(tasks.count, 230)
        XCTAssertEqual(tasks.first?.title, "Task number 1", "the file's order")
        XCTAssertEqual(tasks.last?.title, "Task number 230")
    }

    /// Round 32 (review 151 B5): an import stopped part way keeps the batches it saved, rolls back the rest, says how
    /// many were written, and leaves a receipt so Undo last import removes them.
    func testAStoppedImportSaysWhatWasWrittenAndCanBeUndone() async throws {
        let rows = (1...120).map { "task,Task number \($0),,4,1" }.joined(separator: "\n")
        let project = try TodoistReader.read(csv: "TYPE,CONTENT,DESCRIPTION,PRIORITY,INDENT\n\(rows)\n", fileName: "Big [1].csv")
        let plan = TodoistMapping.plan([project], existing: try TodoistImporter.existing(in: context))
        struct DiskFull: Error {}
        var saves = 0
        do {
            try await TodoistImporter.run(plan, in: context, backup: { _ in }, receiptURL: receiptURL,
                                          save: { context in
                                              saves += 1
                                              if saves == 2 { throw DiskFull() }
                                              try context.save()
                                          })
            XCTFail("the second batch's save fails")
        } catch let stopped as TodoistImporter.Stopped {
            XCTAssertEqual(stopped.written, 50)
            XCTAssertTrue(stopped.underlying is DiskFull)
        }
        XCTAssertFalse(context.hasChanges, "the unsaved batch is taken back")
        XCTAssertEqual(try fetch(TaskItem.self).count, 50)
        let receipt = try XCTUnwrap(TodoistImporter.loadReceipt(at: receiptURL), "Undo last import is offered")
        XCTAssertEqual(receipt.taskIDs.count, 50)
        XCTAssertEqual(try TodoistImporter.undo(receipt, in: context, receiptURL: receiptURL).tasks, 50)
        XCTAssertEqual(try fetch(TaskItem.self).map(\.title), [], "no blank task left behind by the stopped batch")
        XCTAssertEqual(try fetch(Project.self).count, 0, "the Group it made is empty again and goes")
    }

    func testTheStoppedWordsSayHowManyAndThatUndoRemovesThem() {
        struct Boom: LocalizedError { var errorDescription: String? { "The disk is full." } }
        XCTAssertEqual(TodoistImportModel.stoppedMessage(TodoistImporter.Stopped(written: 0, underlying: Boom())),
                       "Import stopped before anything was written: The disk is full.")
        XCTAssertEqual(TodoistImportModel.stoppedMessage(TodoistImporter.Stopped(written: 1, underlying: Boom())),
                       "Import stopped after 1 task was written: The disk is full. Undo last import removes it.")
        XCTAssertEqual(TodoistImportModel.stoppedMessage(TodoistImporter.Stopped(written: 150, underlying: Boom())),
                       "Import stopped after 150 tasks were written: The disk is full. Undo last import removes them.")
    }

    func testANewGroupIsMadeAndUndone() async throws {
        let receipt = try await run(try plan())
        XCTAssertEqual(try fetch(Project.self).map(\.name), ["Home Base"])
        XCTAssertEqual(receipt.groupIDs.count, 1)
        try TodoistImporter.undo(receipt, in: context, receiptURL: receiptURL)
        XCTAssertEqual(try fetch(Project.self).count, 0)
        XCTAssertEqual(try fetch(TaskItem.self).count, 0)
        XCTAssertEqual(try fetch(TaskLabel.self).count, 0)
    }
}
