import Foundation

/// One recognized span inside the quick-add text, so the UI can highlight it.
public struct QuickAddToken: Equatable, Sendable {
    public enum Kind: String, Sendable { case priority, project, label, date, time, recurrence, reminder }
    public var kind: Kind
    public var range: Range<String.Index>
    public var text: String
}

public struct QuickAddResult: Equatable, Sendable {
    public var title: String
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var priority: Priority
    public var projectName: String?
    public var labelNames: [String]
    public var recurrence: RecurrenceRule?
    /// Minutes before the due time to remind (`!15mb`); 0 for `!0` / `!at`; nil when nothing was typed.
    public var reminderOffsetMinutes: Int?
    /// A deadline picked from the card's "+" menu. It has no text token, so the parser never sets it.
    public var deadline: Date?
    /// A location typed from the card's "+" menu. It has no text token, so the parser never sets it.
    public var locationName: String?
    public var tokens: [QuickAddToken]

    public init(title: String = "", dueDate: Date? = nil, hasDueTime: Bool = false, priority: Priority = .p4,
                projectName: String? = nil, labelNames: [String] = [], recurrence: RecurrenceRule? = nil,
                reminderOffsetMinutes: Int? = nil, deadline: Date? = nil, locationName: String? = nil,
                tokens: [QuickAddToken] = []) {
        self.title = title
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.priority = priority
        self.projectName = projectName
        self.labelNames = labelNames
        self.recurrence = recurrence
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.deadline = deadline
        self.locationName = locationName
        self.tokens = tokens
    }
}

/// Turns "Pay rent tomorrow 5pm p1 #Finance @bills every month !1hb" into structured fields.
public struct QuickAddParser: Sendable {
    public var dateParser: DateExpressionParser
    public var knownProjects: [String]
    public var knownLabels: [String]

    public init(now: Date = Date(), calendar: Calendar = .current, knownProjects: [String] = [], knownLabels: [String] = [],
                weekStart: Int = 2) {
        self.dateParser = DateExpressionParser(calendar: calendar, now: now, weekStart: weekStart)
        self.knownProjects = knownProjects
        self.knownLabels = knownLabels
    }

    struct Word {
        let text: String
        let lower: String
        let range: Range<String.Index>
    }

    /// Splits on whitespace but keeps `#"Two Words"` and `"quoted text"` together.
    static func words(in input: String) -> [Word] {
        var result: [Word] = []
        var i = input.startIndex
        while i < input.endIndex {
            while i < input.endIndex, input[i].isWhitespace { i = input.index(after: i) }
            guard i < input.endIndex else { break }
            let start = i
            var inQuotes = false
            while i < input.endIndex {
                let c = input[i]
                if c == "\"" { inQuotes.toggle() }
                else if c.isWhitespace && !inQuotes { break }
                i = input.index(after: i)
            }
            let text = String(input[start..<i])
            result.append(Word(text: text, lower: text.lowercased(), range: start..<i))
        }
        return result
    }

    public func parse(_ input: String) -> QuickAddResult {
        let words = Self.words(in: input)
        let lowers = words.map(\.lower)
        var consumed = [Bool](repeating: false, count: words.count)
        var result = QuickAddResult()
        var time: (Int, Int)? = nil
        var date: Date? = nil

        func mark(_ i: Int, _ n: Int, _ kind: QuickAddToken.Kind) {
            guard n > 0 else { return }
            let range = words[i].range.lowerBound..<words[i + n - 1].range.upperBound
            for k in i..<(i + n) { consumed[k] = true }
            result.tokens.append(QuickAddToken(kind: kind, range: range, text: String(input[range])))
        }

        var i = 0
        while i < words.count {
            if consumed[i] { i += 1; continue }
            let w = lowers[i]

            // Priority: p1..p4, !!1..!!4
            if result.priority == .p4, let p = Self.priority(from: w) {
                result.priority = p; mark(i, 1, .priority); i += 1; continue
            }
            // Project: #Name, #"Two Words", or #two words matching a known project
            if w.hasPrefix("#"), w.count > 1, result.projectName == nil {
                let (name, n) = matchName(words: words, at: i, prefix: "#", known: knownProjects)
                result.projectName = name; mark(i, n, .project); i += n; continue
            }
            // Label: @name
            if w.hasPrefix("@"), w.count > 1 {
                let (name, n) = matchName(words: words, at: i, prefix: "@", known: knownLabels)
                if !result.labelNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    result.labelNames.append(name)
                }
                mark(i, n, .label); i += n; continue
            }
            // Reminder offset: !15mb, !1hb, !1db (the "b" optional), !0 / !at
            if result.reminderOffsetMinutes == nil, let minutes = ReminderOffset.minutes(fromToken: w) {
                result.reminderOffsetMinutes = minutes; mark(i, 1, .reminder); i += 1; continue
            }
            // Recurrence
            if result.recurrence == nil, let (rule, n) = Self.matchRecurrence(lowers, at: i) {
                result.recurrence = rule; mark(i, n, .recurrence); i += n; continue
            }
            // Time
            if time == nil, let t = dateParser.matchTime(in: lowers, at: i) {
                time = (t.hour, t.minute); mark(i, t.consumed, .time); i += t.consumed; continue
            }
            // Date
            if date == nil, let (pd, n) = dateParser.matchDate(in: lowers, at: i) {
                date = pd.date; mark(i, n, .date); i += n
                // A bare hour right after a date word is its time, on a 24-hour clock: "tom 13", "friday 9".
                if time == nil, i < words.count, !consumed[i],
                   let t = dateParser.matchTime(in: lowers, at: i, allowBareHour: true) {
                    time = (t.hour, t.minute); mark(i, t.consumed, .time); i += t.consumed
                }
                continue
            }
            i += 1
        }

