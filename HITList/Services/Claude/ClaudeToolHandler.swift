import Foundation
import SwiftData
import HITListCore

/// Runs the connector's tools (brief 43) on the app's main context, through `TaskActions`, as a tap would.
/// The privacy rule comes first: every tool works on the visible tasks only, so a hidden task can't be
/// listed, counted, searched, read, completed or changed, and asking for one by id gets the same answer
/// as an id that never existed. Task ids are the snapshot JSON's (`TaskItem.id`).
@MainActor
struct ClaudeToolHandler {
    let context: ModelContext
    let rule: ClaudeAccessRule
    var now: Date = Date()
    var calendar: Calendar = .current
    var weekStart: Int = Preferences.weekStartWeekday()
    /// Each write, for the sync log: a message and fields (ids, never task text).
    var log: (_ message: String, _ fields: [String: String]) -> Void = { _, _ in }
    /// After any write (reminders are rescheduled).
    var didWrite: () -> Void = {}
    /// After `complete_task`, so the app can offer its Undo toast.
    var didComplete: (CompletedTask) -> Void = { _ in }

    struct ToolError: Error {
        let message: String
        init(_ message: String) { self.message = message }
        static let noTask = ToolError("No task with that id. List tasks to get current ids.")
    }

    func call(_ tool: String, _ arguments: [String: JSONValue]) -> MCPToolResult {
        do {
            switch tool {
            case ClaudeTools.listTasks: return try listTasks(arguments)
            case ClaudeTools.getTask: return .json(json(try task(arguments["id"]), full: true))
            case ClaudeTools.addTask: return try addTask(arguments)
            case ClaudeTools.completeTask: return try completeTask(arguments)
            case ClaudeTools.updateTask: return try updateTask(arguments)
            case ClaudeTools.listGroups: return try listGroups()
            case ClaudeTools.listLabels: return try listLabels()
            default: return .error("Unknown tool: \(tool)")
            }
        } catch let error as ToolError {
            return .error(error.message)
        } catch {
            return .error("HITList couldn't do that: \(error.localizedDescription)")
        }
    }

    // MARK: Visibility

    static func labelNames(_ task: TaskItem) -> [String] { (task.labels ?? []).map(\.name) }

    func isVisible(_ task: TaskItem) -> Bool {
        rule.isVisible(task, labelNames: Self.labelNames, parent: { $0.parent })
    }

    /// Every task Claude may see, subtasks included.
    func visibleTasks() throws -> [TaskItem] {
        rule.visible(try context.fetch(FetchDescriptor<TaskItem>()), labelNames: Self.labelNames, parent: { $0.parent })
    }

