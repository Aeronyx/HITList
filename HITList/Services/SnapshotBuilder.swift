import Foundation
import SwiftData
import HITListCore

/// Converts between the SwiftData store and the portable `Snapshot` format.
enum SnapshotBuilder {
    static func deviceName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }

    /// Everything `context` holds, as a `Snapshot`. On the main actor for a context of the main actor's; the daily
    /// backup calls it off the main thread with a context of its own and the device's name read before
    /// (`LocalBackup.runIfDue`: `UIDevice` is the main actor's).
    @MainActor
    static func build(from context: ModelContext) throws -> Snapshot {
        try build(from: context, deviceName: deviceName())
    }

    nonisolated static func build(from context: ModelContext, deviceName: String) throws -> Snapshot {
        let projects = try context.fetch(FetchDescriptor<Project>())
        let labels = try context.fetch(FetchDescriptor<TaskLabel>())
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let filters = try context.fetch(FetchDescriptor<SavedFilter>())
        let switchboards = try context.fetch(FetchDescriptor<Switchboard>())
        return Snapshot(
            deviceName: deviceName,
            projects: projects.map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex, sortOrder: $0.sortOrder, createdAt: $0.createdAt, updatedAt: $0.updatedAt) },
            labels: labels.map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex, createdAt: $0.createdAt, updatedAt: $0.updatedAt) },
            tasks: tasks.map {
                .init(id: $0.id, title: $0.title, notes: $0.notes, priority: $0.priority, dueDate: $0.dueDate, hasDueTime: $0.hasDueTime,
                      isCompleted: $0.isCompleted, completedAt: $0.completedAt, recurrence: $0.recurrence, sortOrder: $0.sortOrder,
                      projectID: $0.project?.id, labelIDs: ($0.labels ?? []).map(\.id), createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                      reminderOffsetMinutes: $0.reminderOffsetMinutes, deadline: $0.deadline, locationName: $0.locationName,
                      flipTarget: $0.flipTarget, flipCount: $0.flipCount, flipPeriodStart: $0.flipPeriodStart,
                      parentID: $0.parent?.id, reminderDate: $0.reminderDate,
                      schemaVersion: Snapshot.TaskRecord.currentSchemaVersion,
                      switchboardID: $0.switchboard?.id, overdueBecomesTask: $0.overdueBecomesTask)
            },
            filters: filters.map { .init(id: $0.id, name: $0.name, query: $0.query, colorHex: $0.colorHex, sortOrder: $0.sortOrder, createdAt: $0.createdAt, updatedAt: $0.updatedAt) },
            switchboards: switchboards.map {
                .init(id: $0.id, name: $0.name, sortOrder: $0.sortOrder, cadence: $0.cadence, resetMinutes: $0.resetMinutes,
                      resetWeekday: $0.resetWeekday, overdueBecomesTask: $0.overdueBecomesTask, createdAt: $0.createdAt,
                      updatedAt: $0.updatedAt)
            }
        )
    }

    /// What a backup holds that this device does not (by id): perhaps made elsewhere and never synced here, perhaps
    /// deleted since the backup was made. Import JSON asks before bringing it back (round 32, review 151 B8).
    struct Missing: Equatable {
        var tasks = 0
        var groups = 0
        var labels = 0
        var filters = 0
        var boards = 0

        var total: Int { tasks + groups + labels + filters + boards }

        /// "The backup from George's Mac holds 2 tasks and 1 label that are not on this device, perhaps deleted
        /// since. Bring them back?"
        func question(from device: String) -> String {
            let parts = [(tasks, "task"), (groups, "Group"), (labels, "label"), (filters, "filter"), (boards, "Switchboard")]
                .filter { $0.0 > 0 }.map { TodoistMapping.count($0.0, $0.1) }
            let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.joined()
            let one = total == 1
            return "The backup from \(device) holds \(list) that \(one ? "is" : "are") not on this device, perhaps deleted since. "
                + "Bring \(one ? "it" : "them") back?"
        }
    }

    /// What `snapshot` holds that `context` does not, by id.
    @MainActor
    static func missing(from snapshot: Snapshot, in context: ModelContext) throws -> Missing {
        func absent<M: SharedIDModel>(_ type: M.Type, _ ids: [UUID]) throws -> Int {
            let here = Set(try context.fetch(FetchDescriptor<M>()).map(\.id))
            return Set(ids).subtracting(here).count
        }
        return Missing(tasks: try absent(TaskItem.self, snapshot.tasks.map(\.id)),
                       groups: try absent(Project.self, snapshot.projects.map(\.id)),
                       labels: try absent(TaskLabel.self, snapshot.labels.map(\.id)),
                       filters: try absent(SavedFilter.self, snapshot.filters.map(\.id)),
                       boards: try absent(Switchboard.self, (snapshot.switchboards ?? []).map(\.id)))
    }

    struct RestoreSummary {
        var inserted = 0
        var updated = 0
        var skipped = 0
        var description: String { "\(inserted) added, \(updated) updated, \(skipped) unchanged" }
    }

    /// Upserts every record by id. A record in the snapshot replaces the local copy only when
    /// its `updatedAt` is newer, so restoring an old backup never clobbers recent edits. `addMissing` false: only
    /// what is on this device is updated, and what is not (`missing`) stays out. A description is cut to the limit.
    @MainActor
    @discardableResult
    static func restore(_ snapshot: Snapshot, into context: ModelContext, addMissing: Bool = true,
                        overwriteNewer: Bool = false) throws -> RestoreSummary {
        var summary = RestoreSummary()

        var projectsByID: [UUID: Project] = [:]
        for p in try context.fetch(FetchDescriptor<Project>()) { projectsByID[p.id] = p }
        for r in snapshot.projects {
            if let existing = projectsByID[r.id] {
                guard overwriteNewer || r.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                existing.name = r.name; existing.colorHex = r.colorHex; existing.sortOrder = r.sortOrder; existing.updatedAt = r.updatedAt
                summary.updated += 1
            } else {
                guard addMissing else { continue }
                let p = Project(name: r.name, colorHex: r.colorHex, sortOrder: r.sortOrder)
                p.id = r.id; p.createdAt = r.createdAt; p.updatedAt = r.updatedAt
                context.insert(p); projectsByID[r.id] = p
                summary.inserted += 1
            }
        }

        var labelsByID: [UUID: TaskLabel] = [:]
        for l in try context.fetch(FetchDescriptor<TaskLabel>()) { labelsByID[l.id] = l }
        for r in snapshot.labels {
            if let existing = labelsByID[r.id] {
                guard overwriteNewer || r.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                existing.name = r.name; existing.colorHex = r.colorHex; existing.updatedAt = r.updatedAt
                summary.updated += 1
            } else {
                guard addMissing else { continue }
                let l = TaskLabel(name: r.name, colorHex: r.colorHex)
                l.id = r.id; l.createdAt = r.createdAt; l.updatedAt = r.updatedAt
                context.insert(l); labelsByID[r.id] = l
                summary.inserted += 1
            }
        }

        var filtersByID: [UUID: SavedFilter] = [:]
        for f in try context.fetch(FetchDescriptor<SavedFilter>()) { filtersByID[f.id] = f }
        for r in snapshot.filters {
            if let existing = filtersByID[r.id] {
                guard overwriteNewer || r.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                existing.name = r.name; existing.query = r.query; existing.colorHex = r.colorHex; existing.sortOrder = r.sortOrder; existing.updatedAt = r.updatedAt
                summary.updated += 1
            } else {
                guard addMissing else { continue }
                let f = SavedFilter(name: r.name, query: r.query, colorHex: r.colorHex, sortOrder: r.sortOrder)
                f.id = r.id; f.createdAt = r.createdAt; f.updatedAt = r.updatedAt
                context.insert(f)
                summary.inserted += 1
            }
        }

        // Schema V6's Switchboards (brief 72); a backup from before 0.9.0 (21) has none and touches none.
        var boardsByID: [UUID: Switchboard] = [:]
        for b in try context.fetch(FetchDescriptor<Switchboard>()) { boardsByID[b.id] = b }
        for r in snapshot.switchboards ?? [] {
            let board: Switchboard
            if let existing = boardsByID[r.id] {
                guard overwriteNewer || r.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                board = existing
                summary.updated += 1
            } else {
                guard addMissing else { continue }
                board = Switchboard(name: r.name)
                board.id = r.id
                board.createdAt = r.createdAt
                context.insert(board)
                boardsByID[r.id] = board
                summary.inserted += 1
            }
            board.name = r.name; board.sortOrder = r.sortOrder; board.cadence = r.cadence
            board.resetMinutes = r.resetMinutes; board.resetWeekday = r.resetWeekday
            board.overdueBecomesTask = r.overdueBecomesTask; board.updatedAt = r.updatedAt
        }

        var tasksByID: [UUID: TaskItem] = [:]
        for t in try context.fetch(FetchDescriptor<TaskItem>()) { tasksByID[t.id] = t }
        var restoredTasks: [(record: Snapshot.TaskRecord, task: TaskItem)] = []
        for r in snapshot.tasks {
            let target: TaskItem
            if let existing = tasksByID[r.id] {
                guard overwriteNewer || r.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                target = existing
                summary.updated += 1
            } else {
                guard addMissing else { continue }
                target = TaskItem(title: r.title)
                target.id = r.id
                target.createdAt = r.createdAt
                context.insert(target)
                tasksByID[r.id] = target
                summary.inserted += 1
            }
            restoredTasks.append((r, target))
            target.title = r.title; target.notes = TaskLimits.clampedNotes(r.notes); target.priority = r.priority
            target.dueDate = r.dueDate; target.hasDueTime = r.hasDueTime
            target.isCompleted = r.isCompleted; target.completedAt = r.completedAt
            target.recurrence = r.recurrence; target.sortOrder = r.sortOrder
            target.project = r.projectID.flatMap { projectsByID[$0] }
            target.labels = r.labelIDs.compactMap { labelsByID[$0] }
            // Schema V2's fields, when the backup has them: one from before 0.3.6 doesn't say, so it leaves
            // them as they are (a new task keeps the defaults).
            if r.hasV2Fields {
                target.reminderOffsetMinutes = r.reminderOffsetMinutes
                target.deadline = r.deadline
                target.locationName = r.locationName
                target.flipTarget = r.flipTarget ?? 1
                target.flipCount = r.flipCount ?? 0
                target.flipPeriodStart = r.flipPeriodStart
            }
            // Schema V5's reminder moment ("!15m"), the same way: a backup from before 0.7.0 doesn't say.
            if r.hasV5Fields { target.reminderDate = r.reminderDate }
            // Schema V6's board and opt-in, the same way: a backup from before 0.9.0 (21) doesn't say.
            if r.hasV6Fields {
                target.switchboard = r.switchboardID.flatMap { boardsByID[$0] }
                target.overdueBecomesTask = r.overdueBecomesTask ?? false
            }
            target.updatedAt = r.updatedAt
        }
        // Subtasks once every task exists (a child may come before its parent). One level only: a parent
        // that is itself a subtask in the backup (a damaged one) hands its children to its own parent.
        let parentIDs = Dictionary(snapshot.tasks.map { ($0.id, $0.parentID) }, uniquingKeysWith: { first, _ in first })
        for (record, task) in restoredTasks {
            var parentID = record.parentID
            var hops = 0
            while let id = parentID, let next = parentIDs[id] ?? nil, hops < snapshot.tasks.count {
                parentID = next
                hops += 1
            }
            var parent = parentID.flatMap { tasksByID[$0] }
            // A parent the backup doesn't hold, which is a subtask here: its own parent instead.
            let parentInBackup = parentID.map { parentIDs.keys.contains($0) } ?? false
            if !parentInBackup, let grand = parent?.parent { parent = grand }
            task.parent = parent === task ? nil : parent
        }

        try context.save()
        return summary
    }
}

#if canImport(UIKit)
import UIKit
#endif