        // Title = whatever was not consumed, with surrounding quotes stripped.
        var titleWords: [String] = []
        for (k, word) in words.enumerated() where !consumed[k] {
            var t = word.text
            if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") { t = String(t.dropFirst().dropLast()) }
            titleWords.append(t)
        }
        result.title = titleWords.joined(separator: " ")

        // Resolve date/time. A date the user typed is kept as typed, even in the past ("yesterday").
        let dateWasTyped = date != nil
        if date == nil, let rule = result.recurrence {
            date = rule.firstOccurrence(onOrAfter: dateParser.today, calendar: dateParser.calendar)
        }
        if let time {
            var candidate = dateParser.date(date ?? dateParser.today, hour: time.0, minute: time.1)
            if !dateWasTyped, candidate < dateParser.now {
                if let rule = result.recurrence {
                    // Typed after today's time: the rule's next occurrence ("every weekday 9am" at 2 pm is
                    // tomorrow 9 am). Anchor first so "every month" from the 31st keeps the 31st.
                    let anchored = rule.anchored(to: candidate, calendar: dateParser.calendar)
                    result.recurrence = anchored
                    candidate = anchored.nextOccurrence(after: candidate, calendar: dateParser.calendar)
                } else {
                    candidate = dateParser.date(dateParser.day(1), hour: time.0, minute: time.1)
                }
            }
            result.dueDate = candidate
            result.hasDueTime = true
        } else if let date {
            result.dueDate = date
            result.hasDueTime = false
        }
        // "every month" keeps the day it starts on (the 31st stays the 31st after a short month).
        if let rule = result.recurrence, let due = result.dueDate {
            result.recurrence = rule.anchored(to: due, calendar: dateParser.calendar)
        }
        result.tokens.sort { $0.range.lowerBound < $1.range.lowerBound }
        return result
    }

    static func priority(from w: String) -> Priority? {
        var s = w
        if s.hasPrefix("!!") { s = "p" + s.dropFirst(2) }
        guard s.count == 2, s.hasPrefix("p"), let n = Int(String(s.last!)) else { return nil }
        return Priority(rawValue: n)
    }

    /// Resolves a `#`/`@`-prefixed name. Supports quoted names and multi-word known names.
    func matchName(words: [Word], at i: Int, prefix: Character, known: [String]) -> (String, Int) {
        var raw = String(words[i].text.dropFirst())
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
            raw = String(raw.dropFirst().dropLast())
            return (canonical(raw, in: known) ?? raw, 1)
        }
        // Try the longest known multi-word name starting with this word.
        var best: (String, Int)? = nil
        for name in known {
            let parts = name.split(separator: " ").map { $0.lowercased() }
            guard parts.count > 1, i + parts.count <= words.count else { continue }
            var ok = parts[0] == raw.lowercased()
            if ok {
                for k in 1..<parts.count where words[i + k].lower != parts[k] { ok = false; break }
            }
            if ok, best == nil || parts.count > best!.1 { best = (name, parts.count) }
        }
        if let best { return best }
        return (canonical(raw, in: known) ?? raw, 1)
    }

    func canonical(_ name: String, in known: [String]) -> String? {
        known.first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func matchRecurrence(_ words: [String], at i: Int) -> (RecurrenceRule, Int)? {
        let w = DateExpressionParser.normalize(words[i])
        switch w {
        case "daily": return (.daily, 1)
        case "weekly": return (.weekly, 1)
        case "monthly": return (.monthly, 1)
        case "yearly", "annually": return (.yearly, 1)
        case "every": break
        default: return nil
        }
        guard i + 1 < words.count else { return nil }
        let n = DateExpressionParser.normalize(words[i + 1])
        switch n {
        case "day": return (.daily, 2)
        case "week": return (.weekly, 2)
        case "month": return (.monthly, 2)
        case "year": return (.yearly, 2)
        case "weekday", "weekdays", "workday", "workdays": return (.weekdays, 2)
        case "weekend", "weekends": return (RecurrenceRule(frequency: .weekly, weekdays: [1, 7]), 2)
        case "morning", "night", "evening": return (.daily, 2)
        case "other":
            guard i + 2 < words.count else { return nil }
            switch DateExpressionParser.normalize(words[i + 2]) {
            case "day": return (RecurrenceRule(frequency: .daily, interval: 2), 3)
            case "week": return (RecurrenceRule(frequency: .weekly, interval: 2), 3)
            case "month": return (RecurrenceRule(frequency: .monthly, interval: 2), 3)
            case "year": return (RecurrenceRule(frequency: .yearly, interval: 2), 3)
            default: return nil
            }
        default: break
        }
        // every N days/weeks/months/years (an absurd N stays in the title)
        if let count = Int(n), (1...RecurrenceRule.maxInterval).contains(count), i + 2 < words.count,
           let unit = DateExpressionParser.unitDays(words[i + 2]) {
            let freq: RecurrenceRule.Frequency
            switch unit.component {
            case .day: freq = .daily
            case .weekOfYear: freq = .weekly
            case .month: freq = .monthly
            default: freq = .yearly
            }
            return (RecurrenceRule(frequency: freq, interval: count), 3)
        }
        // every mon, wed and fri
        var days = Set<Int>()
        var j = i + 1
        while j < words.count {
            let wj = DateExpressionParser.normalize(words[j])
            if wj == "and" || wj == "&" { j += 1; continue }
            guard let wd = DateExpressionParser.weekdayNames[wj] else { break }
            days.insert(wd); j += 1
        }
        if !days.isEmpty { return (RecurrenceRule(frequency: .weekly, weekdays: days), j - i) }
        return nil
    }
}

