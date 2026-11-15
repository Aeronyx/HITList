import Foundation

// Brief 137: Todoist's own files, read without any sign-in. A backup (Todoist → Settings → Backups) is a ZIP with
// one CSV per active project, named like `Work [2301234567].csv`; a project's CSV comes from its ⋯ menu → Import &
// export → Export as CSV. The columns are documented at https://todoist.com/help/articles/360000748525 (Format a
// CSV file to import into Todoist): TYPE (task, section, note; a note is a comment on the task in the row above),
// CONTENT (labels typed as `@name`), DESCRIPTION, PRIORITY (1 = p1, the highest, to 4), INDENT (1 a top task, 2 a
// sub-task, 3 its sub-task, and so on), AUTHOR, RESPONSIBLE, DATE (in words, in the language DATE_LANG names),
// DATE_LANG, TIMEZONE, DURATION (minutes), DURATION_UNIT, `meta` (view_style=board), DEADLINE, DEADLINE_LANG,
// IS_COLLAPSED. Columns are read by name, in any order; ones not known here are passed over.

/// Comma-separated values by RFC 4180: fields in double quotes may hold commas, doubled quotes and line breaks;
/// CRLF or LF ends a row; a byte-order mark at the start is dropped.
public enum TodoistCSV {
    public static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var atFieldStart = true
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        var i = 0
        func endField() { row.append(String(field)); field = String.UnicodeScalarView(); atFieldStart = true }
        func endRow() { endField(); rows.append(row); row = [] }
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"" where atFieldStart: inQuotes = true; atFieldStart = false
                case ",": endField()
                case "\r":
                    if i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 1 }
                    endRow()
                case "\n": endRow()
                default: field.append(c); atFieldStart = false
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty || inQuotes { endRow() }
        return rows
    }
}

/// A task as Todoist wrote it: its words untouched, for `TodoistMapping` to read.
public struct TodoistTask: Equatable, Sendable {
    public var content: String
    public var description: String = ""
    /// 1 (p1, the highest) to 4; nil when the cell was empty.
    public var priority: Int?
    public var indent: Int = 1
    public var responsible: String = ""
    public var date: String = ""
    public var dateLang: String = ""
    public var timeZone: String = ""
    public var duration: String = ""
    public var durationUnit: String = ""
    public var deadline: String = ""
    public var deadlineLang: String = ""
    /// Comments (`note` rows) on this task, in order.
    public var notes: [String] = []
    public var children: [TodoistTask] = []

    public init(content: String) { self.content = content }

    /// This task and every task under it.
    public var count: Int { 1 + children.reduce(0) { $0 + $1.count } }
}

public struct TodoistSection: Equatable, Sendable {
    /// nil: the tasks above the first section.
    public var name: String?
    public var tasks: [TodoistTask] = []
    public init(name: String?, tasks: [TodoistTask] = []) { self.name = name; self.tasks = tasks }
}

public struct TodoistProject: Equatable, Sendable {
    public var name: String
    /// The first is always the unnamed one (tasks before any section), even when empty.
    public var sections: [TodoistSection]
    public init(name: String, sections: [TodoistSection]) { self.name = name; self.sections = sections }

    public var taskCount: Int { sections.reduce(0) { $0 + $1.tasks.reduce(0) { $0 + $1.count } } }
}

public enum TodoistReader {
    public enum ReadError: Error, Equatable, Sendable {
        /// No TYPE and CONTENT columns: not a file Todoist wrote.
        case notTodoist
    }

