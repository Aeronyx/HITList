import AppIntents
import Foundation
import SwiftData
import HITListCore

/// A task for Shortcuts and Siri: what Complete Task takes, what Add Task and Today's Tasks hand on.
struct TaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static let defaultQuery = TaskQuery()

    let id: UUID

    @Property(title: "Title")
    var title: String

    @Property(title: "Due")
    var dueDate: Date?

    @Property(title: "Group")
    var group: String?

    /// "Tomorrow 17:00 · Home", under the title in Shortcuts' pickers.
    let detail: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: detail.map { "\($0)" })
    }

    init(id: UUID, title: String, dueDate: Date?, group: String?, detail: String?) {
        self.id = id
        self.detail = detail
        self.title = title
        self.dueDate = dueDate
        self.group = group
    }

    init(_ task: TaskItem, now: Date = Date()) {
        let due = task.dueDate.map { DueFormatter.text(for: $0, hasTime: task.hasDueTime, now: now) }
        let parts = [due, task.project?.name].compactMap { $0 }
        self.init(id: task.id, title: task.title, dueDate: task.dueDate, group: task.project?.name,
                  detail: parts.isEmpty ? nil : parts.joined(separator: " · "))
    }
}

/// Open tasks only, sub-tasks left out (they are reached through their parent), searched by title.
struct TaskQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        try IntentActions.tasks(ids: identifiers, in: IntentStore.context()).map { TaskEntity($0) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [TaskEntity] {
        try IntentActions.openTasks(matching: string, in: IntentStore.context()).map { TaskEntity($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskEntity] {
        try IntentActions.suggestedTasks(in: IntentStore.context()).map { TaskEntity($0) }
    }
}

/// "Complete a task in HITList": ticks a task off through `TaskActions.toggleCompletion` (a repeating task
/// moves to its next date; open sub-tasks are completed with it), without opening the app.
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description: IntentDescription? = IntentDescription(
        "Completes a task in HITList. A repeating task moves to its next date instead.", categoryName: "Tasks")
    static let openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "Which task?")
    var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try IntentActions.complete(task.id, in: IntentStore.context())
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

extension IntentActions {
    /// Completes the task with `id`; returns what Siri says.
    static func complete(_ id: UUID, in context: ModelContext, now: Date = Date()) throws -> String {
        guard let task = task(id: id, in: context) else { throw IntentFailure.taskNotFound }
        guard !task.isCompleted else { return "‘\(task.title)’ is already done." }
        TaskActions.toggleCompletion(task, in: context)
        if !task.isCompleted, let next = task.dueDate {
            return "Done. ‘\(task.title)’ is next due \(spokenDue(next, hasTime: task.hasDueTime, now: now))."
        }
        return "Completed ‘\(task.title)’."
    }

    static func tasks(ids: [UUID], in context: ModelContext) throws -> [TaskItem] {
        let wanted = Set(ids)
        let found = try context.fetch(FetchDescriptor<TaskItem>()).filter { wanted.contains($0.id) }
        // In the order asked for.
        return ids.compactMap { id in found.first { $0.id == id } }
    }

    /// Open top-level tasks whose title or notes hold every word of `text` (Browse search's rule), in
    /// `priorityThenDue` order; blank text gives the suggestions.
    static func openTasks(matching text: String, in context: ModelContext) throws -> [TaskItem] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return try suggestedTasks(in: context) }
        return TaskOrdering.search(try openTopLevelTasks(in: context), text: text)
    }

    /// What Shortcuts offers before anything is typed: Today's tasks (overdue first), then every other open
    /// task in `priorityThenDue` order, at most `suggestionLimit`.
    static func suggestedTasks(in context: ModelContext, now: Date = Date()) throws -> [TaskItem] {
        let open = try openTopLevelTasks(in: context)
        let today = TaskOrdering.today(open, now: now)
        let first = today.overdue + today.today
        let shown = Set(first.map(\.id))
        let rest = TaskOrdering.sorted(open.filter { !shown.contains($0.id) })
        return Array((first + rest).prefix(suggestionLimit))
    }

    static let suggestionLimit = 100

    private static func openTopLevelTasks(in context: ModelContext) throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted })).filter { !$0.isSubtask }
    }
}
