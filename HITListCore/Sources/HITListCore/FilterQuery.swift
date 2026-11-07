import Foundation

// MARK: - Errors

public struct FilterQueryError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    /// Character offset into the source where the problem was detected.
    public let position: Int
    /// How many characters the problem spans; 0 when it points between characters (e.g. at the end).
    public let length: Int

    public init(message: String, position: Int, length: Int = 0) {
        self.message = message
        self.position = position
        self.length = length
    }

    public var errorDescription: String? { message }

    /// The offending characters as offsets into `source`, clamped to its length.
    public func range(in source: String) -> Range<Int> {
        let count = source.count
        let lower = min(max(position, 0), count)
        return lower..<min(lower + max(length, 0), count)
    }
}

// MARK: - AST

public enum ComparisonOp: String, Sendable, Equatable {
    case eq = "=", ne = "!=", lt = "<", le = "<=", gt = ">", ge = ">="

    func test(_ lhs: Int, _ rhs: Int) -> Bool {
        switch self {
        case .eq: return lhs == rhs
        case .ne: return lhs != rhs
        case .lt: return lhs < rhs
        case .le: return lhs <= rhs
        case .gt: return lhs > rhs
        case .ge: return lhs >= rhs
        }
    }
}

/// Units for relative dates such as `+4 hours` and `1 week after next week`.
public enum DateUnit: String, Sendable, Hashable {
    case minute, hour, day, week, month, year

    var component: Calendar.Component {
        switch self {
        case .minute: return .minute
        case .hour: return .hour
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    /// Minutes and hours resolve to an instant; the rest to a whole day.
    var isTimeOfDay: Bool { self == .minute || self == .hour }

    init?(word: String) {
        switch word {
        case "min", "mins", "minute", "minutes": self = .minute
        case "h", "hr", "hrs", "hour", "hours": self = .hour
        case "d", "day", "days": self = .day
        case "w", "wk", "wks", "week", "weeks": self = .week
        case "mo", "mos", "month", "months": self = .month
        case "y", "yr", "yrs", "year", "years": self = .year
        default: return nil
        }
    }

    func name(_ count: Int) -> String { count == 1 ? rawValue : rawValue + "s" }
}

/// A date reference that is resolved at evaluation time so saved filters stay correct across days.
public indirect enum DateTerm: Sendable, Hashable {
    case today, tomorrow, yesterday
    /// Today plus the following `n` days.
    case nextDays(Int)
    /// The past `n` days plus today.
    case lastDays(Int)
    case thisWeek, nextWeek, thisMonth, nextMonth
    /// This coming weekend (the current one on Saturday and Sunday).
    case weekend
    case nextWeekend
    /// A whole named month, 1...12: this year's unless it is already over.
    case month(Int)
    /// Todoist's `first day`: the 1st of next month.
    case firstDayOfNextMonth
    /// `+4 hours`, `-365 days`. Minutes and hours are an instant; larger units a whole day.
    case relative(Int, DateUnit)
    /// `1 week after next week`, `8 days before sunday` (negative counts are "before").
    case shifted(Int, DateUnit, DateTerm)
    /// `today..friday`: from the start of the first to the end of the second.
    case range(DateTerm, DateTerm)
    /// Free-form phrase understood by `DateExpressionParser`, e.g. "next mon", "jan 5", "today at 2pm".
    case expression(String)
}

public indirect enum FilterNode: Sendable, Equatable {
    case all
    case and(FilterNode, FilterNode)
    case or(FilterNode, FilterNode)
    case not(FilterNode)
    case priority(ComparisonOp, Int)
    case dueOn(DateTerm)
    case dueBefore(DateTerm)
    case dueAfter(DateTerm)
    case overdue
    case noDate
    case hasTime(Bool)
    /// `nil` means "no project". Names may contain `*` wildcards; `Inbox` also matches "no project".
    case project(String?)
    /// `nil` means "no labels". Names may contain `*` wildcards.
    case label(String?)
    /// Title or notes contain the text (case-insensitive, `*` wildcards).
    case search(String)
    case completed(Bool)
    case recurring
    case createdOn(DateTerm)
    case createdBefore(DateTerm)
    case createdAfter(DateTerm)
}

// MARK: - Tokenizer

enum FilterToken: Equatable {
    case lparen, rparen, and, or, not, colon
    case op(ComparisonOp)
    case project(String)
    case label(String)
    /// `/Section`: tokenized only to explain that HITList has no sections.
    case section(String)
    case quoted(String)
    case word(String)
}

struct PositionedToken {
    let token: FilterToken
    let position: Int
    let length: Int
    var end: Int { position + length }
}

struct FilterTokenizer {
    static func tokenize(_ source: String) throws -> [PositionedToken] {
        var tokens: [PositionedToken] = []
        let chars = Array(source)
        var i = 0

        func isWordChar(_ c: Character) -> Bool {
            !(c.isWhitespace || "()&|,!:<>=\"".contains(c))
        }

        func add(_ token: FilterToken, _ start: Int, _ end: Int) {
            tokens.append(PositionedToken(token: token, position: start, length: end - start))
        }

        func readQuoted(from start: Int) throws -> (String, Int) {
            var j = start + 1
            var s = ""
            while j < chars.count, chars[j] != "\"" {
                if chars[j] == "\\", j + 1 < chars.count { j += 1 }
                s.append(chars[j]); j += 1
            }
            guard j < chars.count else {
                throw FilterQueryError(message: "Missing closing quote", position: start, length: chars.count - start)
            }
            return (s, j + 1)
        }

        /// A run of word characters; `\` makes the next character part of the word, even a space.
        func readWord(from start: Int) -> (String, Int) {
            var j = start
            var s = ""
            while j < chars.count {
                if chars[j] == "\\", j + 1 < chars.count {
                    s.append(chars[j + 1]); j += 2; continue
                }
                guard isWordChar(chars[j]) else { break }
                s.append(chars[j]); j += 1
            }
            return (s, j)
        }

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            switch c {
            case "(": add(.lparen, i, i + 1); i += 1
            case ")": add(.rparen, i, i + 1); i += 1
            case "&", ",": add(.and, i, i + 1); i += 1
            case "|": add(.or, i, i + 1); i += 1
            case ":": add(.colon, i, i + 1); i += 1
            case "!":
                if i + 1 < chars.count, chars[i + 1] == "=" {
                    add(.op(.ne), i, i + 2); i += 2
                } else {
                    add(.not, i, i + 1); i += 1
                }
            case "<", ">", "=":
                let double = i + 1 < chars.count && chars[i + 1] == "="
                let op: ComparisonOp
                switch c {
                case "<": op = double ? .le : .lt
                case ">": op = double ? .ge : .gt
                default: op = .eq
                }
                add(.op(op), i, i + (double ? 2 : 1)); i += double ? 2 : 1
            case "\"":
                let (s, j) = try readQuoted(from: i)
                add(.quoted(s), i, j); i = j
            case "#", "@", "%", "/":
                let start = i
                var j = i + 1
                if c == "#", j < chars.count, chars[j] == "#" { j += 1 } // ##Project: no sub-projects, same as #
                let name: String
                if j < chars.count, chars[j] == "\"" {
                    (name, j) = try readQuoted(from: j)
                } else {
                    (name, j) = readWord(from: j)
                }
                guard !name.isEmpty else {
                    let what = c == "#" ? "a project name" : (c == "/" ? "a section name" : "a label name")
                    throw FilterQueryError(message: "Expected \(what) after '\(c)'", position: start, length: j - start)
                }
                let token: FilterToken = c == "#" ? .project(name) : (c == "/" ? .section(name) : .label(name))
                add(token, start, j)
                i = j
            default:
                let (w, j) = readWord(from: i)
                add(.word(w.lowercased()), i, j)
                i = j
            }
        }
        return tokens
    }
}

// MARK: - Parser

struct FilterParser {
    private let tokens: [PositionedToken]
    private var index = 0
    private let dateParser: DateExpressionParser

