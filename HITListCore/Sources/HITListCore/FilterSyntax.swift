import Foundation

/// One keyword of the filter language, with a one-line explanation and a runnable example.
public struct FilterSyntaxEntry: Sendable, Equatable, Identifiable {
    public enum Category: String, Sendable, CaseIterable {
        case dates = "Dates"
        case priority = "Priority"
        case places = "Projects & labels"
        case text = "Text"
        case state = "State"
        case operators = "Operators"
    }

    public let keyword: String
    public let summary: String
    /// A complete query that parses; a test keeps every example valid.
    public let example: String
    public let category: Category
    /// Text autocomplete may insert for this entry, most useful first. Empty for entries that are
    /// explanations only (date formats, quoting, wildcards).
    public let completions: [String]

    public var id: String { keyword }
}

/// The single table behind the editor's Syntax help, filter autocomplete and "did you mean" hints,
/// so the three can't drift apart.
public enum FilterSyntax {
    public static let entries: [FilterSyntaxEntry] = [
        // Dates
        .init(keyword: "today", summary: "Due today", example: "today | overdue", category: .dates, completions: ["today"]),
        .init(keyword: "tomorrow", summary: "Due tomorrow", example: "tomorrow & @errand", category: .dates, completions: ["tomorrow"]),
        .init(keyword: "yesterday", summary: "Due yesterday", example: "yesterday", category: .dates, completions: ["yesterday"]),
        .init(keyword: "overdue", summary: "Past due (also od, over due)", example: "overdue & p1", category: .dates, completions: ["overdue"]),
        .init(keyword: "N days", summary: "Due today or in the next N days (also next N days, N weeks)", example: "7 days & @waiting", category: .dates, completions: ["7 days", "next 7 days", "14 days"]),
        .init(keyword: "-N days", summary: "Due today or in the past N days", example: "-3 days", category: .dates, completions: ["-7 days"]),
        .init(keyword: "this week, next week", summary: "Due this or next calendar week (weeks start Monday)", example: "next week", category: .dates, completions: ["this week", "next week"]),
        .init(keyword: "this month, next month", summary: "Due this or next calendar month", example: "this month & p1", category: .dates, completions: ["this month", "next month"]),
        .init(keyword: "this weekend, next weekend", summary: "Due on the coming weekend, or the one after", example: "this weekend", category: .dates, completions: ["this weekend", "next weekend"]),
        .init(keyword: "monday … sunday", summary: "Due on the next such weekday", example: "saturday & @night", category: .dates, completions: ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]),
        .init(keyword: "jan 3, 10/31, 2026-10-31", summary: "Due on a date; a month name alone means the whole month", example: "jan 3 | october", category: .dates, completions: []),
        .init(keyword: "a..b", summary: "Due within a range of dates, both ends included", example: "today..friday", category: .dates, completions: []),
        .init(keyword: "due:", summary: "Due on a date (also date:)", example: "due: next monday", category: .dates, completions: ["due: "]),
        .init(keyword: "due before:", summary: "Due before a date or time (also date before:)", example: "due before: +4 hours", category: .dates, completions: ["due before: "]),
        .init(keyword: "due after:", summary: "Due after a date or time (also date after:)", example: "due after: today & due before: next week", category: .dates, completions: ["due after: "]),
        .init(keyword: "+N days, -N hours", summary: "A date or time relative to now, for due:/created:", example: "due before: +7 days", category: .dates, completions: []),
        .init(keyword: "N days after <date>", summary: "A date counted from another date", example: "due before: 1 week after next week", category: .dates, completions: []),
        .init(keyword: "no date", summary: "No due date (also no due date)", example: "#Work & no date", category: .dates, completions: ["no date"]),
        .init(keyword: "has date", summary: "Has a due date (same as !no date)", example: "!no date & p1", category: .dates, completions: ["has date"]),
        .init(keyword: "no time", summary: "Has a due date but no time", example: "today & no time", category: .dates, completions: ["no time"]),
        .init(keyword: "has time", summary: "Has a due time", example: "overdue & has time", category: .dates, completions: ["has time"]),
        .init(keyword: "recurring", summary: "Repeats; !recurring for one-off tasks", example: "no time & !recurring", category: .dates, completions: ["recurring"]),
        .init(keyword: "created:", summary: "Created on a date", example: "created: today", category: .dates, completions: ["created: "]),
        .init(keyword: "created before:", summary: "Created before a date", example: "created before: -30 days", category: .dates, completions: ["created before: "]),
        .init(keyword: "created after:", summary: "Created after a date", example: "created after: -7 days", category: .dates, completions: ["created after: "]),

        // Priority
        .init(keyword: "p1 … p4", summary: "Priority 1 (most urgent) to 4 (none)", example: "(p1 | p2) & 14 days", category: .priority, completions: ["p1", "p2", "p3", "p4"]),
        .init(keyword: "priority", summary: "Compare with = != < <= > >=; lower numbers are more urgent", example: "priority <= 2", category: .priority, completions: ["priority <= ", "priority >= "]),
        .init(keyword: "no priority", summary: "Same as p4", example: "no priority & no date", category: .priority, completions: ["no priority"]),

