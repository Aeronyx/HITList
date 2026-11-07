import AppIntents
import CoreSpotlight
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
    /// Spotlight only (`init(spotlight:)`): the line under the title, with a fixed date, and the words
    /// it also matches (labels, the Group).
    var spotlightDescription: String?
    var spotlightKeywords: [String] = []

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

    /// The task as Spotlight shows it (brief 52). The date is fixed ("Nov 6, 2026 at 5:00 PM"), never
    /// "Tomorrow", which would go stale in the index; the notes follow after a dash.
    init(spotlight task: TaskItem) {
        // A Flipboard switch has no date to show (brief 59): Spotlight holds only red ones, Today's every day.
        let due = Flipboard.isMember(task) ? Self.switchLine(task)
            : task.dueDate.map { $0.formatted(date: .abbreviated, time: task.hasDueTime ? .shortened : .omitted) }
        let line = [due, task.project?.name].compactMap { $0 }.joined(separator: " · ")
        let notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(id: task.id, title: task.title, dueDate: task.dueDate, group: task.project?.name,
                  detail: line.isEmpty ? nil : line)
        // One line: Spotlight runs lines together ("Home Ask about Sunday").
        let description = [line, notes.replacingOccurrences(of: "\n", with: " ")].filter { !$0.isEmpty }
            .joined(separator: " — ")
        spotlightDescription = description.isEmpty ? nil : description
        spotlightKeywords = task.labelList.map(\.name) + [task.project?.name].compactMap { $0 }
    }

    /// "Flipboard switch · every 3 days".
    static func switchLine(_ task: TaskItem) -> String {
        ["Flipboard switch", task.recurrenceRule?.displayText.lowercased()].compactMap { $0 }.joined(separator: " · ")
    }

    init(_ task: TaskItem, now: Date = Date()) {
        let due = Flipboard.side(of: task, now: now) == .red ? "Today"
            : task.dueDate.map { DueFormatter.text(for: $0, hasTime: task.hasDueTime, now: now) }
        let parts = [due, task.project?.name].compactMap { $0 }
        self.init(id: task.id, title: task.title, dueDate: task.dueDate, group: task.project?.name,
                  detail: parts.isEmpty ? nil : parts.joined(separator: " · "))
    }
}

/// Open tasks in Spotlight (`SpotlightSync` indexes them; tapping one runs `OpenTaskIntent`).
extension TaskEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = title
        set.displayName = title
        set.contentDescription = spotlightDescription ?? detail
        set.keywords = spotlightKeywords.isEmpty ? nil : spotlightKeywords
        // No `dueDate`: Spotlight adds it as a line of its own, "Today, 12:00 AM" for an all-day task.
        return set
    }
}

/// "Open Task": brings HITList forward with the task in its editor. Spotlight runs it when a task result
/// is tapped; Shortcuts offers it too.
struct OpenTaskIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Task"
    static let description: IntentDescription? = IntentDescription("Opens a task in HITList.", categoryName: "Tasks")
    static let openAppWhenRun = true

    @Parameter(title: "Task")
    var target: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.open(task: target.id)
        return .result()
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
        if Flipboard.isMember(task) {
            // A switch flips (brief 59): the interval restarts from today, a charger counts one flip.
            switch Flipboard.flip(task, in: context, now: now) {
            case .counted(let n): return "Flipped ‘\(task.title)’: \(n) of \(Flipboard.clampedTarget(task.flipTarget))."
            case .ignored: return "‘\(task.title)’ is already charged for now."
            case .charged:
                let next = task.dueDate.map { " It’s next due \(spokenDue($0, hasTime: false, now: now))." } ?? ""
                return "Flipped ‘\(task.title)’." + next
            }
        }
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
        let rest = TaskOrdering.sorted(open.filter {
            !shown.contains($0.id) && FlipboardSwitch.listing(for: $0, now: now) != .hidden
        }, now: now)
        return Array((first + rest).prefix(suggestionLimit))
    }

    static let suggestionLimit = 100

    static func openTopLevelTasks(in context: ModelContext) throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted })).filter { !$0.isSubtask }
    }
}