    init(tokens: [PositionedToken], dateParser: DateExpressionParser) {
        self.tokens = tokens
        self.dateParser = dateParser
    }

    static func parse(_ source: String, dateParser: DateExpressionParser) throws -> FilterNode {
        let tokens = try FilterTokenizer.tokenize(source)
        guard !tokens.isEmpty else {
            throw FilterQueryError(message: "Filter is empty", position: 0)
        }
        var parser = FilterParser(tokens: tokens, dateParser: dateParser)
        let node = try parser.parseOr()
        if parser.index < tokens.count {
            let t = tokens[parser.index]
            if t.token == .rparen {
                throw FilterQueryError(message: "This ')' has no matching '('", position: t.position, length: t.length)
            }
            throw FilterQueryError(message: "Unexpected \(describe(t.token)). Join terms with & or |",
                                   position: t.position, length: t.length)
        }
        return node
    }

    private var current: FilterToken? { index < tokens.count ? tokens[index].token : nil }
    private var currentToken: PositionedToken? { index < tokens.count ? tokens[index] : nil }
    /// Where the next token starts, or the end of the last one.
    private var position: Int { index < tokens.count ? tokens[index].position : (tokens.last?.end ?? 0) }
    /// The end of the token just consumed.
    private var previousEnd: Int { index > 0 ? tokens[index - 1].end : 0 }

    private func peekWord(_ offset: Int = 0) -> String? {
        guard index + offset < tokens.count, case .word(let w) = tokens[index + offset].token else { return nil }
        return w
    }

    private mutating func advance() { index += 1 }

    static func describe(_ token: FilterToken) -> String {
        switch token {
        case .lparen: return "'('"
        case .rparen: return "')'"
        case .and: return "'&'"
        case .or: return "'|'"
        case .not: return "'!'"
        case .colon: return "':'"
        case .op(let op): return "'\(op.rawValue)'"
        case .project(let p): return "'#\(p)'"
        case .label(let l): return "'@\(l)'"
        case .section(let s): return "'/\(s)'"
        case .quoted(let q): return "\"\(q)\""
        case .word(let w): return "'\(w)'"
        }
    }

    /// An error covering tokens `from` (an index) through the last consumed token.
    private func error(_ message: String, from first: Int) -> FilterQueryError {
        let start = tokens[first].position
        return FilterQueryError(message: message, position: start, length: max(previousEnd - start, tokens[first].length))
    }

