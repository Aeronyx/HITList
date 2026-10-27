import Foundation

// MARK: - Errors

public struct FilterQueryError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    /// Character offset into the source where the problem was detected.
    public let position: Int
    public init(message: String, position: Int) {
        self.message = message
        self.position = position
    }
    public var errorDescription: String? { message }
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

/// A date reference that is resolved at evaluation time so saved filters stay correct across days.
public enum DateTerm: Sendable, Equatable {
    case today, tomorrow, yesterday
    case nextDays(Int)
    case thisWeek, nextWeek, thisMonth, nextMonth, weekend
    /// Free-form phrase understood by `DateExpressionParser`, e.g. "next mon", "jan 5".
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
    /// `nil` means "no project".
    case project(String?)
    /// `nil` means "no labels".
    case label(String?)
    case search(String)
    case completed(Bool)
    case recurring
}

// MARK: - Tokenizer

enum FilterToken: Equatable {
    case lparen, rparen, and, or, not, colon
    case op(ComparisonOp)
    case project(String)
    case label(String)
    case quoted(String)
    case word(String)
}

struct PositionedToken {
    let token: FilterToken
    let position: Int
}

struct FilterTokenizer {
    static func tokenize(_ source: String) throws -> [PositionedToken] {
        var tokens: [PositionedToken] = []
        let chars = Array(source)
        var i = 0

        func isWordChar(_ c: Character) -> Bool {
            !(c.isWhitespace || "()&|,!:<>=\"".contains(c))
        }

        func readQuoted(from start: Int) throws -> (String, Int) {
            var j = start + 1
            var s = ""
            while j < chars.count, chars[j] != "\"" { s.append(chars[j]); j += 1 }
            guard j < chars.count else {
                throw FilterQueryError(message: "Missing closing quote", position: start)
            }
            return (s, j + 1)
        }

        func readWord(from start: Int) -> (String, Int) {
            var j = start
            var s = ""
            while j < chars.count, isWordChar(chars[j]) { s.append(chars[j]); j += 1 }
            return (s, j)
        }

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            switch c {
            case "(": tokens.append(.init(token: .lparen, position: i)); i += 1
            case ")": tokens.append(.init(token: .rparen, position: i)); i += 1
            case "&", ",": tokens.append(.init(token: .and, position: i)); i += 1
            case "|": tokens.append(.init(token: .or, position: i)); i += 1
            case ":": tokens.append(.init(token: .colon, position: i)); i += 1
            case "!":
                if i + 1 < chars.count, chars[i + 1] == "=" {
                    tokens.append(.init(token: .op(.ne), position: i)); i += 2
                } else {
                    tokens.append(.init(token: .not, position: i)); i += 1
                }
            case "<", ">", "=":
                if i + 1 < chars.count, chars[i + 1] == "=" {
                    let op: ComparisonOp = c == "<" ? .le : (c == ">" ? .ge : .eq)
                    tokens.append(.init(token: .op(op), position: i)); i += 2
                } else {
                    let op: ComparisonOp = c == "<" ? .lt : (c == ">" ? .gt : .eq)
                    tokens.append(.init(token: .op(op), position: i)); i += 1
                }
            case "\"":
                let (s, j) = try readQuoted(from: i)
                tokens.append(.init(token: .quoted(s), position: i)); i = j
            case "#", "@":
                let start = i
                var name: String
                var j: Int
                if i + 1 < chars.count, chars[i + 1] == "\"" {
                    (name, j) = try readQuoted(from: i + 1)
                } else {
                    (name, j) = readWord(from: i + 1)
                }
                guard !name.isEmpty else {
                    throw FilterQueryError(message: "Expected a name after '\(c)'", position: start)
                }
                tokens.append(.init(token: c == "#" ? .project(name) : .label(name), position: start))
                i = j
            default:
                let (w, j) = readWord(from: i)
                tokens.append(.init(token: .word(w.lowercased()), position: i))
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
            throw FilterQueryError(message: "Unexpected \(parser.describe(tokens[parser.index].token))", position: tokens[parser.index].position)
        }
        return node
    }

