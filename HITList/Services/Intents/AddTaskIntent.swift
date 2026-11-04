import AppIntents
import Foundation
import SwiftData
import HITListCore

/// "Add a task in HITList": one line of text read by the quick-add card's own parser ("Buy milk tom 5pm p1
/// #Home") and saved by `TaskActions.create`, without opening the app. Works from Siri, Shortcuts, Spotlight
/// and the Action button.
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description: IntentDescription? = IntentDescription(
        "Adds a task to HITList. Write it the way you would on the quick-add card: “Buy milk tomorrow 5pm p1 #Home”.",
        categoryName: "Tasks")
    static let openAppWhenRun = false

    @Parameter(title: "Task", inputOptions: String.IntentInputOptions(capitalizationType: .sentences), requestValueDialog: "What’s the task?")
    var text: String

    @Parameter(title: "Group", description: "Where the task goes when the text names no #Group. Inbox if empty.")
    var group: GroupEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to \(\.$group)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let added = try IntentActions.addTask(text, group: group?.id, in: IntentStore.context())
        return .result(dialog: IntentDialog(stringLiteral: added.dialog))
    }
}

/// A Group (a `Project`) for intent parameters: Shortcuts lists them, Siri asks for one by name.
struct GroupEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Group"
    static let defaultQuery = GroupQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(_ project: Project) {
        self.init(id: project.id, name: project.name)
    }
}

struct GroupQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [GroupEntity] {
        try IntentActions.groups(ids: identifiers, in: IntentStore.context()).map(GroupEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [GroupEntity] {
        try IntentActions.groups(matching: string, in: IntentStore.context()).map(GroupEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [GroupEntity] {
        try IntentActions.groups(in: IntentStore.context()).map(GroupEntity.init)
    }
}

/// The intents' logic, apart from the AppIntents types so tests can run it on an in-memory container.
@MainActor
enum IntentActions {
    /// What `addTask` saved, and the line Siri says about it.
    struct AddedTask: Equatable {
        let id: UUID
        let title: String
        /// "Added ‘Buy milk’ for tomorrow 17:00".
        let dialog: String
    }

    /// Siri's dictation in the card's words: "5:30 p.m." → "5:30 pm" (the parser reads "5 PM" already).
    static func dictationNormalized(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?<![A-Za-z])([AaPp])\.\s?[Mm]\.?(?![A-Za-z])"#, with: "$1m", options: .regularExpression)
    }

    /// Parses `text` as the quick-add card does (known Groups and labels, the week-start setting) and saves
    /// the task. A `#Group` in the text wins over `group`, the way a typed Group wins over the list's own on
    /// the card. No list context: a task with no date typed has none (it lands in the Inbox).
    @discardableResult
    static func addTask(_ text: String, group: UUID?, in context: ModelContext, now: Date = Date()) throws -> AddedTask {
        let projects = try context.fetch(FetchDescriptor<Project>())
        let labels = try context.fetch(FetchDescriptor<TaskLabel>())
        var defaultProject: Project?
        if let group {
            guard let project = projects.first(where: { $0.id == group }) else { throw IntentFailure.groupNotFound }
            defaultProject = project
        }
        let parser = QuickAddParser(now: now, knownProjects: projects.map(\.name), knownLabels: labels.map(\.name),
                                    weekStart: Preferences.weekStartWeekday())
        let result = parser.parse(dictationNormalized(text))
        let task: TaskItem
        do {
            task = try TaskActions.create(from: result, defaultProject: defaultProject, defaultLabel: nil, in: context)
        } catch TaskActions.ActionError.emptyTitle {
            throw IntentFailure.emptyTitle
        }
        return AddedTask(id: task.id, title: task.title, dialog: addedDialog(for: task, now: now))
    }

    /// "Added ‘Buy milk’ for tomorrow 17:00", "Added ‘Call Sam’ for Friday", "Added ‘Read a book’".
    static func addedDialog(for task: TaskItem, now: Date = Date()) -> String {
        var line = "Added ‘\(task.title)’"
        if let due = task.dueDate { line += " for " + spokenDue(due, hasTime: task.hasDueTime, now: now) }
        return line
    }

    /// `DueFormatter.text` with its relative days in lower case, to sit inside a sentence: "tomorrow 17:00".
    static func spokenDue(_ date: Date, hasTime: Bool, now: Date = Date()) -> String {
        lowercasedRelativeDay(DueFormatter.text(for: date, hasTime: hasTime, now: now))
    }

    /// "Tomorrow 17:00" → "tomorrow 17:00"; dates and weekdays keep their capitals.
    nonisolated static func lowercasedRelativeDay(_ text: String) -> String {
        for word in ["Today", "Tomorrow", "Yesterday"] where text.hasPrefix(word) {
            return word.lowercased() + text.dropFirst(word.count)
        }
        return text
    }

    static func task(id: UUID, in context: ModelContext) -> TaskItem? {
        try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: Groups

    /// Every Group in sidebar order.
    static func groups(in context: ModelContext) throws -> [Project] {
        try context.fetch(FetchDescriptor<Project>()).sorted {
            ($0.sortOrder, $0.name.localizedLowercase) < ($1.sortOrder, $1.name.localizedLowercase)
        }
    }

    static func groups(matching text: String, in context: ModelContext) throws -> [Project] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return try groups(in: context) }
        return try groups(in: context).filter { $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    static func groups(ids: [UUID], in context: ModelContext) throws -> [Project] {
        let wanted = Set(ids)
        return try groups(in: context).filter { wanted.contains($0.id) }
    }
}