    /// "Work [2301234567].csv" → "Work": the backup's id in brackets and the extension go; a folder in front goes.
    public static func projectName(fromFileName fileName: String) -> String {
        var name = (fileName as NSString).lastPathComponent
        if name.lowercased().hasSuffix(".csv") { name = String(name.dropLast(4)) }
        if let range = name.range(of: #"\s*\[\d+\]$"#, options: .regularExpression) { name.removeSubrange(range) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Todoist" : trimmed
    }

    public static func read(csv: String, fileName: String) throws -> TodoistProject {
        let rows = TodoistCSV.rows(csv)
        guard let header = rows.first else { throw ReadError.notTodoist }
        var column: [String: Int] = [:]
        for (i, name) in header.enumerated() {
            let key = name.trimmingCharacters(in: .whitespaces).uppercased()
            if column[key] == nil { column[key] = i }
        }
        guard let typeColumn = column["TYPE"], let contentColumn = column["CONTENT"] else { throw ReadError.notTodoist }
        func cell(_ row: [String], _ key: String) -> String {
            guard let i = column[key], i < row.count else { return "" }
            return row[i]
        }

        var sections = [TodoistSection(name: nil)]
        // The path from the current section's top task down to the last task read: index paths into `tasks`.
        var stack: [(indent: Int, path: [Int])] = []
        var lastTaskPath: [Int]?

        func mutate(_ path: [Int], _ change: (inout TodoistTask) -> Void) {
            func walk(_ tasks: inout [TodoistTask], _ rest: ArraySlice<Int>) {
                guard let head = rest.first else { return }
                if rest.count == 1 { change(&tasks[head]) } else { walk(&tasks[head].children, rest.dropFirst()) }
            }
            walk(&sections[sections.count - 1].tasks, path[...])
        }
        func childCount(_ path: [Int]) -> Int {
            var tasks = sections[sections.count - 1].tasks
            for i in path { tasks = tasks[i].children }
            return tasks.count
        }

        for row in rows.dropFirst() {
            let type = (typeColumn < row.count ? row[typeColumn] : "").trimmingCharacters(in: .whitespaces).lowercased()
            let content = contentColumn < row.count ? row[contentColumn] : ""
            switch type {
            case "section":
                sections.append(TodoistSection(name: content.trimmingCharacters(in: .whitespacesAndNewlines)))
                stack = []
                lastTaskPath = nil
            case "task":
                var task = TodoistTask(content: content.trimmingCharacters(in: .whitespacesAndNewlines))
                task.description = cell(row, "DESCRIPTION").trimmingCharacters(in: .whitespacesAndNewlines)
                task.priority = Int(cell(row, "PRIORITY").trimmingCharacters(in: .whitespaces))
                task.indent = max(1, Int(cell(row, "INDENT").trimmingCharacters(in: .whitespaces)) ?? 1)
                task.responsible = cell(row, "RESPONSIBLE").trimmingCharacters(in: .whitespaces)
                task.date = cell(row, "DATE").trimmingCharacters(in: .whitespacesAndNewlines)
                task.dateLang = cell(row, "DATE_LANG").trimmingCharacters(in: .whitespaces)
                task.timeZone = cell(row, "TIMEZONE").trimmingCharacters(in: .whitespaces)
                task.duration = cell(row, "DURATION").trimmingCharacters(in: .whitespaces)
                task.durationUnit = cell(row, "DURATION_UNIT").trimmingCharacters(in: .whitespaces)
                task.deadline = cell(row, "DEADLINE").trimmingCharacters(in: .whitespacesAndNewlines)
                task.deadlineLang = cell(row, "DEADLINE_LANG").trimmingCharacters(in: .whitespaces)
                guard !task.content.isEmpty else { continue }
                while let last = stack.last, last.indent >= task.indent { stack.removeLast() }
                let path: [Int]
                if let parent = stack.last {
                    path = parent.path + [childCount(parent.path)]
                    mutate(parent.path) { $0.children.append(task) }
                } else {
                    path = [sections[sections.count - 1].tasks.count]
                    sections[sections.count - 1].tasks.append(task)
                }
                stack.append((task.indent, path))
                lastTaskPath = path
            case "note":
                let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let path = lastTaskPath, !text.isEmpty else { continue }
                mutate(path) { $0.notes.append(text) }
            default:
                continue // blank rows, `meta`, and anything a later Todoist adds
            }
        }
        return TodoistProject(name: projectName(fromFileName: fileName), sections: sections)
    }
}
