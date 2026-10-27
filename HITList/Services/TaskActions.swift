import Foundation
import SwiftData
import HITListCore

/// Mutations that touch several models or carry business rules live here so views stay thin.
@MainActor
enum TaskActions {
    /// Creates a task from a parsed quick-add result, creating any project/labels that don't exist yet.
    @discardableResult
    static func create(from parsed: QuickAddResult, defaultProject: Project?, defaultLabel: TaskLabel?, in context: ModelContext) throws -> TaskItem {
        let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ActionError.emptyTitle }

        var project = defaultProject
        if let name = parsed.projectName { project = try findOrCreateProject(named: name, in: context) }

        var labels: [TaskLabel] = []
        for name in parsed.labelNames { labels.append(try findOrCreateLabel(named: name, in: context)) }
        if let defaultLabel, !labels.contains(where: { $0.id == defaultLabel.id }) { labels.append(defaultLabel) }

        let task = TaskItem(title: title, priority: parsed.priority.rawValue, dueDate: parsed.dueDate, hasDueTime: parsed.hasDueTime,
                            project: project, labels: labels, recurrence: parsed.recurrence)
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

    /// Adds a few starter filters on a brand-new install so the feature is discoverable.
    static func seedDefaultsIfNeeded(in context: ModelContext) {
        let key = "didSeedDefaults"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<SavedFilter>())) ?? 0
        if existing == 0 {
            let defaults: [(String, String, String)] = [
                ("Focus", "(p1 | p2) & (overdue | today)", "#E5484D"),
                ("This week", "next 7 days | overdue", "#5E81F4"),
                ("Waiting", "@waiting", "#9A9A9A"),
                ("Unscheduled", "no date & !recurring", "#B07CF5"),
            ]
            for (i, (name, query, color)) in defaults.enumerated() {
                context.insert(SavedFilter(name: name, query: query, colorHex: color, sortOrder: i))
            }
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Developer aid: `HITList -seedSampleData` inserts one task with a project and a label so every
    /// record type exists in CloudKit (needed once before deploying the schema to Production).
    static func seedSampleDataIfRequested(in context: ModelContext) {
        guard CommandLine.arguments.contains("-seedSampleData") else { return }
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
