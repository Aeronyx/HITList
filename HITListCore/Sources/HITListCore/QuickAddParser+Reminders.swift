import Foundation

// Reminders in words (brief 175, George 2026-11-23: "I typed `!0mb` and it didn't register that I wanted a reminder,
// nor did spelling out anything about a reminder"). The reminder list on "!" writes readable phrases, as Todoist does,
// and the parser reads them back, one token however many words:
//
//   !At time of task, !at time, !at the time                 zero before the due time (needs a time, as `!0mb` does)
//   !10 minutes before, !1 hour before, !an hour before       that long before it (minute(s), min(s), hour(s), hr(s),
//                                                            day(s), week(s); N a number, a number word up to twelve,
//                                                            "a" or "an"; "half an hour before" too)
//   !In 5 minutes, !in an hour, !in half an hour, !in 2 days  that long from now
//   !4pm, !4:00 PM, !4 p.m., !16:00, !at 4pm, !tomorrow 9am   at that clock time (`ReminderClock`)
//
// "remind me" before any of these, without the "!", is the same reminder ("remind me 30 minutes before", "remind me at
// 4pm", "remind me at the time"). "reminder" alone is weaker evidence (plenty of titles hold the word: "Send reminder
// at 3pm", "Pay bill reminder tomorrow 9am"), so it takes only the forms measured from something, never a clock time
// or a day: "reminder 1 hour before", "reminder in 10 minutes", "reminder at the time" (the supervisor, round 36).
// Not followed by one, they are title words ("Remind Sam about the party", "Reminder: pay rent"). And they are said to
// the app, not part of a sentence (the review of brief 175): "reminder" counts only where it opens the text, or after
// punctuation or another phrase ("Call mom 5pm, reminder 30 minutes before"), never after a title word ("Set a reminder
// in 10 minutes to check the oven", "Send reminder in 2 days"); "remind me" never right after "to" ("Ask Sam to remind
// me in 2 days"). "!10 minutes" (no "before", no "in") is not a phrase. The one-word codes (`!15m`, `!15mb`, `!at`,
// `!0`) still work (`ReminderPhrase(code:)`).
extension ReminderPhrase {
    /// One reading of a reminder phrase: what it means, how many words it takes, and whether its clock time is "at 1"
    /// to "at 6" with no am or pm (`shortHour`), which `phrase` holds as typed (24-hour). The parser settles that hour
    /// from the whole text (`QuickAddParser.shortHour`: "every morning, remind me at 5" is 5 am); read alone
    /// (`match`), it is the afternoon.
    struct Reading {
        var phrase: ReminderPhrase
        var length: Int
        var shortHour = false
    }

    /// The reminder phrase starting at `words[i]` (the parser's lowercased words, punctuation as typed): what it means
    /// and how many words it takes, the longest reading. `atStart`: the words open the text, where a "to" right after a
    /// phrase said in words belongs to it ("Remind me in 30 minutes to call mom" leaves "Call mom"). A short hour with
    /// nothing around it to say otherwise is the afternoon ("!at 4" is 4 pm).
    static func match(_ words: [String], at i: Int, atStart: Bool = false) -> (ReminderPhrase, Int)? {
        guard let reading = reading(words, at: i, atStart: atStart) else { return nil }
        guard reading.shortHour, case .at(var clock) = reading.phrase else { return (reading.phrase, reading.length) }
        clock.hour += 12
        return (.at(clock), reading.length)
    }

    /// `match`, with a short hour as typed and said to be one. `afterPhrase`: the word before `words[i]` belongs to a
    /// phrase already read (a time, a date, a priority), which ends the sentence before it as punctuation does.
    static func reading(_ words: [String], at i: Int, atStart: Bool = false, afterPhrase: Bool = false) -> Reading? {
        guard i < words.count else { return nil }
        let first = words[i]
        if first.hasPrefix("!") {
            guard !first.hasPrefix("!!") else { return nil }
            var body = Array(words[i...])
            body[0] = String(first.dropFirst())
            if let match = matchBody(body, at: 0) { return match }
            return ReminderPhrase(code: first).map { Reading(phrase: $0, length: 1) }
        }
        let lead: Int
        // "reminder" on its own reads only the relative forms: never a clock time or a day.
        var clocks = true
        let previous = i > 0 ? words[i - 1] : nil
        switch DateExpressionParser.normalize(first) {
        case "remind" where i + 1 < words.count && DateExpressionParser.normalize(words[i + 1]) == "me":
            // "Ask Sam to remind me in 2 days": someone else's to do.
            guard previous.map(DateExpressionParser.normalize) != "to" else { return nil }
            lead = 2
        case "reminder":
            // Said to the app where it opens the text or a clause; after a title word ("Set a reminder", "Send
            // reminder", "my reminder") it is the sentence's.
            guard previous.map({ afterPhrase || endsClause($0) }) ?? true else { return nil }
            lead = 1; clocks = false
        default: return nil
        }
        guard var reading = matchBody(words, at: i + lead, clocks: clocks) else { return nil }
        reading.length += lead
        if atStart, i + reading.length < words.count, DateExpressionParser.normalize(words[i + reading.length]) == "to" {
            reading.length += 1
        }
        return reading
    }