    private func error(_ message: String, at token: PositionedToken) -> FilterQueryError {
        FilterQueryError(message: message, position: token.position, length: token.length)
    }

    /// An error pointing at the next token, or just past the end when there is none.
    private func errorHere(_ message: String) -> FilterQueryError {
        if let t = currentToken { return error(message, at: t) }
        return FilterQueryError(message: message, position: previousEnd)
    }

    private mutating func parseOr() throws -> FilterNode {
        var lhs = try parseAnd()
        while current == .or {
            advance()
            if current == nil { throw FilterQueryError(message: "Expected a term after '|'", position: tokens[index - 1].position, length: 1) }
            let rhs = try parseAnd()
            lhs = .or(lhs, rhs)
        }
        return lhs
    }

    private mutating func parseAnd() throws -> FilterNode {
        var lhs = try parseNot()
        while current == .and {
            advance()
            if current == nil { throw FilterQueryError(message: "Expected a term after '&'", position: tokens[index - 1].position, length: 1) }
            let rhs = try parseNot()
            lhs = .and(lhs, rhs)
        }
        return lhs
    }

    private mutating func parseNot() throws -> FilterNode {
        if current == .not {
            advance()
            if current == nil { throw FilterQueryError(message: "Expected a term after '!'", position: tokens[index - 1].position, length: 1) }
            return .not(try parseNot())
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> FilterNode {
        guard let token = currentToken else {
            throw errorHere("Expected a filter term")
        }
        if token.token == .lparen {
            advance()
            if current == .rparen { throw errorHere("Empty parentheses") }
            let node = try parseOr()
            guard current == .rparen else {
                throw FilterQueryError(message: "Missing ')'", position: token.position, length: 1)
            }
            advance()
            return node
        }
        return try parseTerm()
    }

    /// Words, quoted text and names after a colon, until an operator, paren, or end of input.
    /// Adjacent `5:30` style tokens are glued back together.
    private mutating func collectWords() -> [(text: String, quoted: Bool)] {
        var words: [(text: String, quoted: Bool)] = []
        while let t = currentToken {
            switch t.token {
            case .word(let w): words.append((w, false)); advance()
            case .quoted(let q): words.append((q, true)); advance()
            case .project(let p): words.append(("#" + p, false)); advance()
            case .label(let l): words.append(("@" + l, false)); advance()
            case .colon:
                // "2:30pm": a colon touching a number on both sides belongs to a time.
                guard let last = words.last, !last.quoted, last.text.last?.isNumber == true,
                      index > 0, tokens[index - 1].end == t.position,
                      index + 1 < tokens.count, tokens[index + 1].position == t.end,
                      case .word(let next) = tokens[index + 1].token, next.first?.isNumber == true
                else { return words }
                words[words.count - 1].text += ":" + next
                index += 2
            default: return words
            }
        }
        return words
    }

    private mutating func expectColon(after keyword: String) throws {
        guard current == .colon else {
            throw FilterQueryError(message: "Expected ':' after '\(keyword)'", position: previousEnd)
        }
        advance()
    }

    private func dateError(_ phrase: String, from first: Int) -> FilterQueryError {
        var message = "Can't understand the date \"\(phrase)\""
        if !phrase.contains(" "), let s = FilterSyntax.closest(to: phrase) { message += ". Did you mean '\(s)'?" }
        return error(message, from: first)
    }

    private mutating func parseTerm() throws -> FilterNode {
        guard let token = currentToken else { throw errorHere("Expected a filter term") }
        switch token.token {
        case .project(let name): advance(); return .project(name)
        case .label(let name): advance(); return .label(name)
        case .quoted(let text): advance(); return .search(text)
        case .section:
            throw error("HITList has no sections; use a label (@name) instead", at: token)
        case .word(let w):
            advance()
            return try parseWordTerm(w, first: index - 1)
        case .op:
            throw error("Unexpected \(Self.describe(token.token)). Comparisons go after 'priority', as in 'priority <= 2'", at: token)
        default:
            throw error("Unexpected \(Self.describe(token.token))", at: token)
        }
    }

    private static let unsupported: [String: String] = [
        "assigned": "HITList is single-user, so there is nothing to assign",
        "shared": "HITList is single-user, so nothing is shared",
        "added": "HITList is single-user, so every task is added by you",
        "workspace": "HITList has no workspaces; use a project instead",
        "subtask": "HITList has no sub-tasks",
        "subtasks": "HITList has no sub-tasks",
        "deadline": "HITList has no deadlines; use 'due before:' instead",
        "uncompletable": "HITList has no uncompletable tasks",
    ]

    private mutating func parseWordTerm(_ w: String, first: Int) throws -> FilterNode {
        switch w {
        case "all": return .all
        case "view":
            guard peekWord() == "all" else { throw error("Unknown keyword 'view'. Did you mean 'view all'?", from: first) }
            advance(); return .all
        case "p1", "p2", "p3", "p4":
            return .priority(.eq, Int(String(w.last!))!)
        case "priority", "pri":
            if current == .colon { advance() }
            var op: ComparisonOp = .eq
            if case .op(let o)? = current { op = o; advance() }
            guard let n = peekWord(), let value = Int(n), (1...4).contains(value) else {
                throw errorHere("Expected a priority 1-4 after 'priority'")
            }
            advance()
            return .priority(op, value)
        case "overdue", "od": return .overdue
        case "over":
            guard peekWord() == "due" else { throw error("Unknown keyword 'over'. Did you mean 'overdue'?", from: first) }
            advance(); return .overdue
        case "completed", "done": return .completed(true)
        case "recurring", "repeating": return .recurring
        case "no": return try parseNo(first: first)
        case "has": return try parseHas(first: first)
        case "due", "date": return try parseDateField(w, created: false, first: first)
        case "created": return try parseDateField(w, created: true, first: first)
        case "search", "q":
            try expectColon(after: w)
            let words = collectWords()
            guard !words.isEmpty else { throw errorHere("Expected text after 'search:'") }
            // Unquoted words must each appear, in any order; quoted text is one exact phrase.
            let parts = words.map { FilterNode.search($0.text) }
            return parts.dropFirst().reduce(parts[0]) { .and($0, $1) }
        default:
            if let reason = Self.unsupported[w] { throw error(reason, from: first) }
            return try parseBareDate(w, first: first)
        }
    }

    private mutating func parseNo(first: Int) throws -> FilterNode {
        let options = ["date", "time", "project", "labels", "priority"]
        guard let n = peekWord() else {
            throw error("Expected date, time, project, labels or priority after 'no'", from: first)
        }
        advance()
        switch n {
        case "date": return .noDate
        case "due":
            if peekWord() == "date" { advance() }
            return .noDate
        case "deadline": return .noDate // accepted since 0.1; HITList has no separate deadlines
        case "time": return .hasTime(false)
        case "project", "projects": return .project(nil)
        case "label", "labels": return .label(nil)
        case "priority": return .priority(.eq, 4)
        case "section", "sections": throw error("HITList has no sections", from: first)
        default:
            var message = "Unknown keyword 'no \(n)'"
            if let s = FilterSyntax.closest(to: n, in: options) { message += ". Did you mean 'no \(s)'?" }
            throw error(message, from: first)
        }
    }

    private mutating func parseHas(first: Int) throws -> FilterNode {
        guard let n = peekWord() else {
            throw error("Expected date, time, project, labels or priority after 'has'", from: first)
        }
        advance()
        switch n {
        case "time": return .hasTime(true)
        case "date", "due": return .not(.noDate)
        case "project": return .not(.project(nil))
        case "label", "labels": return .not(.label(nil))
        case "priority": return .not(.priority(.eq, 4))
        default:
            var message = "Unknown keyword 'has \(n)'"
            if let s = FilterSyntax.closest(to: n, in: ["date", "time", "project", "labels", "priority"]) {
                message += ". Did you mean 'has \(s)'?"
            }
            throw error(message, from: first)
        }
    }

    /// `due: x`, `due before: x`, `date after: x`, `created: x` and friends.
    private mutating func parseDateField(_ keyword: String, created: Bool, first: Int) throws -> FilterNode {
        var kind = "on"
        var label = keyword
        if let n = peekWord() {
            if n == "before" || n == "after" {
                kind = n; label += " " + n; advance()
            } else if current != .colon, let s = FilterSyntax.closest(to: n, in: ["before", "after"]) {
                advance()
                throw error("Unknown keyword '\(n)'. Did you mean '\(keyword) \(s):'?", from: index - 1)
            }
        }
        try expectColon(after: label)
        let phraseStart = index
        let phrase = collectWords().map(\.text).joined(separator: " ")
        guard !phrase.isEmpty else {
            throw FilterQueryError(message: "Expected a date after '\(label):'", position: previousEnd)
        }
        guard let term = Self.dateTerm(phrase, parser: dateParser) else {
            throw dateError(phrase, from: phraseStart)
        }
        switch (kind, created) {
        case ("before", false): return .dueBefore(term)
        case ("after", false): return .dueAfter(term)
        case ("before", true): return .createdBefore(term)
        case ("after", true): return .createdAfter(term)
        case (_, true): return .createdOn(term)
        default: return .dueOn(term)
        }
    }

    /// A count of days, weeks or hours typed into a filter, within `DateExpressionParser.relativeCounts`;
    /// nil for anything else, so "99999999999 days" fails to parse instead of trapping in the date
    /// arithmetic (the same overflow quick add had, beta review).
    static func boundedCount(_ word: String) -> Int? {
        guard let n = Int(word), DateExpressionParser.relativeCounts.contains(n) else { return nil }
        return n
    }

    /// A date used on its own: `today`, `7 days`, `-3 days`, `saturday`, `jan 3`, `today..friday`.
    private mutating func parseBareDate(_ w: String, first: Int) throws -> FilterNode {
        var w = w
        if w == "next", let n = peekWord(), let count = Self.boundedCount(n), count >= 0 {
            w = n; advance() // "next 7 days" is "7 days"
        }
        if let count = Self.boundedCount(w), let unit = peekWord().flatMap({ DateUnit(word: $0) }) {
            advance()
            let days: Int
            switch unit {
            case .day: days = count
            case .week: days = count * 7
            default:
                throw error("'\(w) \(unit.name(count))' needs a field, as in 'due before: +\(abs(count)) \(unit.name(abs(count)))'", from: first)
            }
            return .dueOn(days >= 0 ? .nextDays(days) : .lastDays(-days))
        }

        // The longest run of words that reads as a date: "jan 3", "next mon", "today at 2pm".
        var words = [w]
        while let next = peekWord(words.count - 1) { words.append(next) }
        for k in stride(from: words.count, through: 1, by: -1) {
            guard let term = Self.dateTerm(words[0..<k].joined(separator: " "), parser: dateParser) else { continue }
            index += k - 1
            return .dueOn(term)
        }

        switch w {
        case "next":
            throw error("Expected week, month, weekend, a weekday or a number of days after 'next'", from: first)
        case "this":
            throw error("Expected week, month, weekend or a weekday after 'this'", from: first)
        default:
            var message = "Unknown keyword '\(w)'"
            if let s = FilterSyntax.closest(to: w) { message += ". Did you mean '\(s)'?" }
            throw error(message, from: first)
        }
    }

    /// Parses a date phrase used by `due:`, `created:` and bare date terms. Words must be lowercased.
    static func dateTerm(_ raw: String, parser: DateExpressionParser) -> DateTerm? {
        let words = raw.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return nil }
        let phrase = words.joined(separator: " ")

        if let r = phrase.range(of: "..") {
            let a = String(phrase[..<r.lowerBound]), b = String(phrase[r.upperBound...])
            guard !b.contains(".."), let ta = dateTerm(a, parser: parser), let tb = dateTerm(b, parser: parser) else { return nil }
            return .range(ta, tb)
        }

        switch phrase {
        case "today", "tod": return .today
        case "tomorrow", "tom", "tmr", "tmrw": return .tomorrow
        case "yesterday": return .yesterday
        case "this week": return .thisWeek
        case "next week": return .nextWeek
        case "this month": return .thisMonth
        case "next month": return .nextMonth
        case "weekend", "this weekend": return .weekend
        case "next weekend": return .nextWeekend
        case "first day": return .firstDayOfNextMonth
        default: break
        }

        // "+4 hours", "-365 days", "3 days"
        if words.count == 2, let n = Self.boundedCount(words[0]), let unit = DateUnit(word: words[1]) {
            return .relative(n, unit)
        }
        // "1 week after next week", "8 days before sunday"
        if words.count >= 4, let n = Self.boundedCount(words[0]), n >= 0, let unit = DateUnit(word: words[1]),
           words[2] == "after" || words[2] == "before",
           let base = dateTerm(words[3...].joined(separator: " "), parser: parser) {
            return .shifted(words[2] == "after" ? n : -n, unit, base)
        }
        if words.count == 1, let month = DateExpressionParser.monthNames[words[0]] {
            return .month(month)
        }
        if parser.parse(phrase) != nil { return .expression(phrase) }
        return nil
    }
}

// MARK: - Evaluation

/// A parsed, reusable filter. Parse once (validating syntax), evaluate against tasks whenever.
public struct FilterQuery: Sendable, Equatable {
    public let source: String
    public let root: FilterNode