    private var current: FilterToken? { index < tokens.count ? tokens[index].token : nil }
    private var position: Int { index < tokens.count ? tokens[index].position : (tokens.last?.position ?? 0) }

    private func peekWord(_ offset: Int = 0) -> String? {
        guard index + offset < tokens.count, case .word(let w) = tokens[index + offset].token else { return nil }
        return w
    }

    private mutating func advance() { index += 1 }

    private func describe(_ token: FilterToken) -> String {
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
        case .quoted(let q): return "\"\(q)\""
        case .word(let w): return "'\(w)'"
        }
    }

    private mutating func parseOr() throws -> FilterNode {
        var lhs = try parseAnd()
        while current == .or {
            advance()
            let rhs = try parseAnd()
            lhs = .or(lhs, rhs)
        }
        return lhs
    }

    private mutating func parseAnd() throws -> FilterNode {
        var lhs = try parseNot()
        while current == .and {
            advance()
            let rhs = try parseNot()
            lhs = .and(lhs, rhs)
        }
        return lhs
    }

    private mutating func parseNot() throws -> FilterNode {
        if current == .not {
            advance()
            return .not(try parseNot())
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> FilterNode {
        guard let token = current else {
            throw FilterQueryError(message: "Expected a filter term", position: position)
        }
        if token == .lparen {
            let start = position
            advance()
            let node = try parseOr()
            guard current == .rparen else {
                throw FilterQueryError(message: "Missing ')'", position: start)
            }
            advance()
            return node
        }
        return try parseTerm()
    }

    /// Collects words after a colon until an operator, paren, or end of input.
    private mutating func collectPhrase() -> String {
        var words: [String] = []
        while let token = current {
            switch token {
            case .word(let w): words.append(w); advance()
            case .quoted(let q): words.append(q); advance()
            case .project(let p): words.append("#" + p); advance()
            case .label(let l): words.append("@" + l); advance()
            default: return words.joined(separator: " ")
            }
        }
        return words.joined(separator: " ")
    }

    private mutating func expectColon() throws {
        guard current == .colon else {
            throw FilterQueryError(message: "Expected ':'", position: position)
        }
        advance()
    }

    private mutating func parseDateTerm(start: Int) throws -> DateTerm {
        let phrase = collectPhrase()
        guard !phrase.isEmpty else {
            throw FilterQueryError(message: "Expected a date after ':'", position: start)
        }
        switch phrase {
        case "today": return .today
        case "tomorrow", "tom": return .tomorrow
        case "yesterday": return .yesterday
        case "next week": return .nextWeek
        case "this week": return .thisWeek
        case "next month": return .nextMonth
        case "this month": return .thisMonth
        default: break
        }
        guard dateParser.parse(phrase) != nil else {
            throw FilterQueryError(message: "Can't understand the date \"\(phrase)\"", position: start)
        }
        return .expression(phrase)
    }

    private mutating func parseTerm() throws -> FilterNode {
        let start = position
        guard let token = current else {
            throw FilterQueryError(message: "Expected a filter term", position: start)
        }
        switch token {
        case .project(let name): advance(); return .project(name)
        case .label(let name): advance(); return .label(name)
        case .quoted(let text): advance(); return .search(text)
        case .word(let w):
            advance()
            return try parseWordTerm(w, start: start)
        default:
            throw FilterQueryError(message: "Unexpected \(describe(token))", position: start)
        }
    }

    private mutating func parseWordTerm(_ w: String, start: Int) throws -> FilterNode {
        switch w {
        case "all": return .all
        case "p1", "p2", "p3", "p4":
            return .priority(.eq, Int(String(w.last!))!)
        case "priority", "pri":
            var op: ComparisonOp = .eq
            if case .op(let o)? = current { op = o; advance() }
            guard let n = peekWord(), let value = Int(n), (1...4).contains(value) else {
                throw FilterQueryError(message: "Expected a priority 1-4 after 'priority'", position: position)
            }
            advance()
            return .priority(op, value)
        case "today", "tod": return .dueOn(.today)
        case "tomorrow", "tom": return .dueOn(.tomorrow)
        case "yesterday": return .dueOn(.yesterday)
        case "overdue", "od": return .overdue
        case "completed", "done": return .completed(true)
        case "recurring", "repeating": return .recurring
        case "weekend": return .dueOn(.weekend)
        case "no":
            guard let n = peekWord() else {
                throw FilterQueryError(message: "Expected 'date', 'time', 'project', 'labels' or 'priority' after 'no'", position: position)
            }
            advance()
            switch n {
            case "date": return .noDate
            case "due":
                if peekWord() == "date" { advance() }
                return .noDate
            case "deadline": return .noDate
            case "time": return .hasTime(false)
            case "project": return .project(nil)
            case "label", "labels": return .label(nil)
            case "priority": return .priority(.eq, 4)
            default:
                throw FilterQueryError(message: "Unknown term 'no \(n)'", position: start)
            }
        case "has":
            guard let n = peekWord() else {
                throw FilterQueryError(message: "Expected 'date', 'time', 'project' or 'labels' after 'has'", position: position)
            }
            advance()
            switch n {
            case "time": return .hasTime(true)
            case "date", "due": return .not(.noDate)
            case "project": return .not(.project(nil))
            case "label", "labels": return .not(.label(nil))
            default:
                throw FilterQueryError(message: "Unknown term 'has \(n)'", position: start)
            }
        case "next":
            guard let n = peekWord() else {
                throw FilterQueryError(message: "Expected 'week', 'month' or a number of days after 'next'", position: position)
            }
            advance()
            if n == "week" { return .dueOn(.nextWeek) }
            if n == "month" { return .dueOn(.nextMonth) }
            if let count = Int(n), let unit = peekWord() {
                advance()
                switch unit {
                case "day", "days": return .dueOn(.nextDays(count))
                case "week", "weeks": return .dueOn(.nextDays(count * 7))
                default:
                    throw FilterQueryError(message: "Expected 'days' or 'weeks' after 'next \(n)'", position: position)
                }
            }
            throw FilterQueryError(message: "Unknown term 'next \(n)'", position: start)
        case "this":
            guard let n = peekWord() else {
                throw FilterQueryError(message: "Expected 'week' or 'month' after 'this'", position: position)
            }
            advance()
            if n == "week" { return .dueOn(.thisWeek) }
            if n == "month" { return .dueOn(.thisMonth) }
            throw FilterQueryError(message: "Unknown term 'this \(n)'", position: start)
        case "due":
            var kind = "on"
            if let n = peekWord(), n == "before" || n == "after" { kind = n; advance() }
            try expectColon()
            let term = try parseDateTerm(start: start)
            switch kind {
            case "before": return .dueBefore(term)
            case "after": return .dueAfter(term)
            default: return .dueOn(term)
            }
        case "search", "q":
            try expectColon()
            let phrase = collectPhrase()
            guard !phrase.isEmpty else {
                throw FilterQueryError(message: "Expected text after 'search:'", position: position)
            }
            return .search(phrase)
        default:
            if let count = Int(w), let unit = peekWord() {
                if unit == "day" || unit == "days" { advance(); return .dueOn(.nextDays(count)) }
                if unit == "week" || unit == "weeks" { advance(); return .dueOn(.nextDays(count * 7)) }
            }
            throw FilterQueryError(message: "Unknown term '\(w)'", position: start)
        }
    }
}

// MARK: - Evaluation

/// A parsed, reusable filter. Parse once (validating syntax), evaluate against tasks whenever.
public struct FilterQuery: Sendable, Equatable {
    public let source: String
    public let root: FilterNode

    /// Parses `source`. Throws `FilterQueryError` with a message and character position on failure.
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

    public func matches(_ task: FilterableTask, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let ctx = EvalContext(parser: DateExpressionParser(calendar: calendar, now: now))
        return Self.eval(root, task, ctx)
    }

    /// Filters and sorts `tasks`. Completed tasks are excluded unless the query mentions completion.
    public func apply<T: FilterableTask>(to tasks: [T], now: Date = Date(), calendar: Calendar = .current) -> [T] {
        let ctx = EvalContext(parser: DateExpressionParser(calendar: calendar, now: now))
        let hideCompleted = !mentionsCompleted
        let matched = tasks.filter { task in
            if hideCompleted && task.filterIsCompleted { return false }
            return Self.eval(root, task, ctx)
        }
        return Self.defaultSort(matched)
    }

    /// Due date ascending (undated last), then priority, then title.
    public static func defaultSort<T: FilterableTask>(_ tasks: [T]) -> [T] {
        tasks.sorted { a, b in
            switch (a.filterDueDate, b.filterDueDate) {
            case let (da?, db?) where da != db: return da < db
            case (nil, .some): return false
            case (.some, nil): return true
            default: break
            }
            if a.filterPriority != b.filterPriority { return a.filterPriority < b.filterPriority }
            return a.filterTitle.localizedCaseInsensitiveCompare(b.filterTitle) == .orderedAscending
        }
    }

    final class EvalContext {
        let parser: DateExpressionParser
        var cache: [String: ParsedDate?] = [:]
        init(parser: DateExpressionParser) { self.parser = parser }

        func expression(_ phrase: String) -> ParsedDate? {
            if let cached = cache[phrase] { return cached }
            let parsed = parser.parse(phrase)
            cache[phrase] = parsed
            return parsed
        }

        func span(for term: DateTerm) -> DateSpan? {
            let p = parser
            switch term {
            case .today: return p.span(forDay: p.today)
            case .tomorrow: return p.span(forDay: p.day(1))
            case .yesterday: return p.span(forDay: p.day(-1))
            case .nextDays(let n): return p.spanNextDays(n)
            case .thisWeek: return p.spanThisWeek()
            case .nextWeek: return p.spanNextWeek()
            case .thisMonth: return p.spanThisMonth()
            case .nextMonth: return p.spanNextMonth()
            case .weekend: return p.spanWeekend()
            case .expression(let s):
                guard let pd = expression(s) else { return nil }
                return p.span(forDay: pd.date)
            }
        }
    }

    static func eval(_ node: FilterNode, _ t: FilterableTask, _ ctx: EvalContext) -> Bool {
        switch node {
        case .all: return true
        case .and(let a, let b): return eval(a, t, ctx) && eval(b, t, ctx)
        case .or(let a, let b): return eval(a, t, ctx) || eval(b, t, ctx)
        case .not(let a): return !eval(a, t, ctx)
        case .priority(let op, let v): return op.test(t.filterPriority, v)
        case .dueOn(let term):
            guard let due = t.filterDueDate, let span = ctx.span(for: term) else { return false }
            return span.contains(due)
        case .dueBefore(let term):
            guard let due = t.filterDueDate, let span = ctx.span(for: term) else { return false }
            return due < span.start
        case .dueAfter(let term):
            guard let due = t.filterDueDate, let span = ctx.span(for: term) else { return false }
            return due >= span.end
        case .overdue:
            guard let due = t.filterDueDate, !t.filterIsCompleted else { return false }
            return t.filterHasDueTime ? due < ctx.parser.now : due < ctx.parser.today
        case .noDate: return t.filterDueDate == nil
        case .hasTime(let wanted): return t.filterDueDate != nil && t.filterHasDueTime == wanted
        case .project(let name):
            guard let name else { return t.filterProjectName == nil }
            return t.filterProjectName?.caseInsensitiveCompare(name) == .orderedSame
        case .label(let name):
            guard let name else { return t.filterLabelNames.isEmpty }
            return t.filterLabelNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        case .search(let text):
            return t.filterTitle.localizedCaseInsensitiveContains(text) || t.filterNotes.localizedCaseInsensitiveContains(text)
        case .completed(let wanted): return t.filterIsCompleted == wanted
        case .recurring: return t.filterIsRecurring
        }
    }
}
