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
    ///
    /// Monthly and yearly rules advance from their anchor day, which is stored in the rule string on the
    /// first roll if the rule came without one (the Repeat menu, older builds): Jan 31 → Feb 28 → Mar 31.
    /// A timed task's rule likewise takes the task's time on its first roll, and every roll rebuilds the
    /// next due time from the rule's hour and minute (a 2:30 repeat the spring change pushed to 3:00 is back
    /// at 2:30 the next day); an all-day task's rule has no time.
    ///
    /// Subtasks (brief 32) follow: completing a task completes its open subtasks at the same moment, and
    /// un-completing it (the toast's Undo, the Completed list) reopens exactly those, by that shared
    /// `completedAt`; ones ticked by hand earlier stay ticked. A repeating task's next occurrence starts
    /// with its checklist open. Completing the last subtask leaves the parent alone (Todoist's rule).
    static func toggleCompletion(_ task: TaskItem, in context: ModelContext) {
        let wasCompleted = task.isCompleted
        let closedAt = task.completedAt
        if task.isCompleted {
            task.isCompleted = false
            task.completedAt = nil
        } else if let rule = task.recurrenceRule, let due = task.dueDate {
            var next = rule.anchored(to: due)
            if !task.hasDueTime || next.time == nil { next = next.timed(to: due, hasTime: task.hasDueTime) }
            task.dueDate = next.nextDueDate(from: due, now: Date())
            if next.anchorDay != rule.anchorDay || next.time != rule.time { task.recurrence = next.encoded }
        } else {
            task.isCompleted = true
            task.completedAt = Date()
        }
        task.touch()
        followParent(task, wasCompleted: wasCompleted, closedAt: closedAt)
        try? context.save()
    }

    /// `toggleCompletion`'s checklist half, kept out of its branches (the roll-over's time handling is
    /// brief 31's).
    private static func followParent(_ task: TaskItem, wasCompleted: Bool, closedAt: Date?) {
        for subtask in task.subtasks ?? [] {
            let reopen: Bool
            if wasCompleted {
                reopen = subtask.isCompleted && closedAt != nil && subtask.completedAt == closedAt
            } else if task.isCompleted {
                if !subtask.isCompleted {
                    subtask.isCompleted = true
                    subtask.completedAt = task.completedAt
                    subtask.touch()
                }
                continue
            } else {
                reopen = subtask.isCompleted  // rolled over to its next occurrence
            }
            if reopen {
                subtask.isCompleted = false
                subtask.completedAt = nil
                subtask.touch()
            }
        }
    }

    // MARK: Subtasks (brief 32)

    /// Adds a subtask at the end of `parent`'s checklist: the title (trimmed to one line), the parent's
    /// Group, nothing else. Given a subtask as the parent, it goes to that subtask's own parent (one level).
    @discardableResult
    static func addSubtask(_ title: String, to parent: TaskItem, in context: ModelContext) throws -> TaskItem {
        let title = TaskLimits.clampedTitle(TaskLimits.singleLine(title))
        guard !title.isEmpty else { throw ActionError.emptyTitle }
        let parent = parent.parent ?? parent
        let subtask = TaskItem(title: title, project: parent.project)
        subtask.sortOrder = ((parent.subtasks ?? []).map(\.sortOrder).max() ?? -1) + 1
        context.insert(subtask)
        subtask.parent = parent
        parent.touch()
        try context.save()
        return subtask
    }

    /// The quick-add card's sub-task lines, in order, after its task. Blank titles are skipped.
    static func addSubtasks(_ titles: [String], to parent: TaskItem, in context: ModelContext) throws {
        for title in titles where !TaskLimits.clampedTitle(TaskLimits.singleLine(title)).isEmpty {
            try addSubtask(title, to: parent, in: context)
        }
    }

    /// The one-level rule: only a task in its own right takes subtasks, and only a task without subtasks
    /// becomes one.
    static func canNest(_ task: TaskItem, under parent: TaskItem) -> Bool {
        task.persistentModelID != parent.persistentModelID && parent.parent == nil && (task.subtasks ?? []).isEmpty
    }

    /// Makes `task` the last subtask of `parent`, dropping what subtasks don't have (date, time, repeat,
    /// reminder, deadline, priority, labels) and taking the parent's Group. False, and nothing changed,
    /// when the one-level rule forbids it.
    @discardableResult
    static func makeSubtask(_ task: TaskItem, of parent: TaskItem, in context: ModelContext) -> Bool {
        guard canNest(task, under: parent) else { return false }
        task.sortOrder = ((parent.subtasks ?? []).map(\.sortOrder).max() ?? -1) + 1
        task.parent = parent
        task.project = parent.project
        task.dueDate = nil
        task.hasDueTime = false
        task.recurrence = nil
        task.reminderOffsetMinutes = nil
        task.deadline = nil
        task.priority = Priority.p4.rawValue
        task.labels = []
        task.touch()
        try? context.save()
        return true
    }

    /// Moves a task to a Group (nil: the Inbox), its checklist with it.
    static func setProject(_ project: Project?, of task: TaskItem, in context: ModelContext) {
        task.project = project
        for subtask in task.subtasks ?? [] where subtask.project?.persistentModelID != project?.persistentModelID {
            subtask.project = project
            subtask.touch()
        }
        task.touch()
        try? context.save()
    }

    /// Puts a subtask at `index` in its parent's checklist (clamped) and numbers the checklist 0, 1, 2…
    static func moveSubtask(_ subtask: TaskItem, to index: Int, in context: ModelContext) {
        guard let parent = subtask.parent else { return }
        var order = parent.orderedSubtasks.filter { $0.persistentModelID != subtask.persistentModelID }
        order.insert(subtask, at: max(0, min(index, order.count)))
        for (i, item) in order.enumerated() where item.sortOrder != i {
            item.sortOrder = i
            item.touch()
        }
        try? context.save()
    }

    /// The Repeat menu (task popout, its date card): sets or clears the task's repeat and saves. A repeat
    /// on an undated task starts today. A monthly or yearly repeat keeps the day the task returns to
    /// (`RecurrenceRule.keepingAnchor`): picking "Every month" again on a "31st" task due Feb 28 used to
    /// store the plain rule, and the task repeated on the 28th from then on. A timed task's repeat keeps
    /// its time (`RecurrenceRule.timed`).
    static func setRecurrence(_ rule: RecurrenceRule?, on task: TaskItem, in context: ModelContext, now: Date = Date()) {
        if rule != nil, task.dueDate == nil { task.dueDate = Calendar.current.startOfDay(for: now) }
        task.recurrenceRule = rule?.keepingAnchor(of: task.recurrenceRule, due: task.dueDate)
            .timed(to: task.dueDate, hasTime: task.hasDueTime)
        task.touch()
        try? context.save()
    }

    /// Keeps a repeating task's rule on the task's time after something changed `dueDate` or `hasDueTime`
    /// (the editor's time and date setters). Does not save; the caller does.
    static func syncRepeatTime(of task: TaskItem) {
        guard let rule = task.recurrenceRule else { return }
        let timed = rule.timed(to: task.dueDate, hasTime: task.hasDueTime)
        if timed.time != rule.time { task.recurrenceRule = timed }
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
        syncRepeatTime(of: task)
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

    /// Developer aid: `HITList -seedSampleData` inserts one task with a project, a label and a sub-task so
    /// every record type and field exists in CloudKit (needed once before deploying the schema to
    /// Production). Only into a side store (`HITLIST_STORE_SUFFIX`, which a Development build sets for itself): never into
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
            // Schema V5's `reminderDate` (brief 48) reaches CloudKit only on a record that has one. A side store
            // never schedules notifications (`NotificationScheduler.bootstrap`), so this one never goes off.
            task.reminderDate = Date().addingTimeInterval(15 * 60)
            context.insert(task)
            try context.save()
            // Schema V3's `parent` reaches CloudKit only on a record that has one.
            try addSubtask("Sample sub-task (safe to delete)", to: task, in: context)
            // Schema V4's Profile, the same way (brief 34).
            try ProfileStore(context: context).seedSampleProfiles()
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
