import Foundation

/// What a Todoist DATE (or DEADLINE) cell holds, read by HITList's own quick-add reader first.
public struct TodoistDateReading: Equatable, Sendable {
    public var due: Date?
    public var hasTime: Bool
    public var recurrence: RecurrenceRule?
    /// What HITList cannot hold of it, in plain words for the task's notes.
    public var notes: [String] = []
}

/// Brief 137: Todoist writes a date the way a person typed it ("every day", "Nov 20", "every mon, wed at 9am",
/// "every! 3 days", "every day until Dec 31"), in the language DATE_LANG names. `QuickAddParser` reads nearly all of
/// it; this adds what Todoist writes and quick add does not ("ev", "every!"/"after", "until"/"ending", an ISO date
/// with a time, the TIMEZONE column), and keeps a day without a year that is only just past (an overdue task) in
/// this year instead of moving it to next. Anything else, and every language but English, is refused: the caller
/// keeps the words in the task's notes.
public struct TodoistDateReader: Sendable {
    public var now: Date
    public var calendar: Calendar
    /// How far back a day written without a year still counts as this year's (overdue) day.
    public static let overdueWindowDays = 31

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    public func read(_ text: String, language: String = "", timeZone: String = "") -> TodoistDateReading? {
        var words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return nil }
        let lang = language.trimmingCharacters(in: .whitespaces).lowercased()
        guard lang.isEmpty || lang == "en" || lang.hasPrefix("en_") || lang.hasPrefix("en-") else { return nil }
        let original = words
        var notes: [String] = []

        if let r = words.range(of: #"^ev(?=!|\s)"#, options: [.regularExpression, .caseInsensitive]) {
            words.replaceSubrange(r, with: "every")
        }
        if let r = words.range(of: #"^every!"#, options: [.regularExpression, .caseInsensitive]) {
            words.replaceSubrange(r, with: "every")
            notes.append("Todoist repeated it from the day it was completed (\(original)).")
        } else if let r = words.range(of: #"^after(?=\s+(\d+|other|a|an|one|two|three)?\s*\w)"#, options: [.regularExpression, .caseInsensitive]) {
            words.replaceSubrange(r, with: "every")
            notes.append("Todoist repeated it from the day it was completed (\(original)).")
        }
        if let r = words.range(of: #"\s+(until|ending)\s+.+$"#, options: [.regularExpression, .caseInsensitive]),
           words.lowercased().hasPrefix("every") {
            let end = words[r].trimmingCharacters(in: .whitespaces)
            notes.append("Todoist stopped the repeat: \(end).")
            words.removeSubrange(r)
        }

        guard var reading = parse(words, calendar: calendar) else { return nil }
        if reading.hasTime, reading.recurrence == nil, let zone = TimeZone(identifier: timeZone), zone != calendar.timeZone {
            var zoned = calendar
            zoned.timeZone = zone
            if let inZone = parse(words, calendar: zoned) { reading = inZone }
        }
        reading.notes = notes
        return reading
    }

    private func parse(_ words: String, calendar: Calendar) -> TodoistDateReading? {
        if let iso = isoDateTime(words, calendar: calendar) { return iso }
        let parsed = QuickAddParser(now: now, calendar: calendar).parse(words)
        guard parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              parsed.dueDate != nil || parsed.recurrence != nil else { return nil }
        var due = parsed.dueDate
        if parsed.recurrence == nil, let date = due, words.range(of: #"\b\d{4}\b"#, options: .regularExpression) == nil,
           calendar.component(.year, from: date) == calendar.component(.year, from: now) + 1,
           let lastYear = calendar.date(byAdding: .year, value: -1, to: date),
           let windowStart = calendar.date(byAdding: .day, value: -Self.overdueWindowDays, to: calendar.startOfDay(for: now)),
           lastYear >= windowStart {
            due = lastYear
        }
        return TodoistDateReading(due: due, hasTime: parsed.hasDueTime, recurrence: parsed.recurrence)
    }

    /// "2026-11-20 14:00", "2026-11-20T14:00:00": a date and time written the machine's way.
    private func isoDateTime(_ words: String, calendar: Calendar) -> TodoistDateReading? {
        let pattern = #"^(\d{4})-(\d{2})-(\d{2})[ T](\d{1,2}):(\d{2})(:\d{2})?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: words, range: NSRange(words.startIndex..., in: words)) else { return nil }
        func int(_ i: Int) -> Int? { Range(match.range(at: i), in: words).flatMap { Int(words[$0]) } }
        var comps = DateComponents()
        comps.year = int(1); comps.month = int(2); comps.day = int(3); comps.hour = int(4); comps.minute = int(5)
        guard let date = calendar.date(from: comps) else { return nil }
        return TodoistDateReading(due: date, hasTime: true, recurrence: nil)
    }
}
