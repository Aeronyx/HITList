import Foundation
import SwiftData
import HITListCore

/// Mutations that touch several models or carry business rules live here so views stay thin.
@MainActor
enum TaskActions {
    /// Creates a task from a parsed quick-add result, creating any project/labels that don't exist yet.
    @discardableResult
    static func create(from parsed: QuickAddResult, defaultProject: Project?, defaultLabel: TaskLabel?, in context: ModelContext) throws -> TaskItem {
        let title = TaskLimits.clampedTitle(parsed.title)
        guard !title.isEmpty else { throw ActionError.emptyTitle }

        var project = defaultProject
        if let name = parsed.projectName { project = try findOrCreateProject(named: name, in: context) }

        var labels: [TaskLabel] = []
        for name in parsed.labelNames { labels.append(try findOrCreateLabel(named: name, in: context)) }
        if let defaultLabel, !labels.contains(where: { $0.id == defaultLabel.id }) { labels.append(defaultLabel) }

        let task = TaskItem(title: title, priority: parsed.priority.rawValue, dueDate: parsed.dueDate, hasDueTime: parsed.hasDueTime,
                            project: project, labels: labels, recurrence: parsed.recurrence)
        // Zero ("!at") is the same as no offset: remind at the due time.
        if let offset = parsed.reminderOffsetMinutes, offset > 0 { task.reminderOffsetMinutes = offset }
        if let deadline = parsed.deadline { task.deadline = Calendar.current.startOfDay(for: deadline) }
        if let location = parsed.locationName?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            task.locationName = location
        }
        context.insert(task)
        try context.save()
        return task
    }

    static func findOrCreateProject(named name: String, in context: ModelContext) throws -> Project {
        let all = try context.fetch(FetchDescriptor<Project>())
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return existing }
        let project = Project(name: name, colorHex: Color.palette[all.count % Color.palette.count].hex, sortOrder: all.count)
        context.insert(project)
        return project
    }

    static func findOrCreateLabel(named name: String, in context: ModelContext) throws -> TaskLabel {
        let all = try context.fetch(FetchDescriptor<TaskLabel>())
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return existing }
        let label = TaskLabel(name: name)
        context.insert(label)
        return label
    }

    /// Completes a task. Recurring tasks are not marked done; their due date advances instead.
    static func toggleCompletion(_ task: TaskItem, in context: ModelContext) {
        if task.isCompleted {
            task.isCompleted = false
            task.completedAt = nil
        } else if let rule = task.recurrenceRule, let due = task.dueDate {
            task.dueDate = rule.nextDueDate(from: due, now: Date())
        } else {
            task.isCompleted = true
            task.completedAt = Date()
        }
        task.touch()
        try? context.save()
    }

    static func reschedule(_ task: TaskItem, to date: Date?, keepTime: Bool = true, in context: ModelContext) {
        if let date, let old = task.dueDate, task.hasDueTime, keepTime {
            let cal = Calendar.current
            let comps = cal.dateComponents([.hour, .minute], from: old)
            task.dueDate = cal.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: 0, of: date)
        } else {
            task.dueDate = date
            if date == nil { task.hasDueTime = false }
        }
        task.touch()
        try? context.save()
    }

    static func delete(_ task: TaskItem, in context: ModelContext) {
        context.delete(task)
        try? context.save()
    }

    struct DefaultFilter {
        /// Seed key for `SeedIdentity.savedFilter`; never change it, unlike the display name.
        let key: String
        let name: String
        let query: String
        let colorHex: String
    }

    static let defaultFilters: [DefaultFilter] = [
        DefaultFilter(key: "focus", name: "Focus", query: "(p1 | p2) & (overdue | today)", colorHex: "#E5484D"),
        DefaultFilter(key: "this-week", name: "This week", query: "next 7 days | overdue", colorHex: "#5E81F4"),
        DefaultFilter(key: "waiting", name: "Waiting", query: "@waiting", colorHex: "#9A9A9A"),
        DefaultFilter(key: "unscheduled", name: "Unscheduled", query: "no date & !recurring", colorHex: "#B07CF5"),
    ]

    nonisolated static let didSeedDefaultsKey = "didSeedDefaults"

    /// Adds a few starter filters on a brand-new install so the feature is discoverable.
    ///
    /// Each default filter gets the same stable id on every device (`SeedIdentity`), and is skipped if a
    /// filter with that id or that name already exists. A device that seeds before its first CloudKit
    /// import still creates copies, but they share ids with the other devices' copies, and
    /// `Deduplicator` collapses them after the import. The per-device flag only saves the fetch.
    static func seedDefaultsIfNeeded(in context: ModelContext, defaults: UserDefaults = AppGroup.defaults) {
        guard !defaults.bool(forKey: didSeedDefaultsKey) else { return }
        do {
            let existing = try context.fetch(FetchDescriptor<SavedFilter>())
            let ids = Set(existing.map(\.id))
            let names = Set(existing.map { Deduplicator.nameKey($0.name) })
            for (i, seed) in defaultFilters.enumerated() {
                let id = SeedIdentity.savedFilter(seed.key)
                guard !ids.contains(id), !names.contains(Deduplicator.nameKey(seed.name)) else { continue }
                let filter = SavedFilter(name: seed.name, query: seed.query, colorHex: seed.colorHex, sortOrder: i)
                filter.id = id
                context.insert(filter)
            }
            try context.save()
            defaults.set(true, forKey: didSeedDefaultsKey)
        } catch {
            context.rollback()
            print("seedDefaults failed: \(error)")
        }
    }

    /// Developer aid: `HITList -seedSampleData` inserts one task with a project and a label so every
    /// record type exists in CloudKit (needed once before deploying the schema to Production). Only into a
    /// side store (`HITLIST_STORE_SUFFIX`, which a Development build sets for itself): never into
    /// HITList.store, from where the sample would reach every device.
    static func seedSampleDataIfRequested(in context: ModelContext, arguments: [String] = CommandLine.arguments,
                                          storeName: String = ModelContainerFactory.storeName) {
        guard arguments.contains("-seedSampleData") else { return }
        guard storeName != ModelContainerFactory.mainStoreName else {
            print("-seedSampleData ignored: it seeds only a side store (HITLIST_STORE_SUFFIX=schema), never \(storeName)")
            return
        }
        do {
            let project = try findOrCreateProject(named: "Sample Project", in: context)
            let label = try findOrCreateLabel(named: "sample", in: context)
            let task = TaskItem(title: "Sample task (safe to delete)", notes: "Created by -seedSampleData", priority: 2,
                                dueDate: Calendar.current.startOfDay(for: Date()), project: project, labels: [label])
            context.insert(task)
            try context.save()
        } catch {
            print("seedSampleData failed: \(error)")
        }
    }

    enum ActionError: LocalizedError {
        case emptyTitle
        var errorDescription: String? { "A task needs a title." }
    }
}

import SwiftUI
