import Foundation

// The Repeat menu (brief 97; George, 2026-11-11: "there should be a custom dropdown like when repeating tasks on a
// calendar"): seven choices worded for the task's day, as Todoist words them, then Custom… and Don't repeat. The words,
// the rule each choice is, and which choice the rule in force is all come from here, so every picker says the same.

/// One of the Repeat menu's seven choices for a day: "Every week on Wednesday", "Every month on the 11th".
public struct RepeatChoice: Hashable, Sendable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable {
        case everyDay, weekdays, weekly, everyTwoWeeks, monthly, everyThreeMonths, yearly
    }

    public let kind: Kind
    /// What picking it sets: the rule typing its words makes (`QuickAddParser`).
    public let rule: RecurrenceRule
    /// The repeat itself, at full strength: "Every week", "Every 3 months".
    public let lead: String
    /// Where it falls, quieter (picture 4): "on Wednesday", "(Mon – Fri)", "on the 11th"; empty for Every day.
    public let detail: String

    public var id: Kind { kind }

    /// "Every week on Wednesday".
    public var title: String { detail.isEmpty ? lead : lead + " " + detail }

    /// The seven choices for a task due on `day` (today for a task with no date): Every day · Every weekday (Mon –
    /// Fri) · Every week on Wednesday · Every 2 weeks on Wednesday · Every month on the 11th · Every 3 months on the
    /// 11th · Every year on November 11. The weekly choices are plain weekly rules (the day is the task's own, as
    /// "every week" typed beside a Wednesday is); the monthly and yearly ones keep their place ("every month on the
    /// 11th"), so a short month's last day stands in for the 29th to 31st and Feb 29 is Feb 28 in other years.
    public static func all(for day: Date, calendar: Calendar = .current) -> [RepeatChoice] {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: day)
        let date = parts.day ?? 1
        let month = parts.month ?? 1
        let weekday = "on " + RepeatWords.weekdays[(parts.weekday ?? 1) - 1]
        let dayOfMonth = RepeatWords.on(.day(date), shortMonth: false)
        return [
            RepeatChoice(kind: .everyDay, rule: .daily, lead: "Every day", detail: ""),
            RepeatChoice(kind: .weekdays, rule: .weekdays, lead: "Every weekday", detail: "(Mon – Fri)"),
            RepeatChoice(kind: .weekly, rule: .weekly, lead: "Every week", detail: weekday),
            RepeatChoice(kind: .everyTwoWeeks, rule: RecurrenceRule(frequency: .weekly, interval: 2),
                         lead: "Every 2 weeks", detail: weekday),
            RepeatChoice(kind: .monthly, rule: RecurrenceRule(frequency: .monthly, place: .day(date)),
                         lead: "Every month", detail: dayOfMonth),
            RepeatChoice(kind: .everyThreeMonths, rule: RecurrenceRule(frequency: .monthly, interval: 3, place: .day(date)),
                         lead: "Every 3 months", detail: dayOfMonth),
            RepeatChoice(kind: .yearly, rule: RecurrenceRule(frequency: .yearly, place: .date(month: month, day: date)),
                         lead: "Every year", detail: RepeatWords.on(.date(month: month, day: date), shortMonth: false)),
        ]
    }

    /// The choice the rule in force is on a task due on `day`, ticked in the menu; nil when it is none of them (it then
    /// has a ticked line of its own, `rule.displayText`). A rule is a choice when it is that rule, or when it repeats
    /// as often and lands on the same days from `day`: "Every month" before 0.9.4 kept the day it started on, and
    /// "every wednesday" on a Wednesday is "Every week on Wednesday". Its time of day does not count.
    public static func matching(_ rule: RecurrenceRule?, on day: Date, calendar: Calendar = .current) -> RepeatChoice? {
        guard let rule else { return nil }
        let choices = all(for: day, calendar: calendar)
        if let same = choices.first(where: { $0.rule == rule }) { return same }
        return choices.first { choice in
            choice.rule.frequency == rule.frequency && choice.rule.interval == rule.interval
                && Self.days(of: choice.rule, from: day, calendar: calendar) == Self.days(of: rule, from: day, calendar: calendar)
        }
    }

    /// The next two years or so of days `rule` lands on after `day`, by day.
    static func days(of rule: RecurrenceRule, from day: Date, calendar: Calendar, count: Int = 26) -> [Date] {
        let untimed = rule.withoutTime
        var at = calendar.startOfDay(for: day)
        var out: [Date] = []
        out.reserveCapacity(count)
        for _ in 0..<count {
            at = untimed.nextOccurrence(after: at, calendar: calendar)
            out.append(calendar.startOfDay(for: at))
        }
        return out
    }
}

extension RecurrenceRule {
    /// What picking a repeat does to a task (`picked`).
    public struct Pick: Equatable, Sendable {
        /// The task's due date: the one it had, or the repeat's next occurrence for a task with none.
        public var due: Date
        public var hasTime: Bool
        /// The rule to store, anchored to the day it returns to and timed to the task's time.
        public var rule: RecurrenceRule
    }