    /// A word that ends a clause: one ending in ",", ".", ";", ":", "!", "?" or ")", or a dash on its own.
    static func endsClause(_ word: String) -> Bool {
        if ["-", "–", "—"].contains(word) { return true }
        return word.last.map { ",.;:!?)".contains($0) } ?? false
    }

    /// The words after the "!" (or after "remind me" / "reminder"), longest reading first. `clocks: false` leaves out the
    /// clock times and days ("reminder" alone, `match`).
    static func matchBody(_ words: [String], at j: Int, clocks: Bool = true) -> Reading? {
        guard j < words.count, !words[j].isEmpty else { return nil }
        var readings = [matchAtTheTime(words, at: j), matchBefore(words, at: j), matchFromNow(words, at: j)]
            .map { $0.map { Reading(phrase: $0.0, length: $0.1) } }
        if clocks { readings.append(matchClock(words, at: j)) }
        return readings.compactMap { $0 }.max { $0.length < $1.length }
    }

    private static func word(_ words: [String], _ k: Int) -> String? {
        k < words.count ? DateExpressionParser.normalize(words[k]) : nil
    }

    /// "at time of task", "at the time", "at time", "at the time of the task": zero before the due time.
    private static func matchAtTheTime(_ words: [String], at j: Int) -> (ReminderPhrase, Int)? {
        guard word(words, j) == "at" else { return nil }
        var k = j + 1
        if word(words, k) == "the" { k += 1 }
        guard word(words, k) == "time" else { return nil }
        k += 1
        // "… of task", "… of the task"
        if word(words, k) == "of" {
            var m = k + 1
            if word(words, m) == "the" { m += 1 }
            if word(words, m) == "task" { k = m + 1 }
        }
        return (.beforeDue(minutes: 0), k - j)
    }

    /// Minutes in one of a span's units: minute(s), min(s), hour(s), hr(s), day(s), week(s), wk(s).
    static func unitMinutes(_ word: String?) -> Int? {
        guard let word else { return nil }
        if let minutes = DateExpressionParser.unitMinutes(word) { return minutes }
        switch word {
        case "day", "days": return 24 * 60
        case "week", "weeks", "wk", "wks": return 7 * 24 * 60
        default: return nil
        }
    }

    /// "10 minutes", "an hour", "two days", "half an hour": the minutes, whether the unit was days or weeks, and the words
    /// taken. `zero`: "0 minutes" counts.
    private static func matchSpan(_ words: [String], at j: Int, zero: Bool) -> (minutes: Int, inDays: Bool, consumed: Int)? {
        if word(words, j) == "half", ["a", "an"].contains(word(words, j + 1) ?? ""), unitMinutes(word(words, j + 2)) == 60 {
            return (30, false, 3)
        }
        guard let w = word(words, j), let count = DateExpressionParser.count(w), count >= (zero ? 0 : 1),
              let unit = unitMinutes(word(words, j + 1)) else { return nil }
        let (total, overflow) = count.multipliedReportingOverflow(by: unit)
        guard !overflow, total <= ReminderOffset.maxMinutes else { return nil }
        return (total, unit >= 24 * 60, 2)
    }

    /// "10 minutes before", "1 hour before", "half an hour before".
    private static func matchBefore(_ words: [String], at j: Int) -> (ReminderPhrase, Int)? {
        guard let span = matchSpan(words, at: j, zero: true), word(words, j + span.consumed) == "before" else { return nil }
        return (.beforeDue(minutes: span.minutes), span.consumed + 1)
    }

