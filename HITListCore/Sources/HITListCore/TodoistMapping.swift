import Foundation

/// The one switch the preview shows.
public struct TodoistImportOptions: Equatable, Sendable {
    /// A Todoist section becomes a label named after it; off, the section's name goes in each task's notes.
    public var sectionsAsLabels: Bool
    public init(sectionsAsLabels: Bool = true) { self.sectionsAsLabels = sectionsAsLabels }
}

/// What is already in HITList, so the plan uses it and doubles nothing.
public struct TodoistExisting: Sendable {
    public struct OpenTask: Hashable, Sendable {
        public var title: String
        /// nil: the Inbox.
        public var groupName: String?
        public init(title: String, groupName: String?) { self.title = title; self.groupName = groupName }
    }
    public var groupNames: [String]
    public var labelNames: [String]
    /// Tasks not completed, any level.
    public var openTasks: [OpenTask]
    public init(groupNames: [String] = [], labelNames: [String] = [], openTasks: [OpenTask] = []) {
        self.groupNames = groupNames
        self.labelNames = labelNames
        self.openTasks = openTasks
    }
}

/// A task HITList will make.
public struct TodoistPlannedTask: Equatable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    /// nil: the Inbox. Otherwise the Group's name as HITList has it (an existing Group's own spelling).
    public var groupName: String?
    public var labels: [String] = []
    public var priority: Priority = .p4
    public var due: Date?
    public var hasDueTime = false
    public var recurrence: RecurrenceRule?
    /// The start of its day.
    public var deadline: Date?
    public var notes = ""
    /// Sub-tasks with nothing of their own, as checklist lines in order ("Bread", "Bread › Sourdough").
    public var checklist: [String] = []
    /// The DATE words HITList could not read; the task comes in without a date.
    public var unreadDate: String?
    /// The Todoist project it came from.
    public var projectName: String
}

public struct TodoistPlan: Equatable, Sendable {
    public enum Destination: Equatable, Sendable {
        case inbox
        case newGroup(String)
        case existingGroup(String)
    }
    public struct ProjectLine: Equatable, Sendable, Identifiable {
        public var name: String
        public var destination: Destination
        /// Tasks to be made from it (skipped ones not counted).
        public var taskCount: Int
        public var id: String { name }
        public init(name: String, destination: Destination, taskCount: Int) {
            self.name = name
            self.destination = destination
            self.taskCount = taskCount
        }
    }

    public var projects: [ProjectLine] = []
    public var tasks: [TodoistPlannedTask] = []
    /// Already in HITList (same title, same Group, not completed): not made again.
    public var skipped: [TodoistPlannedTask] = []
    /// Labels that do not exist yet, in the order first met.
    public var labelsToMake: [String] = []
    public var checklistLineCount = 0
    /// Sub-tasks with a date, priority or label of their own, made tasks with "Under: <parent>" in their notes.
    public var subtasksAsTasks = 0
    public var headingCount = 0
    /// Every choice the mapping made, in plain words, for the preview.
    public var choices: [String] = []

    public var taskCount: Int { tasks.count }
    public var repeatingCount: Int { tasks.filter { $0.recurrence != nil }.count }
    public var unreadDates: [TodoistPlannedTask] { tasks.filter { $0.unreadDate != nil } }
    /// The files held no tasks at all.
    public var isEmpty: Bool { tasks.isEmpty && skipped.isEmpty }
    public var groupsToMake: [String] {
        projects.compactMap { if case .newGroup(let name) = $0.destination, $0.taskCount > 0 { return name } else { return nil } }
    }
}

/// Brief 137: Todoist's tree into HITList's shapes. Pure: the app writes what `plan` returns.
public enum TodoistMapping {
    public static let inboxName = "Inbox"
    public static let checklistSeparator = " › "