    /// The visible task with this id; a hidden one is "no task", exactly like a missing one.
    func task(_ argument: JSONValue?) throws -> TaskItem {
        guard let text = argument?.stringValue?.trimmingCharacters(in: .whitespaces), let id = UUID(uuidString: text) else {
            throw ToolError("Give the task's id: a UUID from list_tasks.")
        }
        let matches = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id }))
        guard let task = matches.first(where: isVisible) else { throw ToolError.noTask }
        return task
    }

    // MARK: Reading

    private func listTasks(_ arguments: [String: JSONValue]) throws -> MCPToolResult {
        let filter = arguments["filter"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var source = filter.isEmpty ? "all" : filter
        if arguments["include_completed"]?.boolValue == true { source = "(\(source)) & (completed | !completed)" }
        let query: FilterQuery
        do {
            query = try FilterQuery(source, calendar: calendar, now: now)
        } catch let error as FilterQueryError {
            throw ToolError("The filter didn't parse: \(error.message). Example: \"(today | overdue) & p1\" or \"#Work & 7 days\".")
        }
        // `apply` leaves out subtasks (they come inside their task) and completed tasks unless asked.
        let matched = query.apply(to: try visibleTasks(), now: now, calendar: calendar)
        let limit = min(max(arguments["limit"]?.intValue ?? ClaudeTools.defaultLimit, 1), ClaudeTools.maxLimit)
        let shown = matched.prefix(limit)
        return .json([
            "today": .string(dayString(now)),
            "filter": .string(filter.isEmpty ? "(every open task)" : filter),
            "total": .int(matched.count),
            "returned": .int(shown.count),
            "tasks": .array(shown.map { json($0, full: false) }),
        ])
    }

    private func listGroups() throws -> MCPToolResult {
        let visible = try visibleTasks()
        let visibleIDs = Set(visible.map(\.persistentModelID))
        let projects = try context.fetch(FetchDescriptor<Project>()).sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        var groups: [JSONValue] = [["name": "Inbox", "open_tasks": .int(visible.filter { $0.project == nil && Self.isOpenRow($0) }.count)]]
        for project in projects {
            let tasks = project.tasks ?? []
            guard rule.showsContainer(holding: tasks, labelNames: Self.labelNames, parent: { $0.parent }) else { continue }
            let open = tasks.filter { visibleIDs.contains($0.persistentModelID) && Self.isOpenRow($0) }.count
            groups.append(["name": .string(project.name), "open_tasks": .int(open)])
        }
        return .json(["groups": .array(groups)])
    }

    private func listLabels() throws -> MCPToolResult {
        let visibleIDs = Set(try visibleTasks().map(\.persistentModelID))
        let labels = try context.fetch(FetchDescriptor<TaskLabel>()).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var out: [JSONValue] = []
        for label in labels {
            let tasks = label.tasks ?? []
            guard rule.showsContainer(holding: tasks, labelNames: Self.labelNames, parent: { $0.parent }) else { continue }
            let open = tasks.filter { visibleIDs.contains($0.persistentModelID) && Self.isOpenRow($0) }.count
            out.append(["name": .string(label.name), "open_tasks": .int(open)])
        }
        return .json(["labels": .array(out)])
    }

    /// An open task in its own right (what a list counts).
    private static func isOpenRow(_ task: TaskItem) -> Bool { !task.isCompleted && task.parent == nil }

    // MARK: Writing

    private func addTask(_ arguments: [String: JSONValue]) throws -> MCPToolResult {
        let text = TaskLimits.singleLine(arguments["text"]?.stringValue ?? "")
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { throw ToolError("add_task needs text: the task's title and any quick-add syntax.") }
        let projects = try context.fetch(FetchDescriptor<Project>())
        let labels = try context.fetch(FetchDescriptor<TaskLabel>())
        let parser = QuickAddParser(now: now, calendar: calendar, knownProjects: projects.map(\.name),
                                    knownLabels: labels.map(\.name), weekStart: weekStart)
        // The quick-add card's own path (no list defaults: the plain card).
        var parsed = QuickAddDraft(context: .plain, text: text).result(parser)
        guard !parsed.title.isEmpty else { throw ToolError("That text is all syntax: give the task a title too.") }
        parsed.labelNames = rule.labelsKeepingAccess(parsed.labelNames)
        let task = try TaskActions.create(from: parsed, defaultProject: nil, defaultLabel: nil, in: context)
        if let notes = arguments["description"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            task.notes = notes
            try context.save()
        }
        log("Claude added a task", ["tool": ClaudeTools.addTask, "task": task.id.uuidString])
        didWrite()
        var reply: [String: JSONValue] = ["added": json(task, full: true)]
        if !isVisible(task) {
            reply["note"] = .string("It carries @\(rule.hiddenLabel), so it is hidden from you from now on.")
        }
        return .json(.object(reply))
    }

    private func completeTask(_ arguments: [String: JSONValue]) throws -> MCPToolResult {
        let task = try self.task(arguments["id"])
        guard !task.isCompleted else { throw ToolError("That task is already completed.") }
        let revert: CompletedTask.Revert = if task.recurrenceRule != nil, let due = task.dueDate { .restoreDueDate(due) } else { .uncomplete }
        TaskActions.toggleCompletion(task, in: context, now: now)
        log("Claude completed a task", ["tool": ClaudeTools.completeTask, "task": task.id.uuidString])
        didWrite()
        didComplete(CompletedTask(id: task.id, title: task.title, revert: revert))
        if case .restoreDueDate = revert {
            return .json(["completed": false, "repeats": true, "next_due": dueJSON(task) ?? .null,
                          "note": "A repeating task moves to its next date instead of being marked done.", "task": json(task, full: false)])
        }
        return .json(["completed": true, "task": json(task, full: false)])
    }

    private func updateTask(_ arguments: [String: JSONValue]) throws -> MCPToolResult {
        let task = try self.task(arguments["id"])
        let fields = Set(arguments.keys).subtracting(["id"])
        guard !fields.isEmpty else { throw ToolError("Nothing to change: give title, description, due, priority, labels or group.") }
        if task.isSubtask, !fields.isSubset(of: ["title", "description"]) {
            throw ToolError("A subtask has only a title and a description; its date, priority, labels and Group are its task's.")
        }
        // Check everything before changing anything, so a bad field changes nothing.
        let title = try arguments["title"].map { value -> String in
            let title = TaskLimits.clampedTitle(TaskLimits.singleLine(value.stringValue ?? ""))
            guard !title.isEmpty else { throw ToolError("A task needs a title.") }
            return title
        }
        let notes = try arguments["description"].map { value -> String in
            guard let text = value.stringValue else { throw ToolError("description must be text.") }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let due = try arguments["due"].map(parseDue)
        let priority = try arguments["priority"].map { value -> Int in
            guard let p = value.intValue ?? value.stringValue.flatMap({ Int($0.lowercased().replacingOccurrences(of: "p", with: "")) }),
                  (1...4).contains(p) else { throw ToolError("priority is 1 (most urgent) to 4 (none).") }
            return p
        }
        let labelNames = try arguments["labels"].map { value -> [String] in
            guard let items = value.arrayValue else { throw ToolError("labels is a list of names, e.g. [\"home\", \"errand\"].") }
            let names = items.compactMap(\.stringValue).map { ClaudeAccessRule.normalized($0, fallback: "") }.filter { !$0.isEmpty }
            return rule.labelsKeepingAccess(names)
        }
        let groupName = try arguments["group"].map { value -> String? in
            guard let name = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) else { throw ToolError("group is a Group's name.") }
            let bare = name.hasPrefix("#") ? String(name.dropFirst()) : name
            return bare.isEmpty || bare.caseInsensitiveCompare("Inbox") == .orderedSame ? nil : bare
        }

        if let title { task.title = title }
        if let notes { task.notes = notes }
        if let due {
            task.dueDate = due.date
            task.hasDueTime = due.date != nil && due.hasTime
            if let rule = due.recurrence { task.recurrenceRule = rule } else if due.date == nil { task.recurrence = nil }
            TaskActions.syncRepeatTime(of: task)
        }
        if let priority { task.priority = priority }
        if let labelNames {
            var labels: [TaskLabel] = []
            for name in labelNames where !labels.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                labels.append(try TaskActions.findOrCreateLabel(named: name, in: context))
            }
            task.labels = labels
        }
        task.touch()
        try context.save()
        if let groupName {
            TaskActions.setProject(try groupName.map { try TaskActions.findOrCreateProject(named: $0, in: context) }, of: task, in: context)
        }
        log("Claude changed a task", ["tool": ClaudeTools.updateTask, "task": task.id.uuidString,
                                      "fields": fields.sorted().joined(separator: ",")])
        didWrite()
        var reply: [String: JSONValue] = ["updated": json(task, full: true)]
        if !isVisible(task) {
            reply["note"] = .string("It now carries @\(rule.hiddenLabel), so it is hidden from you from now on.")
        }
        return .json(.object(reply))
    }

    struct Due { var date: Date?; var hasTime: Bool; var recurrence: RecurrenceRule? }

    /// A date phrase as quick add reads it ("friday 5pm", "every weekday 9am"), or "none" / "" to clear.
    func parseDue(_ value: JSONValue) throws -> Due {
        guard let phrase = value.isNull ? "" : value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ToolError("due is a date phrase such as \"tomorrow 3pm\", or \"none\".")
        }
        if ["", "none", "no date", "clear", "remove"].contains(phrase.lowercased()) { return Due(date: nil, hasTime: false) }
        let parser = QuickAddParser(now: now, calendar: calendar, weekStart: weekStart)
        let parsed = parser.parse("x " + phrase)
        let kinds = Set(parsed.tokens.filter { !$0.isSuperseded }.map(\.kind))
        guard let date = parsed.dueDate, !kinds.isDisjoint(with: [.date, .time, .recurrence]), parsed.title == "x" else {
            throw ToolError("Couldn't read \"\(phrase)\" as a date. Try \"tomorrow\", \"fri 5pm\", \"jan 6\", \"in 3 days\" or \"every monday\".")
        }
        return Due(date: date, hasTime: parsed.hasDueTime, recurrence: parsed.recurrence)
    }

    // MARK: JSON for Claude

    /// A task as Claude sees it. The list form keeps the description to its first 200 characters and the
    /// subtasks to a count; the full form has both in full.
    func json(_ task: TaskItem, full: Bool) -> JSONValue {
        var out: [String: JSONValue] = [
            "id": .string(task.id.uuidString),
            "title": .string(task.title),
            "priority": .int(task.priority),
            "group": .string(task.project?.name ?? "Inbox"),
            "labels": .array(task.labelList.map { .string($0.name) }),
            "completed": .bool(task.isCompleted),
        ]
        if !task.notes.isEmpty {
            out["description"] = .string(full || task.notes.count <= 200 ? task.notes : String(task.notes.prefix(200)) + "…")
        }
        if let due = dueJSON(task) { out["due"] = due }
        if let rule = task.recurrenceRule { out["repeats"] = .string(rule.displayText) }
        if let deadline = task.deadline { out["deadline"] = .string(dayString(deadline)) }
        if let minutes = task.reminderOffsetMinutes, task.hasDueTime { out["reminder_minutes_before"] = .int(minutes) }
        if let at = task.reminderDate, !task.isCompleted, at > now { out["reminder_at"] = .string(timeString(at)) }
        if let location = task.locationName { out["location"] = .string(location) }
        if let completedAt = task.completedAt, task.isCompleted { out["completed_at"] = .string(timeString(completedAt)) }
        if let parent = task.parent {
            out["parent"] = ["id": .string(parent.id.uuidString), "title": .string(parent.title)]
            out.removeValue(forKey: "group")
            out.removeValue(forKey: "labels")
            out.removeValue(forKey: "priority")
        }
        let subtasks = task.orderedSubtasks
        if !subtasks.isEmpty {
            if full {
                out["subtasks"] = .array(subtasks.map {
                    ["id": .string($0.id.uuidString), "title": .string($0.title), "completed": .bool($0.isCompleted)]
                })
            } else if let progress = task.subtaskProgress {
                out["subtasks_done"] = .string(progress.text)
            }
        }
        return .object(out)
    }

    /// "2026-11-05" for an all-day date, "2026-11-05T15:00:00-05:00" with a time.
    func dueJSON(_ task: TaskItem) -> JSONValue? {
        guard let due = task.dueDate else { return nil }
        return .string(task.hasDueTime ? timeString(due) : dayString(due))
    }

    private func dayString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        f.formatOptions = [.withFullDate]
        return f.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
