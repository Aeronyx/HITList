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

    @MainActor
    static func build(from context: ModelContext) throws -> Snapshot {
        let projects = try context.fetch(FetchDescriptor<Project>())
        let labels = try context.fetch(FetchDescriptor<TaskLabel>())
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let filters = try context.fetch(FetchDescriptor<SavedFilter>())
        return Snapshot(
            deviceName: deviceName(),
            projects: projects.map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex, sortOrder: $0.sortOrder, createdAt: $0.createdAt, updatedAt: $0.updatedAt) },
            labels: labels.map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex, createdAt: $0.createdAt, updatedAt: $0.updatedAt) },
            tasks: tasks.map {
                .init(id: $0.id, title: $0.title, notes: $0.notes, priority: $0.priority, dueDate: $0.dueDate, hasDueTime: $0.hasDueTime,
                      isCompleted: $0.isCompleted, completedAt: $0.completedAt, recurrence: $0.recurrence, sortOrder: $0.sortOrder,
                      projectID: $0.project?.id, labelIDs: ($0.labels ?? []).map(\.id), createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            filters: filters.map { .init(id: $0.id, name: $0.name, query: $0.query, colorHex: $0.colorHex, sortOrder: $0.sortOrder, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
        )
    }

    struct RestoreSummary {
        var inserted = 0
        var updated = 0
        var skipped = 0
        var description: String { "\(inserted) added, \(updated) updated, \(skipped) unchanged" }
    }

    /// Upserts every record by id. A record in the snapshot replaces the local copy only when
    /// its `updatedAt` is newer, so restoring an old backup never clobbers recent edits.
    @MainActor
    @discardableResult
    static func restore(_ snapshot: Snapshot, into context: ModelContext, overwriteNewer: Bool = false) throws -> RestoreSummary {
        var summary = RestoreSummary()

        var projectsByID: [UUID: Project] = [:]
        for p in try context.fetch(FetchDescriptor<Project>()) { projectsByID[p.id] = p }
        for r in snapshot.projects {
            if let existing = projectsByID[r.id] {
                guard overwriteNewer || r.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                existing.name = r.name; existing.colorHex = r.colorHex; existing.sortOrder = r.sortOrder; existing.updatedAt = r.updatedAt
                summary.updated += 1
            } else {
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
                let f = SavedFilter(name: r.name, query: r.query, colorHex: r.colorHex, sortOrder: r.sortOrder)
                f.id = r.id; f.createdAt = r.createdAt; f.updatedAt = r.updatedAt
                context.insert(f)
                summary.inserted += 1
            }
        }

        var tasksByID: [UUID: TaskItem] = [:]
        for t in try context.fetch(FetchDescriptor<TaskItem>()) { tasksByID[t.id] = t }
        for r in snapshot.tasks {
            let target: TaskItem
            if let existing = tasksByID[r.id] {
                guard overwriteNewer || r.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                target = existing
                summary.updated += 1
            } else {
                target = TaskItem(title: r.title)
                target.id = r.id
                target.createdAt = r.createdAt
                context.insert(target)
                summary.inserted += 1
            }
            target.title = r.title; target.notes = r.notes; target.priority = r.priority
            target.dueDate = r.dueDate; target.hasDueTime = r.hasDueTime
            target.isCompleted = r.isCompleted; target.completedAt = r.completedAt
            target.recurrence = r.recurrence; target.sortOrder = r.sortOrder
            target.project = r.projectID.flatMap { projectsByID[$0] }
            target.labels = r.labelIDs.compactMap { labelsByID[$0] }
            target.updatedAt = r.updatedAt
        }

        try context.save()
        return summary
    }
}

#if canImport(UIKit)
import UIKit
#endif
