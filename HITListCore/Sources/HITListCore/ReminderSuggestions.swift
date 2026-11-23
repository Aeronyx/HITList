import Foundation

/// One row of the reminder list that opens on "!" in quick add (brief 175, after Todoist's): a label, the line under
/// it, and the words a pick writes into the title (`phrase`), which the parser reads back as `reminder`.
public struct ReminderSuggestion: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// Before the task's time ("10 minutes before"): a clock.
        case before
        /// That long from now ("In 15 minutes"): a calendar with a clock.
        case fromNow
        /// A clock time a few hours on ("Later"): a clock with a forward arrow.
        case later
    }

    public var kind: Kind
    public var id: String
    /// "At time of task", "10 minutes before", "In 15 minutes", "Later".
    public var label: String
    /// What a pick writes in place of the typed "!…": "!At time of task", "!10 minutes before", "!In 15 minutes",
    /// "!4:00 PM".
    public var phrase: String
    /// What a person can type instead next time: "!0mb", "!10mb", "!15m", "!4pm".
    public var code: String
    /// The grey line under the label: the code; for Later its time ("4:00 PM", "Tomorrow 9:00 AM").
    public var detail: String
    /// What the phrase sets.
    public var reminder: ReminderPhrase

    /// VoiceOver: the label, then the line under it ("10 minutes before, exclamation 10 m b"; "Later, 4:00 PM").
    public var spokenLabel: String {
        kind == .later ? "\(label), \(detail)" : "\(label), \(ReminderSuggestions.spoken(code))"
    }
}

/// The reminder list's rows, how typing narrows them, and the "!" word it answers (brief 175). Pure: the quick-add
/// card asks with the text, the caret and the task's time; the tests pin every row against the parser.
public enum ReminderSuggestions {
    /// The task has a time: these before it, then the from-now rows and Later.
    public static let beforeMinutes = [0, 10, 30, 45, 60, 120, 180, 24 * 60]
    public static let timedFromNowMinutes = [5, 15, 30]
    /// No time: from now, then Later.
    public static let untimedFromNowMinutes = [5, 15, 30, 60]

    /// Later: three hours from now, rounded up to the next whole hour; if that is after 10 PM, 9:00 AM tomorrow.
    public static func later(now: Date, calendar: Calendar = .current) -> Date {
        // To the minute, as "in 2 hours" counts: 1:00:30 PM is 4:00 PM, not 5.
        let minute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let ahead = minute.addingTimeInterval(3 * 3600)
        let hourStart = calendar.dateInterval(of: .hour, for: ahead)?.start ?? ahead
        let rounded = hourStart < ahead ? calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? ahead : hourStart
        let today = calendar.startOfDay(for: now)
        let tenPM = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: today) ?? today
        guard rounded > tenPM else { return rounded }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// The rows for a task with a time (`hasTime`, typed or picked) or without, in order. `dueDate` is the task's due
    /// day, if it has one: Later's words name its day when a clock time alone would go off on another (a clock time
    /// goes off on the task's due day, `ReminderClock.date`).
    public static func rows(hasTime: Bool, dueDate: Date? = nil, now: Date, calendar: Calendar = .current) -> [ReminderSuggestion] {
        var rows: [ReminderSuggestion] = []
        if hasTime {
            rows += beforeMinutes.map(before)
            rows += timedFromNowMinutes.map(fromNow)
        } else {
            rows += untimedFromNowMinutes.map(fromNow)
        }
        rows.append(laterRow(dueDate: dueDate, now: now, calendar: calendar))
        return rows
    }

    static func before(_ minutes: Int) -> ReminderSuggestion {
        let label = minutes == 0 ? "At time of task" : String(ReminderOffset.phrase(minutes: minutes).dropFirst())
        // "!0mb" as Todoist shows it ("!at" and "!0" work too).
        let code = minutes == 0 ? "!0mb" : ReminderOffset.token(minutes: minutes)
        return ReminderSuggestion(kind: .before, id: "before-\(minutes)", label: label,
                                  phrase: ReminderOffset.phrase(minutes: minutes), code: code, detail: code,
                                  reminder: .beforeDue(minutes: minutes))
    }

    static func fromNow(_ minutes: Int) -> ReminderSuggestion {
        let span = ReminderSpan(minutes: minutes)
        return ReminderSuggestion(kind: .fromNow, id: "in-\(minutes)", label: String(span.phrase.dropFirst()),
                                  phrase: span.phrase, code: span.token, detail: span.token, reminder: .fromNow(span))
    }