    public static func plan(_ projects: [TodoistProject], existing: TodoistExisting,
                            options: TodoistImportOptions = TodoistImportOptions(),
                            dates: TodoistDateReader = TodoistDateReader()) -> TodoistPlan {
        var plan = TodoistPlan()
        func key(_ s: String) -> String { s.lowercased() }
        var groupSpelling: [String: String] = [:]
        for name in existing.groupNames where groupSpelling[key(name)] == nil { groupSpelling[key(name)] = name }
        var labelSpelling: [String: String] = [:]
        for name in existing.labelNames where labelSpelling[key(name)] == nil { labelSpelling[key(name)] = name }
        var open = Set(existing.openTasks.map { TodoistExisting.OpenTask(title: key($0.title), groupName: $0.groupName.map(key)) })
        var nextID = 0
        var sectionLabels: [String] = []
        var sectionsInNotes = 0

        for project in projects {
            let isInbox = key(project.name) == key(inboxName)
            let destination: TodoistPlan.Destination
            let groupName: String?
            if isInbox {
                destination = .inbox
                groupName = nil
            } else if let existingName = groupSpelling[key(project.name)] {
                destination = .existingGroup(existingName)
                groupName = existingName
            } else {
                destination = .newGroup(project.name)
                groupName = project.name
                groupSpelling[key(project.name)] = project.name
            }
            var made = 0

            for section in project.sections {
                var queue: [(task: TodoistTask, under: String?)] = section.tasks.map { ($0, nil) }
                while !queue.isEmpty {
                    let (source, under) = queue.removeFirst()
                    var task = TodoistPlannedTask(id: nextID, title: "", groupName: groupName, projectName: project.name)
                    nextID += 1
                    var title = source.content
                    var labels: [String] = []
                    let isHeading = title.hasPrefix("* ")
                    if isHeading { title = String(title.dropFirst(2)) }
                    (title, labels) = splitLabels(title)
                    if isHeading { labels = [] }
                    if let name = section.name, !name.isEmpty, !isHeading {
                        if options.sectionsAsLabels {
                            labels.append(name)
                            if !sectionLabels.contains(name) { sectionLabels.append(name) }
                        }
                    }
                    task.title = TaskLimits.clampedTitle(TaskLimits.singleLine(title))
                    if task.title.isEmpty { task.title = TaskLimits.clampedTitle(TaskLimits.singleLine(source.content)) }
                    if let p = source.priority { task.priority = Priority(clamping: p) }

                    var notes: [String] = []
                    var tail: [String] = []
                    if !source.date.isEmpty {
                        if let reading = dates.read(source.date, language: source.dateLang, timeZone: source.timeZone) {
                            task.due = reading.due
                            task.hasDueTime = reading.hasTime
                            task.recurrence = reading.recurrence // as quick add stores it (TaskActions.create)
                            tail += reading.notes
                        } else {
                            task.unreadDate = source.date
                            notes.append("Todoist date: \(source.date)")
                        }
                    }
                    if !source.description.isEmpty { notes.append(source.description) }
                    notes += source.notes

                    // Sub-tasks: nothing of their own → a checklist line ("A › B"); anything of their own → a task.
                    func walk(_ children: [TodoistTask], path: [String]) {
                        for child in children {
                            let childTitle = splitLabels(child.content).title
                            if hasOwn(child) {
                                queue.insert((child, task.title), at: 0)
                                plan.subtasksAsTasks += 1
                                continue
                            }
                            let line = (path + [childTitle]).joined(separator: checklistSeparator)
                            task.checklist.append(TaskLimits.clampedTitle(TaskLimits.singleLine(line)))
                            plan.checklistLineCount += 1
                            if !child.description.isEmpty { notes.append("\(line): \(child.description)") }
                            for comment in child.notes { notes.append("\(line): \(comment)") }
                            walk(child.children, path: path + [childTitle])
                        }
                    }
                    let checklistBefore = plan.checklistLineCount
                    let tasksBefore = plan.subtasksAsTasks
                    let queueBefore = queue.count
                    walk(source.children, path: [])
                    // Children made tasks are queued in reverse; put them back in file order, right after this one.
                    let added = queue.count - queueBefore
                    if added > 1 { queue[0..<added].reverse() }

                    if !source.deadline.isEmpty {
                        if let reading = dates.read(source.deadline, language: source.deadlineLang), reading.recurrence == nil,
                           let day = reading.due {
                            task.deadline = dates.calendar.startOfDay(for: day)
                        } else {
                            notes.append("Todoist deadline: \(source.deadline)")
                        }
                    }
                    notes += tail
                    if let minutes = Int(source.duration), minutes > 0 {
                        let unit = source.durationUnit.lowercased().hasPrefix("day") ? "day" : "minute"
                        notes.append("Duration in Todoist: \(minutes) \(unit)\(minutes == 1 ? "" : "s")")
                    }
                    let assignee = source.responsible.replacingOccurrences(of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
                    if !assignee.isEmpty { notes.append("Assigned in Todoist to \(assignee)") }
                    if let under { notes.append("Under: \(under)") }
                    if isHeading {
                        notes.append("Heading in Todoist")
                        plan.headingCount += 1
                    }
                    if let name = section.name, !name.isEmpty, !options.sectionsAsLabels {
                        notes.append("Section in Todoist: \(name)")
                        sectionsInNotes += 1
                    }
                    task.notes = notes.joined(separator: "\n")

                    // Labels: an existing one's spelling, each once.
                    var seen = Set<String>()
                    task.labels = labels.compactMap { name in
                        guard seen.insert(key(name)).inserted else { return nil }
                        return labelSpelling[key(name)] ?? name
                    }

                    let openKey = TodoistExisting.OpenTask(title: key(task.title), groupName: groupName.map(key))
                    if open.contains(openKey) {
                        plan.skipped.append(task)
                        // Its sub-tasks were counted for a task that will not be made.
                        plan.checklistLineCount = checklistBefore
                        plan.subtasksAsTasks = tasksBefore
                        if added > 0 { queue.removeFirst(added) }
                        continue
                    }
                    open.insert(openKey)
                    for name in task.labels where labelSpelling[key(name)] == nil {
                        labelSpelling[key(name)] = name
                        plan.labelsToMake.append(name)
                    }
                    plan.tasks.append(task)
                    made += 1
                }
            }
            plan.projects.append(TodoistPlan.ProjectLine(name: project.name, destination: destination, taskCount: made))
        }

        plan.choices = choices(plan, sectionLabels: sectionLabels, sectionsInNotes: sectionsInNotes)
        return plan
    }

    /// "Pay rent @home @bills" → ("Pay rent", ["home", "bills"]): a word starting with @ is a label and leaves the title.
    static func splitLabels(_ content: String) -> (title: String, labels: [String]) {
        var labels: [String] = []
        var words: [Substring] = []
        for word in content.split(separator: " ", omittingEmptySubsequences: true) {
            if word.hasPrefix("@"), word.count > 1 {
                labels.append(String(word.dropFirst()))
            } else {
                words.append(word)
            }
        }
        return (words.joined(separator: " "), labels)
    }

    /// A sub-task with a date, a priority or a label of its own cannot be a checklist line.
    static func hasOwn(_ task: TodoistTask) -> Bool {
        !task.date.isEmpty || (task.priority.map { $0 < 4 } ?? false) || !splitLabels(task.content).labels.isEmpty
    }

    private static func choices(_ plan: TodoistPlan, sectionLabels: [String], sectionsInNotes: Int) -> [String] {
        var lines: [String] = []
        for project in plan.projects {
            switch project.destination {
            case .inbox: lines.append("\(project.name) goes to your Inbox.")
            case .newGroup(let name): lines.append("\(project.name) becomes a new Group, \(name).")
            case .existingGroup(let name): lines.append("\(project.name) goes into your Group \(name).")
            }
        }
        if !sectionLabels.isEmpty { lines.append("Sections become labels: \(sectionLabels.joined(separator: ", ")).") }
        if sectionsInNotes > 0 { lines.append("Sections are kept in the notes of \(count(sectionsInNotes, "task")).") }
        if plan.checklistLineCount > 0 {
            lines.append("\(count(plan.checklistLineCount, "sub-task")) with nothing of their own become checklist lines.")
        }
        if plan.subtasksAsTasks > 0 {
            lines.append("\(count(plan.subtasksAsTasks, "sub-task")) with a date, priority or label of their own become tasks, with \"Under:\" in their notes.")
        }
        if plan.headingCount > 0 { lines.append("\(count(plan.headingCount, "heading")) come in as tasks, the star removed.") }
        let unread = plan.unreadDates.count
        if unread > 0 { lines.append("\(count(unread, "date")) HITList could not read: the words are kept in the notes.") }
        if !plan.skipped.isEmpty { lines.append("\(count(plan.skipped.count, "task")) already in HITList are skipped.") }
        return lines
    }

    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}