    /// Parses `source`. Throws `FilterQueryError` with a message and character range on failure.
    public init(_ source: String, calendar: Calendar = .current, now: Date = Date()) throws {
        self.source = source
        self.root = try FilterParser.parse(source, dateParser: DateExpressionParser(calendar: calendar, now: now))
    }

    /// Validates a query string without keeping the result.
    public static func validate(_ source: String) -> FilterQueryError? {
        do { _ = try FilterQuery(source); return nil } catch let e as FilterQueryError { return e } catch { return nil }
    }

    /// Whether the query explicitly refers to completion state. Views hide completed tasks unless it does.
    public var mentionsCompleted: Bool { Self.mentionsCompleted(root) }

    private static func mentionsCompleted(_ node: FilterNode) -> Bool {
        switch node {
        case .completed: return true
        case .and(let a, let b), .or(let a, let b): return mentionsCompleted(a) || mentionsCompleted(b)
        case .not(let a): return mentionsCompleted(a)
        default: return false
        }
    }

    /// Whether the query names the `flipboard` label (`@flipboard`, `!@flipboard`, `@flip*`). Such a query
    /// opts out of the Flipboard's listing rule and sees switches as the tasks they are (brief 59).
    public var namesFlipboard: Bool { Self.namesFlipboard(root) }