    /// What picking this repeat (the Repeat menu, Custom…) does to a task due at `due` (nil: no date) whose repeat was
    /// `previous`: what typing its words does (brief 97, item 4; `QuickAddParser`). A task with a day keeps it, as a
    /// typed day is kept, and its time; one with no date gets the repeat's next occurrence from today, all day. The rule
    /// is anchored to the day (keeping the day `previous` returned to while the task is still on it,
    /// `keepingAnchor`) and timed to the task's time.
    public func picked(due: Date?, hasTime: Bool, previous: RecurrenceRule?, now: Date = Date(),
                       calendar: Calendar = .current) -> Pick {
        let day = due ?? firstOccurrence(onOrAfter: calendar.startOfDay(for: now), calendar: calendar)
        let timed = due != nil && hasTime
        let rule = keepingAnchor(of: previous, due: day, calendar: calendar).timed(to: day, hasTime: timed, calendar: calendar)
        return Pick(due: day, hasTime: timed, rule: rule)
    }

    /// The words the quick-add card writes for this rule, which read back as it (`QuickAddParser`): "every day",
    /// "every 3 days", "every weekday", "every tue, thu and sat", "every 2 weeks", "every month on the 11th",
    /// "every 3 months on the last day", "every month on the second wednesday", "every year on nov 11". Nil for the
    /// one shape quick add cannot type: two or more weeks apart on days of their own ("every 2 weeks on tue and thu").
    public var typedWords: String? {
        let n = interval
        if let place {
            let head: String
            switch place {
            case .day, .lastDay, .weekday: head = n == 1 ? "every month" : "every \(n) months"
            case .date: head = n == 1 ? "every year" : "every \(n) years"
            }
            return head + " " + RepeatWords.on(place, shortMonth: true).lowercased()
        }
        switch frequency {
        case .daily: return n == 1 ? "every day" : "every \(n) days"
        case .monthly: return n == 1 ? "every month" : "every \(n) months"
        case .yearly: return n == 1 ? "every year" : "every \(n) years"
        case .weekly:
            guard let days = weekdays, !days.isEmpty else { return n == 1 ? "every week" : "every \(n) weeks" }
            guard n == 1 else { return nil }
            if days == [2, 3, 4, 5, 6] { return "every weekday" }
            return "every " + RepeatWords.list(days.sorted().map { RepeatWords.shortWeekdays[$0 - 1].lowercased() })
        }
    }
}

/// The words the repeat pickers share (English, as the rest of the app).
public enum RepeatWords {
    /// Sunday first, as `Calendar`'s weekday numbers (1 = Sunday ... 7 = Saturday).
    public static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    public static let shortWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    /// A day button's letter: S M T W T F S.
    public static let initials = ["S", "M", "T", "W", "T", "F", "S"]
    public static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                                "October", "November", "December"]
    public static let shortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "first" … "fifth", "last" (-1): which of a weekday's days in the month.
    public static func ordinalWord(_ ordinal: Int) -> String {
        switch ordinal {
        case 1: "first"
        case 2: "second"
        case 3: "third"
        case 4: "fourth"
        case 5: "fifth"
        default: "last"
        }
    }

    /// "1st", "2nd", "3rd", "11th", "22nd", "31st".
    public static func ordinal(_ day: Int) -> String { RecurrenceRule.ordinal(day) }

    /// Where a place falls, after the repeat: "on the 28th", "on the last day", "on the second Wednesday", "on
    /// November 11" ("on Nov 11" with `shortMonth`, as a row says it).
    public static func on(_ place: RecurrenceRule.Place, shortMonth: Bool) -> String {
        switch place {
        case .day(let day): return "on the \(ordinal(day))"
        case .lastDay: return "on the last day"
        case .weekday(let weekday, let ordinal):
            return "on the \(ordinalWord(ordinal)) \(weekdays[min(max(weekday, 1), 7) - 1])"
        case .date(let month, let day):
            let names = shortMonth ? shortMonths : months
            return "on \(names[min(max(month, 1), 12) - 1]) \(day)"
        }
    }

    /// "Mon", "Mon and Thu", "Tue, Thu and Sat".
    public static func list(_ words: [String]) -> String {
        guard words.count > 1 else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " and " + words.last!
    }

    /// Weekday numbers in the order of a week that starts on `weekStart` (1 = Sunday ... 7 = Saturday).
    public static func ordered(_ days: Set<Int>, weekStart: Int) -> [Int] {
        let start = (1...7).contains(weekStart) ? weekStart : 1
        return days.sorted { (($0 - start + 7) % 7) < (($1 - start + 7) % 7) }
    }

    /// The seven weekdays from `weekStart`: [2, 3, 4, 5, 6, 7, 1] for a week from Monday.
    public static func week(from weekStart: Int) -> [Int] {
        let start = (1...7).contains(weekStart) ? weekStart : 1
        return (0..<7).map { (start - 1 + $0) % 7 + 1 }
    }
}
