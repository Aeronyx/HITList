import Foundation

/// One recognized span inside the quick-add text, so the UI can highlight it.
public struct QuickAddToken: Equatable, Sendable {
    public enum Kind: String, Sendable { case priority, project, label, date, time, recurrence, reminder }
    public var kind: Kind
    public var range: Range<String.Index>
    public var text: String
    /// Overridden by a later phrase of the same kind (brief 37: "p1 … p3", "jan 6 … in a month"): not
    /// highlighted, sets nothing, its words are title text. It applies again once every later phrase of its
    /// kind is switched off (`parse(_:disabling:)`).
    public var isSuperseded = false
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
    /// A reminder that long from now (`!15m`, brief 48), whatever the due date; nil when none was typed.
    public var reminderFromNow: ReminderSpan?
    /// When `reminderFromNow` goes off: the parser's `now` plus the span. Saved as the task's `reminderDate`.
    public var reminderDate: Date?
    /// A deadline picked from the card's "+" menu. It has no text token, so the parser never sets it.
    public var deadline: Date?
    /// A location typed from the card's "+" menu. It has no text token, so the parser never sets it.
    public var locationName: String?
    public var tokens: [QuickAddToken]

    public init(title: String = "", dueDate: Date? = nil, hasDueTime: Bool = false, priority: Priority = .p4,
                projectName: String? = nil, labelNames: [String] = [], recurrence: RecurrenceRule? = nil,
                reminderOffsetMinutes: Int? = nil, deadline: Date? = nil, locationName: String? = nil,
                tokens: [QuickAddToken] = [], reminderFromNow: ReminderSpan? = nil, reminderDate: Date? = nil) {
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
        self.reminderFromNow = reminderFromNow
        self.reminderDate = reminderDate
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

    /// How finished the text is (brief 48, George: a "!" phrase "only checks/adds a highlight after the user
    /// presses space instead of while they're typing it").
    public enum Mode: Sendable {
        /// Confirm, Siri, Claude: the end of the text ends the last word, so "Call mom !15m" sets the reminder.
        case final
        /// The quick-add card while it is typed in: a "!" word (`!15m`, `!15mb`, `!at`, `!!1`) at the very end,
        /// with no whitespace after it yet, is still being typed and stays plain title text.
        case live
    }

    public func parse(_ input: String, mode: Mode = .final) -> QuickAddResult {
        let words = Self.words(in: input)
        let lowers = words.map(\.lower)
        var consumed = [Bool](repeating: false, count: words.count)
        var result = QuickAddResult()
        var time: (Int, Int)? = nil
        var date: Date? = nil
        /// "in 2 hours": the due moment itself, unless a time is typed too (then that time on its day).
        var moment: Date? = nil
        /// The winning token of each kind that holds one value, by index in `result.tokens`. A reminder has
        /// two places (brief 48): one "from now" and one "before the due time" may stand side by side.
        var winner: [Slot: Int] = [:]
        var fromNow: ReminderSpan? = nil
        /// Words of superseded tokens: matched, so no other rule reads them, but title text.
        var supersededWords = Set<Int>()

        func mark(_ i: Int, _ n: Int, _ kind: QuickAddToken.Kind) {
            guard n > 0 else { return }
            let range = words[i].range.lowerBound..<words[i + n - 1].range.upperBound
            for k in i..<(i + n) { consumed[k] = true }
            result.tokens.append(QuickAddToken(kind: kind, range: range, text: String(input[range])))
        }

        /// `mark`, for a kind that holds one value: a later phrase overrides the earlier one (George,
        /// 2026-11-04), which stays in `tokens` as superseded and goes back to the title.
        func win(_ i: Int, _ n: Int, _ kind: QuickAddToken.Kind, slot: Slot? = nil) {
            let slot = slot ?? .kind(kind)
            if let earlier = winner[slot] {
                result.tokens[earlier].isSuperseded = true
                supersededWords.formUnion(words.indices.filter { result.tokens[earlier].range.contains(words[$0].range.lowerBound) })
            }
            mark(i, n, kind)
            winner[slot] = result.tokens.count - 1
        }

        var i = 0
        while i < words.count {
            if consumed[i] { i += 1; continue }
            let w = lowers[i]
            if mode == .live, w.hasPrefix("!"), words[i].range.upperBound == input.endIndex { i += 1; continue }

            // Priority: p1..p4, !!1..!!4
            if let p = Self.priority(from: w) {
                result.priority = p; win(i, 1, .priority); i += 1; continue
            }
            // Project: #Name, #"Two Words", or #two words matching a known project
            if w.hasPrefix("#"), w.count > 1 {
                let (name, n) = matchName(words: words, at: i, prefix: "#", known: knownProjects)
                result.projectName = name; win(i, n, .project); i += n; continue
            }
            // Label: @name
            if w.hasPrefix("@"), w.count > 1 {
                let (name, n) = matchName(words: words, at: i, prefix: "@", known: knownLabels)
                if !result.labelNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                    result.labelNames.append(name)
                }
                mark(i, n, .label); i += n; continue
            }
            // Reminder: !15m / !2h / !1d from now; !15mb / !2hb / !1db before the due time, !0 / !at at it
            switch ReminderPhrase(token: w) {
            case .fromNow(let span)?:
                fromNow = span; win(i, 1, .reminder, slot: .reminderFromNow); i += 1; continue
            case .beforeDue(let minutes)?:
                result.reminderOffsetMinutes = minutes; win(i, 1, .reminder, slot: .reminderBeforeDue); i += 1; continue
            case nil:
                break
            }
            // Recurrence
            if let (rule, n) = Self.matchRecurrence(lowers, at: i) {
                result.recurrence = rule; win(i, n, .recurrence); i += n; continue
            }
            // "in 10 minutes", "in two hours": a date token that sets the time as well
            if let (at, n) = dateParser.matchRelativeTime(in: lowers, at: i) {
                moment = at; date = dateParser.startOfDay(at); win(i, n, .date); i += n; continue
            }
            // Time
            if let t = dateParser.matchTime(in: lowers, at: i) {
                time = (t.hour, t.minute); win(i, t.consumed, .time); i += t.consumed; continue
            }
            // Date (a plain day drops the moment of an earlier "in 2 hours")
            if let (pd, n) = dateParser.matchDate(in: lowers, at: i) {
                date = pd.date; moment = nil; win(i, n, .date); i += n
                // A bare hour right after a date word is its time, on a 24-hour clock: "tom 13", "friday 9".
                // Only when no time is typed yet: a bare number is too weak to override "5pm".
                if time == nil, i < words.count, !consumed[i],
                   let t = dateParser.matchTime(in: lowers, at: i, allowBareHour: true) {
                    time = (t.hour, t.minute); win(i, t.consumed, .time); i += t.consumed
                }
                continue
            }
            i += 1
        }

        // A reminder before the due time is relative to it: with no time typed (or set by "in 2 hours") it is
        // plain title text and sets nothing (George, 0.4.1 and again on 0.5.0, brief 41: "A typed reminder like
        // '!15mb' should not highlight before there's a time"). Once a time is typed it lights up and counts.
        // The Reminder chip picked before a time keeps its offset in the draft (`QuickAddDraft`). A reminder
        // from now ("!15m") needs no time (brief 48).
        if time == nil, moment == nil {
            result.reminderOffsetMinutes = nil
            let beforeDue = { (token: QuickAddToken) in token.kind == .reminder && ReminderPhrase(token: token.text)?.isBeforeDue == true }
            for token in result.tokens where beforeDue(token) {
                for k in words.indices where token.range.contains(words[k].range.lowerBound) { consumed[k] = false }
            }
            result.tokens.removeAll(where: beforeDue)
        }
        result.reminderFromNow = fromNow
        result.reminderDate = fromNow.map { $0.date(from: dateParser.now, calendar: dateParser.calendar) }

        // Title = whatever was not consumed or was superseded, with surrounding quotes stripped.
        var titleWords: [String] = []
        for (k, word) in words.enumerated() where !consumed[k] || supersededWords.contains(k) {
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
        } else if let moment {
            result.dueDate = moment
            result.hasDueTime = true
        } else if let date {
            result.dueDate = date
            result.hasDueTime = false
        }
        // "every month" keeps the day it starts on (the 31st stays the 31st after a short month), and a
        // timed repeat its time.
        if let rule = result.recurrence, let due = result.dueDate {
            result.recurrence = rule.anchored(to: due, calendar: dateParser.calendar)
                .timed(to: due, hasTime: result.hasDueTime, calendar: dateParser.calendar)
        }
        result.tokens.sort { $0.range.lowerBound < $1.range.lowerBound }
        return result
    }