    private static func namesFlipboard(_ node: FilterNode) -> Bool {
        switch node {
        case .label(let name?): return Glob.matches(name, FlipboardSwitch.labelName)
        case .and(let a, let b), .or(let a, let b): return namesFlipboard(a) || namesFlipboard(b)
        case .not(let a): return namesFlipboard(a)
        default: return false
        }
    }

    /// Whether `task` matches. Unless the query names `@flipboard`, a green switch never does and a red one
    /// is judged as due today (`FlipboardSwitch.listing`); `flipboardRule: false` judges every task as it is.
    public func matches(_ task: FilterableTask, now: Date = Date(), calendar: Calendar = .current,
                        flipboardRule: Bool = true) -> Bool {
        let ctx = EvalContext(parser: DateExpressionParser(calendar: calendar, now: now))
        return Self.evalListed(root, task, ctx, flipboardRule: flipboardRule && !namesFlipboard)
    }

    /// Filters and sorts `tasks`. Completed tasks are excluded unless the query mentions completion;
    /// subtasks always are (they live inside their parent, `TaskOrdering.topLevel`). The Flipboard's
    /// listing rule applies as in `matches`; Claude's `list_tasks` passes `flipboardRule: false`.
    public func apply<T: FilterableTask>(to tasks: [T], now: Date = Date(), calendar: Calendar = .current,
                                         flipboardRule: Bool = true) -> [T] {
        let ctx = EvalContext(parser: DateExpressionParser(calendar: calendar, now: now))
        let hideCompleted = !mentionsCompleted
        let rule = flipboardRule && !namesFlipboard
        let matched = tasks.filter { task in
            if task.filterIsSubtask { return false }
            if hideCompleted && task.filterIsCompleted { return false }
            return Self.evalListed(root, task, ctx, flipboardRule: rule)
        }
        return Self.defaultSort(matched, now: now, calendar: calendar, flipboardRule: rule)
    }