/// The reminder-offset grammar, shared by the parser, the chips and the notification copy.
///
/// `!15mb` or `!15m` = 15 minutes before the due time, `!1hb` / `!1h` = an hour before, `!1db` / `!1d` =
/// a day before; `!0` and `!at` = at the due time. The offset only matters for a task with a time.
public enum ReminderOffset {
    /// The longest offset accepted: four weeks.
    public static let maxMinutes = 28 * 24 * 60

    /// The offset in minutes a `!…` word stands for, or nil if it isn't one.
    public static func minutes(fromToken word: String) -> Int? {
        var w = DateExpressionParser.normalize(word)
        guard w.hasPrefix("!"), !w.hasPrefix("!!") else { return nil }
        w.removeFirst()
        if w == "0" || w == "at" { return 0 }
        if w.hasSuffix("b") { w.removeLast() }
        guard let unit = w.last else { return nil }
        let scale: Int
        switch unit {
        case "m": scale = 1
        case "h": scale = 60
        case "d": scale = 24 * 60
        default: return nil
        }
        let digits = w.dropLast()
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(digits), n > 0 else { return nil }
        // Overflow-checked: this runs on every keystroke, and "!9999999999999999d" used to trap.
        let (minutes, overflow) = n.multipliedReportingOverflow(by: scale)
        return !overflow && minutes <= maxMinutes ? minutes : nil
    }

    /// The token a chip writes: "!15mb", "!1hb", "!1db"; "!at" for zero.
    public static func token(minutes: Int) -> String {
        guard minutes > 0 else { return "!at" }
        if minutes % (24 * 60) == 0 { return "!\(minutes / (24 * 60))db" }
        if minutes % 60 == 0 { return "!\(minutes / 60)hb" }
        return "!\(minutes)mb"
    }

    /// "15 min", "1 hour", "2 hours", "1 day", "1 hr 30 min".
    public static func duration(minutes: Int) -> String {
        let day = 24 * 60
        let days = minutes / day, hours = (minutes % day) / 60, mins = minutes % 60
        if minutes > 0, minutes % day == 0 { return days == 1 ? "1 day" : "\(days) days" }
        if days == 0, hours > 0, mins == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        var parts: [String] = []
        if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
        if hours > 0 { parts.append("\(hours) hr") }
        if mins > 0 || parts.isEmpty { parts.append("\(mins) min") }
        return parts.joined(separator: " ")
    }

    /// The chip's wording: "15 min before"; "At time" for zero.
    public static func label(minutes: Int) -> String {
        minutes > 0 ? duration(minutes: minutes) + " before" : "At time"
    }
}
