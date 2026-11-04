import Foundation

/// The connector's tools (brief 43): what `tools/list` offers and the argument names both ends use.
/// Small and sharp: read with a filter, add with quick-add text, complete, update, and the two lists
/// a model needs to write good quick-add text. Nothing deletes.
public enum ClaudeTools {
    public static let listTasks = "list_tasks"
    public static let getTask = "get_task"
    public static let addTask = "add_task"
    public static let completeTask = "complete_task"
    public static let updateTask = "update_task"
    public static let listGroups = "list_groups"
    public static let listLabels = "list_labels"

    public static let defaultLimit = 50
    public static let maxLimit = 200

    public static let serverName = "hitlist"
    public static let serverTitle = "HITList"

    public static let instructions = """
        HITList is the user's personal task list. Tasks have a title, an optional description, a due date \
        (optionally with a time), a priority from p1 (most urgent) to p4 (none), labels (@name), and a Group \
        (#Name; tasks without one are in the Inbox). Task ids are stable UUIDs. The user chooses which tasks \
        you can see; tasks you can't see behave as if they don't exist. Prefer list_tasks with a filter over \
        listing everything. Ask before completing or changing several tasks at once.
        """

    private static let idProperty: JSONValue = ["type": "string", "description": "The task's id (a UUID from list_tasks)."]

    private static func schema(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        var schema: [String: JSONValue] = ["type": "object", "properties": .object(properties), "additionalProperties": false]
        if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
        return .object(schema)
    }

    public static let all: [MCPTool] = [
        MCPTool(
            name: listTasks, title: "List tasks",
            description: """
                Lists the user's tasks, open ones by default, sorted by due date then priority. `filter` uses \
                HITList's filter language (Todoist-like): today, tomorrow, overdue, "7 days", "this week", \
                "no date", p1…p4, #Group, #Inbox, @label, "search: words", recurring, "completed", combined \
                with & (and), | (or), ! (not) and parentheses, e.g. "(today | overdue) & p1" or "#Work & 7 days". \
                Subtasks appear inside their task, not as rows of their own.
                """,
            inputSchema: schema([
                "filter": ["type": "string", "description": "A filter query. Omit for every open task."],
                "include_completed": ["type": "boolean", "description": "Also return completed tasks. Default false."],
                "limit": ["type": "integer", "minimum": 1, "maximum": .int(maxLimit),
                          "description": .string("At most this many tasks (default \(defaultLimit)).")],
            ]),
            readOnly: true),
        MCPTool(
            name: getTask, title: "Get a task",
            description: "One task by id, with its description, labels, Group, dates and subtasks.",
            inputSchema: schema(["id": idProperty], required: ["id"]),
            readOnly: true),
        MCPTool(
            name: addTask, title: "Add a task",
            description: """
                Adds a task from quick-add text, parsed exactly as HITList's own quick add does: dates and \
                times ("tomorrow 3pm", "next fri", "in 2 hours"), repeats ("every monday"), priority (p1…p4), \
                #Group, @label and a reminder offset ("!15mb", needs a time). Words that aren't \
                syntax stay in the title. Example: "Call the dentist tomorrow 9am p2 #Health @phone".
                """,
            inputSchema: schema([
                "text": ["type": "string", "description": "Quick-add text: the title plus any syntax."],
                "description": ["type": "string", "description": "Optional longer notes for the task."],
            ], required: ["text"]),
            readOnly: false),
        MCPTool(
            name: completeTask, title: "Complete a task",
            description: """
                Completes a task (or a subtask). A repeating task isn't marked done: it moves to its next \
                date, as in the app. Completing a task also completes its open subtasks. The user can reopen it in HITList.
                """,
            inputSchema: schema(["id": idProperty], required: ["id"]),
            readOnly: false),
        MCPTool(
            name: updateTask, title: "Update a task",
            description: """
                Changes a task. Give only the fields to change. `due` takes a date phrase as quick add reads \
                it ("friday 5pm", "in 3 days", "every weekday 9am"), or "none" to clear it. `labels` replaces \
                the task's labels. `group` moves it ("Inbox" for none). A subtask takes only title and description.
                """,
            inputSchema: schema([
                "id": idProperty,
                "title": ["type": "string"],
                "description": ["type": "string", "description": "Replaces the description; \"\" clears it."],
                "due": ["type": "string", "description": "A date phrase, or \"none\"."],
                "priority": ["type": "integer", "minimum": 1, "maximum": 4, "description": "1 is most urgent, 4 is none."],
                "labels": ["type": "array", "items": ["type": "string"], "description": "Label names, without @."],
                "group": ["type": "string", "description": "A Group name; created if new. \"Inbox\" for none."],
            ], required: ["id"]),
            readOnly: false),
        MCPTool(
            name: listGroups, title: "List Groups",
            description: "The user's Groups (projects) you can see, with how many open tasks each holds, plus the Inbox.",
            inputSchema: schema([:]),
            readOnly: true),
        MCPTool(
            name: listLabels, title: "List labels",
            description: "The labels you can see, with how many open tasks carry each.",
            inputSchema: schema([:]),
            readOnly: true),
    ]
}