    /// `eval` with the Flipboard's listing rule: green switches are left out, red ones are due today.
    private static func evalListed(_ node: FilterNode, _ task: FilterableTask, _ ctx: EvalContext, flipboardRule: Bool) -> Bool {
        guard flipboardRule else { return eval(node, task, ctx) }
        func listed<T: FilterableTask>(_ task: T) -> Bool {
            switch FlipboardSwitch.listing(for: task, now: ctx.parser.now, calendar: ctx.parser.calendar) {
            case .hidden: return false
            case .today: return eval(node, FlipboardSwitch.listed(task, now: ctx.parser.now, calendar: ctx.parser.calendar), ctx)
            case .unchanged: return eval(node, task, ctx)
            }
        }
        return listed(task)
    }

    /// Due date ascending (undated last), then priority, then creation order (`TaskOrdering.createdThenTitle`),
    /// each task by the date it is listed under (a red switch: today) unless `flipboardRule` is false.
    public static func defaultSort<T: FilterableTask>(_ tasks: [T], now: Date = Date(), calendar: Calendar = .current,
                                                      flipboardRule: Bool = true) -> [T] {
        guard flipboardRule else { return dueThenPriority(tasks) }
        return dueThenPriority(tasks.map { FlipboardSwitch.listed($0, now: now, calendar: calendar) }).map(\.base)
    }

    private static func dueThenPriority<T: FilterableTask>(_ tasks: [T]) -> [T] {
        tasks.sorted { a, b in
            switch (a.filterDueDate, b.filterDueDate) {
            case let (da?, db?) where da != db: return da < db
            case (nil, .some): return false
            case (.some, nil): return true
            default: break
            }
            if a.filterPriority != b.filterPriority { return a.filterPriority < b.filterPriority }
            return TaskOrdering.createdThenTitle(a, b)
        }
    }

    final class EvalContext {
        let parser: DateExpressionParser
        var cache: [DateTerm: DateSpan?] = [:]
        init(parser: DateExpressionParser) { self.parser = parser }

        /// The span a term covers. Instants (`+4 hours`, `today at 2pm`) are the minute they fall in.
        func span(for term: DateTerm) -> DateSpan? {
            if let cached = cache[term] { return cached }
            let s = resolve(term)
            cache[term] = s
            return s
        }

        private func instant(_ date: Date) -> DateSpan { DateSpan(start: date, end: date.addingTimeInterval(60)) }

        private func offset(_ n: Int, _ unit: DateUnit, from base: Date) -> DateSpan? {
            guard let date = parser.calendar.date(byAdding: unit.component, value: n, to: base) else { return nil }
            return unit.isTimeOfDay ? instant(date) : parser.span(forDay: date)
        }

        private func resolve(_ term: DateTerm) -> DateSpan? {
            let p = parser
            switch term {
            case .today: return p.span(forDay: p.today)
            case .tomorrow: return p.span(forDay: p.day(1))
            case .yesterday: return p.span(forDay: p.day(-1))
            case .nextDays(let n): return p.spanNextDays(n)
            case .lastDays(let n): return p.spanLastDays(n)
            case .thisWeek: return p.spanThisWeek()
            case .nextWeek: return p.spanNextWeek()
            case .thisMonth: return p.spanThisMonth()
            case .nextMonth: return p.spanNextMonth()
            case .weekend: return p.spanWeekend()
            case .nextWeekend: return p.spanNextWeekend()
            case .month(let m): return p.spanMonth(m)
            case .firstDayOfNextMonth: return p.span(forDay: p.firstDayOfNextMonth(after: p.today))
            case .relative(let n, let unit): return offset(n, unit, from: unit.isTimeOfDay ? p.now : p.today)
            case .shifted(let n, let unit, let base):
                guard let b = span(for: base) else { return nil }
                return offset(n, unit, from: b.start)
            case .range(let a, let b):
                guard let sa = span(for: a), let sb = span(for: b), sa.start < sb.end else { return nil }
                return DateSpan(start: sa.start, end: sb.end)
            case .expression(let s):
                guard let pd = p.parse(s) else { return nil }
                return pd.hasTime ? instant(pd.date) : p.span(forDay: pd.date)
            }
        }
    }