    /// "in 5 minutes", "in an hour", "in half an hour", "in 2 days": days and weeks are days (the same clock time on that
    /// day, as `!1d` is), minutes and hours real time (as `!24h` is).
    private static func matchFromNow(_ words: [String], at j: Int) -> (ReminderPhrase, Int)? {
        guard word(words, j) == "in", let span = matchSpan(words, at: j + 1, zero: false) else { return nil }
        let reach = span.inDays ? ReminderSpan(days: span.minutes / (24 * 60)) : ReminderSpan(minutes: span.minutes)
        return (.fromNow(reach), span.consumed + 1)
    }

    /// "4pm", "4:00 pm", "4 p.m.", "16:00", "noon", "at 4pm", "at 4" (a short hour, read as a due time's is), and a
    /// day before it: "today 4pm", "tomorrow 9am", "tomorrow at 9". A bare "4" is not one ("!15" is no reminder).
    private static func matchClock(_ words: [String], at j: Int) -> Reading? {
        var k = j
        var day: Int? = nil
        switch word(words, k) {
        case "today", "tod", "tonight": day = 0; k += 1
        case "tomorrow", "tom", "tmr", "tmrw": day = 1; k += 1
        default: break
        }
        guard let time = DateExpressionParser().matchTime(in: words, at: k, afternoonAfterAt: false) else { return nil }
        return Reading(phrase: .at(ReminderClock(hour: time.hour, minute: time.minute, day: day)),
                       length: k - j + time.consumed, shortHour: time.shortHour)
    }
}

/// The clock time a reminder goes off at (`!4pm`, `!4:00 PM`, "remind me at 4pm", `!tomorrow 9am`; brief 175): a moment
/// of the task's own, as "!15m" is, kept as the task's `reminderDate`.
public struct ReminderClock: Hashable, Codable, Sendable {
    public var hour: Int
    public var minute: Int
    /// A day typed with it: 0 today, 1 tomorrow. Nil when only the time was typed.
    public var day: Int?

    public init(hour: Int, minute: Int, day: Int? = nil) {
        self.hour = hour
        self.minute = minute
        self.day = day
    }

    /// When it goes off. With a day typed, that day at that time. Otherwise on the task's due day (`dueDay`) when it has
    /// one and that moment is still to come; else today if the time is still ahead; else tomorrow. Never a moment
    /// already gone when a later one will do: "!4pm" on a task due today, typed at 5 pm, is tomorrow 4 pm.
    public func date(dueDay: Date?, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        func at(_ day: Date) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: day)) ?? day
        }
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        if let typed = self.day { return at(day(typed)) }
        if let dueDay, at(dueDay) > now { return at(dueDay) }
        let todays = at(today)
        return todays > now ? todays : at(day(1))
    }

    /// "4:00 PM", "9:30 AM": the time as the list writes it, on a 12-hour clock with a plain space whatever the locale (the
    /// parser reads it back the same everywhere).
    public var text: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", h12, minute, hour < 12 ? "AM" : "PM")
    }

    /// "!4pm", "!9:30am": the code a person can type instead.
    public var code: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        return minute == 0 ? "!\(h12)\(suffix)" : String(format: "!%d:%02d%@", h12, minute, suffix)
    }
}

extension ReminderOffset {
    /// The words a pick writes (brief 175): "!At time of task", "!10 minutes before", "!1 hour before", "!2 days before".
    /// Each reads back as `ReminderPhrase.beforeDue` of the same minutes.
    public static func phrase(minutes: Int) -> String {
        guard minutes > 0 else { return "!At time of task" }
        let day = 24 * 60
        if minutes % day == 0 { return "!" + count(minutes / day, "day") + " before" }
        if minutes % 60 == 0 { return "!" + count(minutes / 60, "hour") + " before" }
        return "!" + count(minutes, "minute") + " before"
    }

    /// "1 day", "2 hours", "15 minutes".
    static func count(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
}

extension ReminderSpan {
    /// The words a pick writes (brief 175): "!In 15 minutes", "!In 1 hour", "!In 2 days". A span of days and minutes both
    /// has no such words and keeps its code ("!1d30m"). Each reads back as `ReminderPhrase.fromNow` of the same span.
    public var phrase: String {
        if days > 0 { return minutes > 0 ? token : "!In " + ReminderOffset.count(days, "day") }
        if minutes > 0, minutes % 60 == 0 { return "!In " + ReminderOffset.count(minutes / 60, "hour") }
        return "!In " + ReminderOffset.count(minutes, "minute")
    }
}