    /// Where a winning token is kept: one per kind, but two for reminders.
    enum Slot: Hashable {
        case kind(QuickAddToken.Kind)
        case reminderFromNow, reminderBeforeDue
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

/// A typed reminder (brief 48): `!15m`, `!2h`, `!1d`, `!90m`, `!1h30m`, `!1d12h` = that long from now;
/// the same with a "b" (`!15mb`, `!1hb`, `!1h30mb`) = that long before the due time; `!0` and `!at` = at the
/// due time. The parts come in the order d, h, m, each once, each N ≥ 1, four weeks at most in all. Nothing
/// else is a reminder (`!`, `!0m`, `!m`, `!15`, `!30m15h`, `!29d`).
public enum ReminderPhrase: Equatable, Sendable {
    case fromNow(ReminderSpan)
    /// 0 is at the due time.
    case beforeDue(minutes: Int)

    public var isBeforeDue: Bool {
        if case .beforeDue = self { return true }
        return false
    }

    /// The phrase a `!…` word stands for (case and trailing ",.;" ignored), or nil if it isn't one.
    public init?(token word: String) {
        var w = Substring(DateExpressionParser.normalize(word))
        guard w.hasPrefix("!"), !w.hasPrefix("!!") else { return nil }
        w.removeFirst()
        if w == "0" || w == "at" { self = .beforeDue(minutes: 0); return }
        let before = w.hasSuffix("b")
        if before { w.removeLast() }
        guard let span = ReminderSpan(parts: w) else { return nil }
        self = before ? .beforeDue(minutes: span.totalMinutes) : .fromNow(span)
    }
}

/// How long a reminder phrase reaches: whole days (each the same clock time on the next day, so `!1d` keeps
/// 9:00 across a daylight-saving change) and minutes (real time: `!1h` is always 60 minutes on).
public struct ReminderSpan: Hashable, Codable, Sendable {
    public var days: Int
    public var minutes: Int