    private enum DateComparison { case on, before, after }

    private static func compare(_ date: Date?, _ term: DateTerm, _ how: DateComparison, _ ctx: EvalContext) -> Bool {
        guard let date, let span = ctx.span(for: term) else { return false }
        switch how {
        case .on: return span.contains(date)
        case .before: return date < span.start
        case .after: return date >= span.end
        }
    }

    static func eval(_ node: FilterNode, _ t: FilterableTask, _ ctx: EvalContext) -> Bool {
        switch node {
        case .all: return true
        case .and(let a, let b): return eval(a, t, ctx) && eval(b, t, ctx)
        case .or(let a, let b): return eval(a, t, ctx) || eval(b, t, ctx)
        case .not(let a): return !eval(a, t, ctx)
        case .priority(let op, let v): return op.test(t.filterPriority, v)
        case .dueOn(let term): return compare(t.filterDueDate, term, .on, ctx)
        case .dueBefore(let term): return compare(t.filterDueDate, term, .before, ctx)
        case .dueAfter(let term): return compare(t.filterDueDate, term, .after, ctx)
        case .createdOn(let term): return compare(t.filterCreatedDate, term, .on, ctx)
        case .createdBefore(let term): return compare(t.filterCreatedDate, term, .before, ctx)
        case .createdAfter(let term): return compare(t.filterCreatedDate, term, .after, ctx)
        case .overdue:
            guard let due = t.filterDueDate, !t.filterIsCompleted else { return false }
            return t.filterHasDueTime ? due < ctx.parser.now : due < ctx.parser.today
        case .noDate: return t.filterDueDate == nil
        case .hasTime(let wanted): return t.filterDueDate != nil && t.filterHasDueTime == wanted
        case .project(let name):
            guard let name else { return t.filterProjectName == nil }
            guard let project = t.filterProjectName else { return name.caseInsensitiveCompare("inbox") == .orderedSame }
            return Glob.matches(name, project)
        case .label(let name):
            guard let name else { return t.filterLabelNames.isEmpty }
            return t.filterLabelNames.contains { Glob.matches(name, $0) }
        case .search(let text):
            return Glob.contains(text, in: t.filterTitle) || Glob.contains(text, in: t.filterNotes)
        case .completed(let wanted): return t.filterIsCompleted == wanted
        case .recurring: return t.filterIsRecurring
        }
    }
}

// MARK: - English description

extension FilterQuery {
    /// The query as readable English, e.g. "Priority 1 or 2, due today or overdue".
    public static func describe(_ query: FilterQuery) -> String { describe(query.root) }

    public static func describe(_ node: FilterNode) -> String {
        var text = FilterDescriber.render(node, .top)
        if let i = text.firstIndex(where: \.isLetter) {
            text.replaceSubrange(i...i, with: text[i...i].uppercased())
        }
        return text
    }

    /// `describe(self)`.
    public var summary: String { Self.describe(self) }
}

enum FilterDescriber {
    enum Context { case top, inAnd, inOr, inNot }

    static func render(_ node: FilterNode, _ ctx: Context) -> String {
        switch node {
        case .and:
            if let levels = prioritySet(node) { return priorityText(levels) }
            var parts: [String] = []
            var previousWasSearch = false
            for kid in flattenAnd(node) {
                // "search: send email" reads as one phrase: containing “send” and “email”.
                if case .search(let s) = kid, previousWasSearch {
                    parts[parts.count - 1] += " and “\(s)”"
                    continue
                }
                if case .search = kid { previousWasSearch = true } else { previousWasSearch = false }
                parts.append(render(kid, .inAnd))
            }
            if ctx == .top { return parts.joined(separator: ", ") }
            return "(" + parts.joined(separator: " and ") + ")"
        case .or:
            let kids = flattenOr(node)
            if let levels = prioritySet(node) { return priorityText(levels) }
            var parts: [String] = []
            for kid in kids {
                var text = render(kid, .inOr)
                if let previous = parts.last {
                    for prefix in ["due ", "created "] where previous.hasPrefix(prefix) && text.hasPrefix(prefix) {
                        text = String(text.dropFirst(prefix.count))
                    }
                }
                parts.append(text)
            }
            let joined = parts.joined(separator: " or ")
            return ctx == .inNot ? "(" + joined + ")" : joined
        case .not(let inner):
            return negated(inner)
        default:
            return atom(node)
        }
    }

    static func flattenAnd(_ node: FilterNode) -> [FilterNode] {
        if case .and(let a, let b) = node { return flattenAnd(a) + flattenAnd(b) }
        return [node]
    }

    static func flattenOr(_ node: FilterNode) -> [FilterNode] {
        if case .or(let a, let b) = node { return flattenOr(a) + flattenOr(b) }
        return [node]
    }

