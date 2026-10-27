import Foundation

/// Suggests completions while typing a task, and learns which project/labels/priority
/// usually go with the words you use.
public struct AutocompleteEngine: Sendable {
    public struct Suggestion: Equatable, Sendable {
        public enum Kind: String, Sendable { case title, project, label, keyword }
        public var kind: Kind
        /// Text shown to the user.
        public var text: String
        /// What to put in place of the word currently being typed.
        public var replacement: String
        public var score: Double
    }

    public struct AttributeSuggestion: Equatable, Sendable {
        public var projectName: String?
        public var labelNames: [String]
        public var priority: Priority?
        /// How many past tasks supported the suggestion.
        public var support: Int
        public var isEmpty: Bool { projectName == nil && labelNames.isEmpty && priority == nil }
    }

    public static let keywordVocabulary: [String] = [
        "today", "tomorrow", "next week", "next month", "this weekend",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "p1", "p2", "p3",
        "every day", "every week", "every month", "every year", "every weekday",
    ]

    static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "to", "for", "of", "in", "on", "at", "with", "my", "up", "out",
        "about", "from", "into", "this", "that", "it", "is", "be", "do", "get", "go", "new", "re",
    ]

    private var titleCounts: [String: (display: String, count: Int)] = [:]
    private var projects: [String]
    private var labels: [String]
    private var keywordProjects: [String: [String: Int]] = [:]
    private var keywordLabels: [String: [String: Int]] = [:]
    private var keywordPriorities: [String: [Int: Int]] = [:]
    private var keywordTotals: [String: Int] = [:]

    public init(tasks: [FilterableTask], projects: [String], labels: [String]) {
        self.projects = projects
        self.labels = labels
        for task in tasks {
            let title = task.filterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let key = title.lowercased()
            let existing = titleCounts[key]
            titleCounts[key] = (existing?.display ?? title, (existing?.count ?? 0) + 1)

            for kw in Self.keywords(in: title) {
                keywordTotals[kw, default: 0] += 1
                if let p = task.filterProjectName { keywordProjects[kw, default: [:]][p, default: 0] += 1 }
                for l in task.filterLabelNames { keywordLabels[kw, default: [:]][l, default: 0] += 1 }
                if task.filterPriority != 4 { keywordPriorities[kw, default: [:]][task.filterPriority, default: 0] += 1 }
            }
        }
    }

    public static func keywords(in text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let w = String(raw)
            guard w.count >= 3, !stopWords.contains(w), !seen.contains(w) else { continue }
            seen.insert(w); out.append(w)
        }
        return out
    }

    // MARK: Inline suggestions

    /// Suggestions for the word at the end of `text` (or at `cursor`).
    public func suggestions(for text: String, cursor: String.Index? = nil, limit: Int = 6) -> [Suggestion] {
        let end = cursor ?? text.endIndex
        let upToCursor = text[..<end]
        guard let lastSpace = upToCursor.lastIndex(where: { $0.isWhitespace }) else {
            return rank(word: String(upToCursor), fullPrefix: String(upToCursor), limit: limit)
        }
        let word = String(upToCursor[upToCursor.index(after: lastSpace)...])
        return rank(word: word, fullPrefix: String(upToCursor), limit: limit)
    }

    private func rank(word: String, fullPrefix: String, limit: Int) -> [Suggestion] {
        let lower = word.lowercased()
        var out: [Suggestion] = []

        if lower.hasPrefix("#") {
            let q = String(lower.dropFirst())
            for p in projects {
                let pl = p.lowercased()
                let score: Double = q.isEmpty ? 1 : (pl.hasPrefix(q) ? 3 : (pl.contains(q) ? 1.5 : 0))
                if score > 0 {
                    let rep = p.contains(" ") ? "#\"\(p)\"" : "#\(p)"
                    out.append(Suggestion(kind: .project, text: p, replacement: rep, score: score))
                }
            }
            return Array(out.sorted { $0.score > $1.score || ($0.score == $1.score && $0.text < $1.text) }.prefix(limit))
        }

        if lower.hasPrefix("@") {
            let q = String(lower.dropFirst())
            for l in labels {
                let ll = l.lowercased()
                let score: Double = q.isEmpty ? 1 : (ll.hasPrefix(q) ? 3 : (ll.contains(q) ? 1.5 : 0))
                if score > 0 { out.append(Suggestion(kind: .label, text: l, replacement: "@\(l)", score: score)) }
            }
            return Array(out.sorted { $0.score > $1.score || ($0.score == $1.score && $0.text < $1.text) }.prefix(limit))
        }

        // Whole-title completions: the typed text so far is a prefix of a past title.
        let typed = fullPrefix.trimmingCharacters(in: .whitespaces).lowercased()
        if typed.count >= 2 {
            for (key, entry) in titleCounts where key.hasPrefix(typed) && key != typed {
                out.append(Suggestion(kind: .title, text: entry.display, replacement: entry.display,
                                      score: 2 + log2(Double(entry.count) + 1)))
            }
        }
        // Keyword completions for the current word (needs at least two characters to be useful).
        if lower.count >= 2 {
            for kw in Self.keywordVocabulary where kw.hasPrefix(lower) && kw != lower {
                out.append(Suggestion(kind: .keyword, text: kw, replacement: kw, score: 1))
            }
        }
        return Array(out.sorted { $0.score > $1.score || ($0.score == $1.score && $0.text < $1.text) }.prefix(limit))
    }

    // MARK: Attribute autofill

    /// Looks at past tasks that share keywords with `title` and proposes the project, labels,
    /// and priority they usually carry. Returns nil when there isn't enough evidence.
    public func attributeSuggestion(forTitle title: String, minimumSupport: Int = 2) -> AttributeSuggestion? {
        let kws = Self.keywords(in: title)
        guard !kws.isEmpty else { return nil }

        var projectVotes: [String: Int] = [:]
        var labelVotes: [String: Int] = [:]
        var priorityVotes: [Int: Int] = [:]
        var total = 0
        for kw in kws {
            guard let n = keywordTotals[kw] else { continue }
            total += n
            for (p, c) in keywordProjects[kw] ?? [:] { projectVotes[p, default: 0] += c }
            for (l, c) in keywordLabels[kw] ?? [:] { labelVotes[l, default: 0] += c }
            for (p, c) in keywordPriorities[kw] ?? [:] { priorityVotes[p, default: 0] += c }
        }
        // An exact prior title counts as strong evidence on its own.
        let exact = titleCounts[title.trimmingCharacters(in: .whitespaces).lowercased()]?.count ?? 0
        guard total >= minimumSupport || exact >= 1 else { return nil }

        var result = AttributeSuggestion(projectName: nil, labelNames: [], priority: nil, support: total)
        if let (p, c) = projectVotes.max(by: { $0.value < $1.value }), Double(c) > Double(total) * 0.5 {
            result.projectName = p
        }
        result.labelNames = labelVotes.filter { Double($0.value) > Double(total) * 0.5 }.keys.sorted()
        if let (p, c) = priorityVotes.max(by: { $0.value < $1.value }), Double(c) > Double(total) * 0.5 {
            result.priority = Priority(rawValue: p)
        }
        return result.isEmpty ? nil : result
    }
}
