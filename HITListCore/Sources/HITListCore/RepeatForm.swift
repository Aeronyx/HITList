import Foundation

/// What the Repeat menu's Custom… card shows and builds (brief 97, item 2; macOS Calendar's custom repeat, George's
/// picture 5): a frequency; "Every [n] days / weeks / months / years"; for a weekly repeat its days; for a monthly
/// one a day of the month, the last day, or the first to fifth or last of a weekday; for a yearly one a month and
/// day. It can build every rule quick add can type. Opened on a rule it shows that rule, and while nothing it shows
/// has changed it gives that very rule back (its anchor day and time with it), so Done on a typed "every month" is
/// still "every month". With no rule it starts weekly on the day's own weekday; every other frequency starts on the
/// day's own place ("on the 11th", "on the second Wednesday", "on November 11").
public struct RepeatForm: Sendable {
    public enum MonthlyPlace: String, Hashable, Sendable, CaseIterable {
        /// On a day of the month (`monthDay`).
        case day
        case lastDay
        /// On the first to fifth or last (`ordinal`) of a weekday (`ordinalWeekday`).
        case weekday
    }

    public var frequency: RecurrenceRule.Frequency
    /// 1 to `RecurrenceRule.maxInterval`; the rule clamps anything else.
    public var interval: Int
    /// Weekly: the days (1 = Sunday ... 7 = Saturday); never empty (`toggle(weekday:)`).
    public var weekdays: Set<Int>
    public var monthly: MonthlyPlace
    /// Monthly on a day: 1 to 31 (a shorter month's last day stands in).
    public var monthDay: Int
    /// Monthly on a weekday: 1 to 5, or -1 for the last.
    public var ordinal: Int
    public var ordinalWeekday: Int
    /// Yearly: the month (1 to 12) and its day (`setMonth` keeps it inside the month; Feb 29 allowed).
    public private(set) var month: Int
    public var yearDay: Int

    /// The rule it was opened on, and what it showed then.
    private var opened: RecurrenceRule?
    private var openedShown: Shown?

    /// What the card shows for its frequency, and nothing else: two forms showing the same build the same rule.
    public struct Shown: Hashable, Sendable {
        var frequency: RecurrenceRule.Frequency
        var interval: Int
        var weekdays: Set<Int>?
        var place: RecurrenceRule.Place?
    }

    /// The card for a task due on `day` (today for a task with no date) whose repeat is `rule` (nil: none yet).
    public init(rule: RecurrenceRule?, day: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: day)
        let date = parts.day ?? 1
        let weekday = parts.weekday ?? 1
        // A plain "every month" / "every year" lands on the day it keeps returning to (its anchor while the day is on
        // it, or a short month's last day short of it), which is the day it shows.
        let returnsTo = rule.map { $0.targetDay(from: day, calendar: calendar) } ?? date
        frequency = rule?.frequency ?? .weekly
        interval = rule?.interval ?? 1
        weekdays = rule.flatMap { $0.frequency == .weekly ? $0.weekdays : nil } ?? [weekday]
        monthly = .day
        monthDay = rule?.frequency == .monthly ? returnsTo : date
        ordinal = (date - 1) / 7 + 1
        ordinalWeekday = weekday
        month = parts.month ?? 1
        yearDay = rule?.frequency == .yearly ? returnsTo : date
        switch rule?.place {
        case .day(let d)?: monthDay = d
        case .lastDay?: monthly = .lastDay
        case .weekday(let w, let o)?:
            monthly = .weekday
            ordinalWeekday = w
            ordinal = o
        case .date(let m, let d)?:
            month = m
            yearDay = d
        case nil: break
        }
        opened = rule
        openedShown = nil
        if rule != nil { openedShown = shown }
    }

    /// What the card shows now (`Shown`).
    public var shown: Shown {
        let n = min(max(interval, 1), RecurrenceRule.maxInterval)
        switch frequency {
        case .daily:
            return Shown(frequency: .daily, interval: n, weekdays: nil, place: nil)
        case .weekly:
            return Shown(frequency: .weekly, interval: n, weekdays: weekdays.isEmpty ? nil : weekdays, place: nil)
        case .monthly:
            let place: RecurrenceRule.Place
            switch monthly {
            case .day: place = .day(min(max(monthDay, 1), 31))
            case .lastDay: place = .lastDay
            case .weekday: place = .weekday(ordinalWeekday, ordinal: ordinal)
            }
            return Shown(frequency: .monthly, interval: n, weekdays: nil, place: place)
        case .yearly:
            let day = min(max(yearDay, 1), Self.days(inMonth: month))
            return Shown(frequency: .yearly, interval: n, weekdays: nil, place: .date(month: month, day: day))
        }
    }

    /// What Done sets: the rule it was opened on while the card still shows it, else `shownRule`.
    public var rule: RecurrenceRule {
        if let opened, shown == openedShown { return opened }
        return shownRule
    }

    /// The rule the card shows, built afresh: weekly on its days, monthly and yearly on their place.
    public var shownRule: RecurrenceRule {
        let s = shown
        return RecurrenceRule(frequency: s.frequency, interval: s.interval, weekdays: s.weekdays, place: s.place)
    }

    /// "day" / "days", "week" / "weeks": the word after the interval.
    public var unit: String {
        let one: String
        switch frequency {
        case .daily: one = "day"
        case .weekly: one = "week"
        case .monthly: one = "month"
        case .yearly: one = "year"
        }
        return interval == 1 ? one : one + "s"
    }

    /// Turns a weekly repeat's day on or off; the last day on stays on (false).
    @discardableResult
    public mutating func toggle(weekday: Int) -> Bool {
        guard (1...7).contains(weekday) else { return false }
        if weekdays.contains(weekday) {
            guard weekdays.count > 1 else { return false }
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }
        return true
    }

    /// A yearly repeat's month; its day is shortened to fit (Jan 31 → Feb 29).
    public mutating func setMonth(_ month: Int) {
        guard (1...12).contains(month) else { return }
        self.month = month
        yearDay = min(yearDay, Self.days(inMonth: month))
    }

    /// The most days a month can have (February: 29).
    public static func days(inMonth month: Int) -> Int {
        RecurrenceRule.Place.monthLengths[min(max(month, 1), 12) - 1]
    }

    /// The interval typed in its field: a whole number from 1 to `RecurrenceRule.maxInterval`, else nil.
    public static func interval(from text: String) -> Int? {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)), (1...RecurrenceRule.maxInterval).contains(n) else { return nil }
        return n
    }
}
