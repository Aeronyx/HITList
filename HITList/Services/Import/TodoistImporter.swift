import Foundation
import SwiftData
import SwiftUI
import OSLog
import HITListCore

/// Brief 137: writes a `TodoistPlan` into the store, additively. It makes Groups, labels and tasks and never edits
/// or deletes what was there. A local backup is taken before the first record (on the real store; a Debug side store
/// has none to take), tasks are made the way `TaskActions.create` and `addSubtask` make them, in batches with one save
/// each, and the ids of what was made go in a receipt on this device (not synced) so "Undo last import" can remove
/// exactly those. The sync mirror is left alone: the saves are ordinary saves.
@MainActor
enum TodoistImporter {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "storage")

    struct Receipt: Codable, Equatable {
        var date: Date
        var taskIDs: [UUID]
        /// Checklist lines (sub-tasks), removed with their task.
        var checklistIDs: [UUID]
        var groupIDs: [UUID]
        var labelIDs: [UUID]

        var summary: String {
            var parts = [TodoistMapping.count(taskIDs.count, "task")]
            if !groupIDs.isEmpty { parts.append(TodoistMapping.count(groupIDs.count, "Group")) }
            if !labelIDs.isEmpty { parts.append(TodoistMapping.count(labelIDs.count, "label")) }
            return parts.joined(separator: ", ")
        }
    }

    struct Undone: Equatable {
        var tasks = 0
        var groups = 0
        var labels = 0
        /// Groups and labels the import made that now hold something of the person's own, so they stay.
        var kept = 0
    }

    static let batchSize = 50

    /// One receipt per store, in the app's own Application Support (never the App Group, never iCloud): a Debug run
    /// on a side store keeps its own.
    nonisolated static var receiptURL: URL {
        let store = ModelContainerFactory.storeName.replacingOccurrences(of: ".store", with: "")
        return URL.applicationSupportDirectory.appending(path: "Todoist import (\(store)).json")
    }

    static func loadReceipt(at url: URL = receiptURL) -> Receipt? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Receipt.self, from: data)
    }

    static func saveReceipt(_ receipt: Receipt?, at url: URL = receiptURL) throws {
        guard let receipt else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
    }

    /// What the plan needs to know of the store: Group and label names, and every open task's title and Group.
    static func existing(in context: ModelContext) throws -> TodoistExisting {
        let groups = try context.fetch(FetchDescriptor<Project>()).map(\.name)
        let labels = try context.fetch(FetchDescriptor<TaskLabel>()).map(\.name)
        let open = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted }))
            .map { TodoistExisting.OpenTask(title: $0.title, groupName: $0.project?.name) }
        return TodoistExisting(groupNames: groups, labelNames: labels, openTasks: open)
    }

    /// The local backup before the first write: on the real store only (`LocalBackup.run` refuses a side store).
    static func backUpFirst(context: ModelContext) throws {
        guard ModelContainerFactory.isMainStoreOpen else {
            log.info("Todoist import: no backup on \(ModelContainerFactory.openedStoreDescription, privacy: .public)")
            return
        }
        try LocalBackup.run(context: context)
    }

    /// Writes the plan. `backup` runs before the first record is made; a throw stops the import with nothing written.
    /// `progress` is told how many tasks are made after each batch.
    static func run(_ plan: TodoistPlan, in context: ModelContext, now: Date = .now,
                    backup: (ModelContext) throws -> Void = backUpFirst,
                    receiptURL: URL = receiptURL,
                    progress: (Int) -> Void = { _ in }) async throws -> Receipt {
        try backup(context)
        var receipt = Receipt(date: now, taskIDs: [], checklistIDs: [], groupIDs: [], labelIDs: [])

        var groups: [String: Project] = [:]
        var allGroups = try context.fetch(FetchDescriptor<Project>())
        for group in allGroups where groups[group.name.lowercased()] == nil { groups[group.name.lowercased()] = group }
        var labels: [String: TaskLabel] = [:]
        for label in try context.fetch(FetchDescriptor<TaskLabel>()) where labels[label.name.lowercased()] == nil {
            labels[label.name.lowercased()] = label
        }

        func group(named name: String) -> Project {
            if let found = groups[name.lowercased()] { return found }
            // As `TaskActions.findOrCreateProject` makes one: the palette's next colour, at the end.
            let made = Project(name: name, colorHex: Color.palette[allGroups.count % Color.palette.count].hex, sortOrder: allGroups.count)
            context.insert(made)
            allGroups.append(made)
            groups[name.lowercased()] = made
            receipt.groupIDs.append(made.id)
            return made
        }
        func label(named name: String) -> TaskLabel {
            if let found = labels[name.lowercased()] { return found }
            let made = TaskLabel(name: name)
            context.insert(made)
            labels[name.lowercased()] = made
            receipt.labelIDs.append(made.id)
            return made
        }

        var made = 0
        for (index, planned) in plan.tasks.enumerated() {
            // As `TaskActions.create` makes a task (title clamped, deadline at its day's start), notes and checklist added.
            let task = TaskItem(title: TaskLimits.clampedTitle(planned.title), notes: planned.notes, priority: planned.priority.rawValue,
                                dueDate: planned.due, hasDueTime: planned.hasDueTime,
                                project: planned.groupName.map(group(named:)), labels: planned.labels.map(label(named:)),
                                recurrence: planned.recurrence)
            if let deadline = planned.deadline { task.deadline = Calendar.current.startOfDay(for: deadline) }
            // The file's order, a millisecond apart, for lists that sort by when a task was made.
            task.createdAt = now.addingTimeInterval(Double(index) / 1000)
            task.updatedAt = task.createdAt
            context.insert(task)
            receipt.taskIDs.append(task.id)
            // As `TaskActions.addSubtask` makes a checklist line: the title on one line, the parent's Group, in order.
            for (order, line) in planned.checklist.enumerated() {
                let subtask = TaskItem(title: TaskLimits.clampedTitle(TaskLimits.singleLine(line)), project: task.project)
                subtask.sortOrder = order
                context.insert(subtask)
                subtask.parent = task
                receipt.checklistIDs.append(subtask.id)
            }
            made += 1
            if made % batchSize == 0 {
                try context.save()
                progress(made)
                await Task.yield()
            }
        }
        try context.save()
        progress(made)
        try saveReceipt(receipt, at: receiptURL)
        log.notice("Todoist import: \(receipt.summary, privacy: .public)")
        return receipt
    }

    /// Removes exactly what the receipt names: its tasks (their checklists with them), then the Groups and labels it
    /// made that hold nothing else now. The receipt goes with them.
    @discardableResult
    static func undo(_ receipt: Receipt, in context: ModelContext, receiptURL: URL = receiptURL) throws -> Undone {
        var undone = Undone()
        let taskIDs = Set(receipt.taskIDs + receipt.checklistIDs)
        // On HITList's own sync engine a device that suddenly lacks most of what iCloud holds is stopped and asked
        // (the mass-deletion hold). The person asked for exactly this, a moment ago, with the counts in front of
        // them: the app vouches for these, before the save that removes them (round 28, the sync review's finding 12).
        var vouched = Set(taskIDs.map { SyncSchema.key(SyncSchema.taskItem, id: $0) })
        vouched.formUnion(receipt.groupIDs.map { SyncSchema.key(SyncSchema.project, id: $0) })
        vouched.formUnion(receipt.labelIDs.map { SyncSchema.key(SyncSchema.taskLabel, id: $0) })
        SyncEngine.vouchForDeletions(vouched)
        let tasks = try context.fetch(FetchDescriptor<TaskItem>()).filter { taskIDs.contains($0.id) }
        // Top tasks first: their checklists go with them (cascade); a line moved elsewhere goes on its own.
        for task in tasks where task.parent == nil || !taskIDs.contains(task.parent!.id) {
            if receipt.taskIDs.contains(task.id) { undone.tasks += 1 }
            context.delete(task)
        }
        try context.save()

        let groupIDs = Set(receipt.groupIDs)
        for group in try context.fetch(FetchDescriptor<Project>()) where groupIDs.contains(group.id) {
            if (group.tasks ?? []).isEmpty { context.delete(group); undone.groups += 1 } else { undone.kept += 1 }
        }
        let labelIDs = Set(receipt.labelIDs)
        for label in try context.fetch(FetchDescriptor<TaskLabel>()) where labelIDs.contains(label.id) {
            if (label.tasks ?? []).isEmpty { context.delete(label); undone.labels += 1 } else { undone.kept += 1 }
        }
        try context.save()
        try saveReceipt(nil, at: receiptURL)
        log.notice("Todoist import undone: \(undone.tasks) tasks, \(undone.groups) Groups, \(undone.labels) labels")
        return undone
    }
}