    static func laterRow(dueDate: Date?, now: Date, calendar: Calendar) -> ReminderSuggestion {
        let at = later(now: now, calendar: calendar)
        let parts = calendar.dateComponents([.hour, .minute], from: at)
        let plain = ReminderClock(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        let isToday = calendar.isDate(at, inSameDayAs: now)
        let phrase: String
        let clock: ReminderClock
        if !isToday {
            clock = ReminderClock(hour: plain.hour, minute: plain.minute, day: 1)
            phrase = "!Tomorrow " + plain.text
        } else if plain.date(dueDay: dueDate, now: now, calendar: calendar) == at {
            clock = plain
            phrase = "!" + plain.text
        } else {
            clock = ReminderClock(hour: plain.hour, minute: plain.minute, day: 0)
            phrase = "!Today " + plain.text
        }
        return ReminderSuggestion(kind: .later, id: "later", label: "Later", phrase: phrase, code: plain.code,
                                  detail: isToday ? plain.text : "Tomorrow " + plain.text, reminder: .at(clock))
    }

    /// The rows a typed query leaves (what follows the "!" up to the caret): those whose code starts with it ("!1":
    /// !10mb, !1hb, !1db, !15m, !1h) or with a word of the label starting with it ("!h": the hours; "!in": the In rows;
    /// "!at": At time of task). Nothing typed: every row. None left: the list closes.
    public static func narrowed(_ rows: [ReminderSuggestion], by query: String) -> [ReminderSuggestion] {
        let q = query.lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            row.code.dropFirst().lowercased().hasPrefix(q)
                || row.label.lowercased().split(separator: " ").contains { $0.hasPrefix(q) }
        }
    }

    /// The "!" word the caret is in, which the list answers.
    public struct BangWord: Equatable, Sendable {
        /// The whole word, "!" included (UTF-16 offsets, as the text views count): what a pick replaces.
        public var range: NSRange
        /// What is typed after the "!", up to the caret: what narrows the list.
        public var query: String

        public init(range: NSRange, query: String) {
            self.range = range
            self.query = query
        }
    }

    /// The word around `cursor` (a UTF-16 offset in `text`), when it starts with one "!" (not "!!", a priority) and the
    /// caret is past that "!"; nil otherwise, and after a space (a space ends the word: the list closes).
    public static func bangWord(in text: String, cursor: Int) -> BangWord? {
        let ns = text as NSString
        guard cursor > 0, cursor <= ns.length else { return nil }
        func isSpace(_ index: Int) -> Bool {
            guard let scalar = Unicode.Scalar(ns.character(at: index)) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        var start = cursor
        while start > 0, !isSpace(start - 1) { start -= 1 }
        var end = cursor
        while end < ns.length, !isSpace(end) { end += 1 }
        guard start < cursor, ns.character(at: start) == 0x21 /* ! */ else { return nil }
        if start + 1 < ns.length, ns.character(at: start + 1) == 0x21 { return nil }
        let query = ns.substring(with: NSRange(location: start + 1, length: cursor - start - 1))
        return BangWord(range: NSRange(location: start, length: end - start), query: query)
    }

    /// `text` with `range` (a `BangWord`'s) replaced by `phrase` and one space after it, and where the caret goes: after
    /// that space. A space already there is the one.
    public static func applying(_ phrase: String, to text: String, replacing range: NSRange) -> (text: String, cursor: Int) {
        let ns = text as NSString
        guard range.location >= 0, NSMaxRange(range) <= ns.length else { return (text, ns.length) }
        let end = NSMaxRange(range)
        let spaced = end < ns.length && Unicode.Scalar(ns.character(at: end)).map { CharacterSet.whitespaces.contains($0) } == true
        let replacement = spaced ? phrase : phrase + " "
        let new = ns.replacingCharacters(in: range, with: replacement)
        return (new, range.location + (phrase as NSString).length + 1)
    }

    /// "!10mb" read aloud: "exclamation 10 m b"; "!4:30pm": "exclamation 4:30 p m".
    static func spoken(_ code: String) -> String {
        var parts = ["exclamation"]
        var digits = ""
        for character in code.drop(while: { $0 == "!" }) {
            if character.isNumber || character == ":" {
                digits.append(character)
            } else {
                if !digits.isEmpty { parts.append(digits); digits = "" }
                parts.append(String(character))
            }
        }
        if !digits.isEmpty { parts.append(digits) }
        return parts.joined(separator: " ")
    }
}