    public init(days: Int = 0, minutes: Int = 0) {
        self.days = days
        self.minutes = minutes
    }

    public var totalMinutes: Int { days * 24 * 60 + minutes }

    /// "1d12h30m" (no "!"): parts in the order d, h, m, each once, each a whole number ≥ 1. Nil for anything
    /// else, or longer than `ReminderOffset.maxMinutes`. Overflow-checked: it runs on every keystroke.
    init?(parts: Substring) {
        var days = 0, minutes = 0, lastUnit = -1, digits = ""
        for c in parts {
            if c.isASCII, c.isNumber { digits.append(c); continue }
            let unit: Int, scale: Int
            switch c {
            case "d": unit = 0; scale = 24 * 60
            case "h": unit = 1; scale = 60
            case "m": unit = 2; scale = 1
            default: return nil
            }
            guard unit > lastUnit, let n = Int(digits), n > 0 else { return nil }
            let (value, overflow) = n.multipliedReportingOverflow(by: scale)
            guard !overflow, value <= ReminderOffset.maxMinutes else { return nil }
            if unit == 0 { days = n } else { minutes += value }
            lastUnit = unit
            digits = ""
        }
        guard digits.isEmpty, lastUnit >= 0 else { return nil }
        self.init(days: days, minutes: minutes)
        guard totalMinutes <= ReminderOffset.maxMinutes else { return nil }
    }

    /// `now` plus the span: the days on the calendar, then the minutes in real time.
    public func date(from now: Date, calendar: Calendar = .current) -> Date {
        let day = days == 0 ? now : calendar.date(byAdding: .day, value: days, to: now) ?? now.addingTimeInterval(TimeInterval(days * 86_400))
        return day.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// "15 min", "1 hour", "1 hr 30 min", "1 day", "2 days 1 hr".
    public var text: String { ReminderOffset.duration(minutes: totalMinutes) }

    /// The token a chip writes: "!15m", "!1h", "!90m", "!1d", "!1d30m".
    public var token: String {
        var out = "!"
        if days > 0 { out += "\(days)d" }
        if minutes > 0 { out += minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m" }
        return out
    }
}

/// The before-the-due-time half of the reminder grammar (`ReminderPhrase.beforeDue`), shared by the parser,
/// the chips and the notification copy. The parser reads one only when the task has a due time; without one
/// it is title text (`QuickAddParser.parse`).
public enum ReminderOffset {
    /// The longest offset accepted: four weeks.
    public static let maxMinutes = 28 * 24 * 60

    /// The offset in minutes a `!…mb` / `!…hb` / `!…db` / `!0` / `!at` word stands for, or nil if it isn't
    /// one (`!15m` is 15 minutes from now, not an offset).
    public static func minutes(fromToken word: String) -> Int? {
        guard case .beforeDue(let minutes)? = ReminderPhrase(token: word) else { return nil }
        return minutes
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