        // Projects & labels
        .init(keyword: "#Project", summary: "In a project (## also works)", example: "#Work & today", category: .places, completions: ["#"]),
        .init(keyword: "#\"Two words\"", summary: "Quote names with spaces, or escape the space with \\", example: "#\"Home Repairs\" | #Shopping\\ list", category: .places, completions: []),
        .init(keyword: "#Inbox", summary: "Tasks without a project", example: "!#Inbox", category: .places, completions: ["#Inbox"]),
        .init(keyword: "no project", summary: "Same as #Inbox", example: "no project & p1", category: .places, completions: ["no project"]),
        .init(keyword: "@label", summary: "Has a label (%label also works)", example: "today & @email", category: .places, completions: ["@"]),
        .init(keyword: "no labels", summary: "Has no labels", example: "no labels & #Work", category: .places, completions: ["no labels"]),
        .init(keyword: "*", summary: "Wildcard in project, label and search text", example: "@home* | #*Work", category: .places, completions: []),

        // Text
        .init(keyword: "search:", summary: "Title or notes contain every word, in any order", example: "search: send email", category: .text, completions: ["search: "]),
        .init(keyword: "search: \"…\"", summary: "Title or notes contain the exact phrase", example: "search: \"exact phrase\"", category: .text, completions: []),
        .init(keyword: "\"text\"", summary: "Shortcut for search", example: "\"dentist\" | @health", category: .text, completions: []),

        // State
        .init(keyword: "all", summary: "Every open task (also view all)", example: "all & !#Inbox", category: .state, completions: ["all"]),
        .init(keyword: "completed", summary: "Completed tasks; they are hidden unless the query mentions completed", example: "completed & #Work", category: .state, completions: ["completed"]),

        // Operators
        .init(keyword: "&", summary: "Both sides match (a comma works too)", example: "today & p1", category: .operators, completions: ["& "]),
        .init(keyword: "|", summary: "Either side matches; & binds tighter", example: "today | overdue", category: .operators, completions: ["| "]),
        .init(keyword: "!", summary: "Not", example: "today & !#Work", category: .operators, completions: ["!"]),
        .init(keyword: "( )", summary: "Group terms", example: "(today | overdue) & #Work", category: .operators, completions: ["("]),
        .init(keyword: "\\", summary: "Treat the next character in a name as text", example: "#One\\ \\&\\ Two", category: .operators, completions: []),
    ]

    /// Date phrases offered after `due:`, `due before:`, `created:` and the like.
    public static let dateCompletions: [String] = [
        "today", "tomorrow", "yesterday", "next week", "this week", "next month",
        "this weekend", "next weekend", "monday", "tuesday", "wednesday", "thursday", "friday",
        "saturday", "sunday", "+4 hours", "+7 days", "-7 days", "-30 days", "today at 5pm", "first day",
    ]

    /// Single words the parser understands, in the order "did you mean" prefers them on a tie.
    static let vocabulary: [String] = [
        "today", "tomorrow", "yesterday", "overdue", "all", "completed", "recurring", "weekend",
        "priority", "search", "created", "due", "date", "next", "this", "view", "before", "after",
        "time", "project", "labels", "week", "month", "days", "weeks",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "june", "july", "august", "september", "october",
        "november", "december",
    ]

    /// The closest candidate within a small edit distance, for "Did you mean …?" hints.
    static func closest(to word: String, in candidates: [String] = vocabulary) -> String? {
        let w = word.lowercased()
        guard w.count >= 3 else { return nil }
        let allowed = w.count <= 4 ? 1 : 2
        var best: (String, Int)? = nil
        for c in candidates where c != w {
            let d = editDistance(w, c)
            if d <= allowed, d < (best?.1 ?? .max) { best = (c, d) }
        }
        return best?.0
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var row = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                row[j] = min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = row
        }
        return prev[b.count]
    }
}

/// `*` wildcard matching, case-insensitive.
enum Glob {
    /// Whole-string match: `Work*`, `*Work`, `*or*`. Without `*` it is a plain case-insensitive compare.
    static func matches(_ pattern: String, _ text: String) -> Bool {
        guard pattern.contains("*") else { return pattern.caseInsensitiveCompare(text) == .orderedSame }
        return match(pattern, text, anchored: true)
    }

    /// Substring match, where `*` stands for any run of characters.
    static func contains(_ pattern: String, in text: String) -> Bool {
        guard pattern.contains("*") else { return text.localizedCaseInsensitiveContains(pattern) }
        return match(pattern, text, anchored: false)
    }

    private static func match(_ pattern: String, _ text: String, anchored: Bool) -> Bool {
        let pieces = pattern.lowercased().split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        var rest = Substring(text.lowercased())
        for (i, piece) in pieces.enumerated() {
            if piece.isEmpty { continue }
            if i == 0 && anchored {
                guard rest.hasPrefix(piece) else { return false }
                rest = rest.dropFirst(piece.count)
            } else if i == pieces.count - 1 && anchored {
                return rest.hasSuffix(piece)
            } else {
                guard let r = rest.range(of: piece) else { return false }
                rest = rest[r.upperBound...]
            }
        }
        return true
    }
}