    /// The priority levels a node allows, when it is made only of priority terms.
    static func prioritySet(_ node: FilterNode) -> Set<Int>? {
        switch node {
        case .priority(let op, let v): return Set((1...4).filter { op.test($0, v) })
        case .or(let a, let b):
            guard let x = prioritySet(a), let y = prioritySet(b) else { return nil }
            return x.union(y)
        case .and(let a, let b):
            guard let x = prioritySet(a), let y = prioritySet(b) else { return nil }
            return x.intersection(y)
        case .not(let a):
            guard let x = prioritySet(a) else { return nil }
            return Set(1...4).subtracting(x)
        default: return nil
        }
    }

    static func priorityText(_ levels: Set<Int>) -> String {
        switch levels.sorted() {
        case []: return "no possible priority"
        case [4]: return "no priority"
        case [1, 2, 3, 4]: return "any priority"
        case let sorted: return "priority " + list(sorted.map(String.init), "or")
        }
    }

    static func list(_ items: [String], _ conjunction: String) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " \(conjunction) " + items.last!
    }

    static func atom(_ node: FilterNode) -> String {
        switch node {
        case .all: return "all tasks"
        case .priority: return priorityText(prioritySet(node) ?? [])
        case .dueOn(let t): return "due " + onPhrase(t)
        case .dueBefore(let t): return "due before " + name(t)
        case .dueAfter(let t): return "due after " + name(t)
        case .createdOn(let t): return "created " + onPhrase(t)
        case .createdBefore(let t): return "created before " + name(t)
        case .createdAfter(let t): return "created after " + name(t)
        case .overdue: return "overdue"
        case .noDate: return "no due date"
        case .hasTime(true): return "with a due time"
        case .hasTime(false): return "with a date but no time"
        case .project(nil): return "no project"
        case .project(let p?):
            if p.caseInsensitiveCompare("inbox") == .orderedSame { return "in the Inbox" }
            return p.contains("*") ? "in a project matching \(p)" : "in #\(p)"
        case .label(nil): return "no labels"
        case .label(let l?): return l.contains("*") ? "with a label matching @\(l)" : "labelled @\(l)"
        case .search(let s): return "containing “\(s)”"
        case .completed(true): return "completed"
        case .completed(false): return "not completed"
        case .recurring: return "recurring"
        case .and, .or, .not: return render(node, .inAnd)
        }
    }

    static func negated(_ inner: FilterNode) -> String {
        switch inner {
        case .noDate: return "with a due date"
        case .project(nil): return "in a project"
        case .label(nil): return "with labels"
        case .project(let p?):
            if p.caseInsensitiveCompare("inbox") == .orderedSame { return "not in the Inbox" }
            return p.contains("*") ? "not in a project matching \(p)" : "not in #\(p)"
        case .label(let l?): return "without @\(l)"
        case .search(let s): return "not containing “\(s)”"
        case .completed(let c): return c ? "not completed" : "completed"
        case .hasTime(true): return "without a due time"
        case .hasTime(false): return "with a due time or no due date"
        case .all: return "nothing"
        case .not(let x): return render(x, .inAnd)
        case .priority, .or, .and:
            if let levels = prioritySet(.not(inner)) { return priorityText(levels) }
            return "not " + render(inner, .inNot)
        default: return "not " + atom(inner)
        }
    }

    /// What follows "due " for an `on` comparison.
    static func onPhrase(_ term: DateTerm) -> String {
        switch term {
        case .today, .tomorrow, .yesterday, .thisWeek, .nextWeek, .thisMonth, .nextMonth, .weekend, .nextWeekend:
            return name(term)
        case .nextDays(let n): return "today or in the next \(n) \(n == 1 ? "day" : "days")"
        case .lastDays(let n): return "today or in the past \(n) \(n == 1 ? "day" : "days")"
        case .month(let m): return "in " + monthName(m)
        case .range(let a, let b): return "from \(name(a)) through \(name(b))"
        default: return "on " + name(term)
        }
    }

    static func name(_ term: DateTerm) -> String {
        switch term {
        case .today: return "today"
        case .tomorrow: return "tomorrow"
        case .yesterday: return "yesterday"
        case .nextDays(let n): return "the next \(n) days"
        case .lastDays(let n): return "the past \(n) days"
        case .thisWeek: return "this week"
        case .nextWeek: return "next week"
        case .thisMonth: return "this month"
        case .nextMonth: return "next month"
        case .weekend: return "this weekend"
        case .nextWeekend: return "next weekend"
        case .month(let m): return monthName(m)
        case .firstDayOfNextMonth: return "the 1st of next month"
        case .relative(let n, let unit):
            if n == 0 { return unit.isTimeOfDay ? "now" : "today" }
            return n > 0 ? "\(n) \(unit.name(n)) from now" : "\(-n) \(unit.name(-n)) ago"
        case .shifted(let n, let unit, let base):
            return "\(abs(n)) \(unit.name(abs(n))) \(n >= 0 ? "after" : "before") \(name(base))"
        case .range(let a, let b): return "\(name(a)) through \(name(b))"
        case .expression(let s): return s
        }
    }

    static func monthName(_ m: Int) -> String {
        ["January", "February", "March", "April", "May", "June", "July", "August", "September",
         "October", "November", "December"][max(0, min(11, m - 1))]
    }
}
