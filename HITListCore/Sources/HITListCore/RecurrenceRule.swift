import Foundation

/// A deliberately small recurrence model: every N days/weeks/months/years,
/// optionally restricted to specific weekdays (weekly only).
///
/// Monthly and yearly rules may carry an anchor day: the day of the month the task started on, so "every
/// month" from Jan 31 goes Feb 28, Mar 31, Apr 30 instead of drifting to the 28th, and "every year" from
/// Feb 29 comes back to Feb 29 in the next leap year (George, 2026-11-02). Equality ignores the anchor:
/// it only says where a shortened month's date returns to and follows the task's due date.
public struct RecurrenceRule: Codable, Hashable, Sendable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency
    public var interval: Int
    /// Calendar weekdays (1 = Sunday ... 7 = Saturday). Only meaningful for `.weekly`.
    public var weekdays: Set<Int>?
    /// The day of the month (1...31) a monthly or yearly repeat keeps returning to; nil for daily and
    /// weekly rules, and for rules written before 0.4.0 (they behave as they always did until a
    /// completion anchors them: see `anchored(to:calendar:)`).
    public var anchorDay: Int?

    public init(frequency: Frequency, interval: Int = 1, weekdays: Set<Int>? = nil, anchorDay: Int? = nil) {
        self.frequency = frequency
        self.interval = min(max(1, interval), Self.maxInterval)
        self.weekdays = weekdays?.isEmpty == true ? nil : weekdays
        self.anchorDay = Self.usesAnchor(frequency) ? anchorDay.flatMap { (1...31).contains($0) ? $0 : nil } : nil
    }

    private static func usesAnchor(_ frequency: Frequency) -> Bool { frequency == .monthly || frequency == .yearly }

    public static func == (a: RecurrenceRule, b: RecurrenceRule) -> Bool {
        a.frequency == b.frequency && a.interval == b.interval && a.weekdays == b.weekdays
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(frequency)
        hasher.combine(interval)
        hasher.combine(weekdays)
    }

    /// The longest interval a rule holds: the date arithmetic (7 × interval for weeks, the weekday walk)
    /// trapped on absurd values typed into quick add or arriving from another device.
    public static let maxInterval = 999

    public static let daily = RecurrenceRule(frequency: .daily)
    public static let weekly = RecurrenceRule(frequency: .weekly)
    public static let monthly = RecurrenceRule(frequency: .monthly)
    public static let yearly = RecurrenceRule(frequency: .yearly)
    public static let weekdays = RecurrenceRule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])

    // MARK: Storage as a compact string ("weekly;2;2,4") so SwiftData/CloudKit can hold it.
    //
    // A fourth part holds the anchor day: "monthly;1;;31". Builds before 0.4.0 read only the first three
    // parts and see an empty weekday list, so to them it is plain "every month" (no schema change).

    public var encoded: String {
        var s = "\(frequency.rawValue);\(interval)"
        if let weekdays { s += ";" + weekdays.sorted().map(String.init).joined(separator: ",") }
        if let anchorDay { s += (weekdays == nil ? ";;" : ";") + String(anchorDay) }
        return s
    }

    public init?(encoded: String) {
        let parts = encoded.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let freq = Frequency(rawValue: parts[0]), let interval = Int(parts[1]) else { return nil }
        var weekdays: Set<Int>? = nil
        if parts.count >= 3, !parts[2].isEmpty {
            weekdays = Set(parts[2].split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
        }
        let anchorDay = parts.count >= 4 ? Int(parts[3]) : nil
        self.init(frequency: freq, interval: interval, weekdays: weekdays, anchorDay: anchorDay)
    }

    // MARK: Anchor day

    /// The day of the month a monthly or yearly step from `date` aims for: the anchor while `date` is on
    /// it (or on a shorter month's last day short of it), otherwise `date`'s own day. A task moved from
    /// the 31st to the 15th therefore repeats on the 15th; a rule without an anchor clamps and drifts as
    /// it always did.
    func targetDay(from date: Date, calendar: Calendar) -> Int {
        let day = calendar.component(.day, from: date)
        guard let anchorDay else { return day }
        if day == anchorDay { return anchorDay }
        let monthLength = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        return day == monthLength && anchorDay > day ? anchorDay : day
    }

    /// This rule anchored to a task due at `due`: monthly and yearly rules take the day it keeps returning
    /// to (an existing anchor `due` still matches is kept); daily and weekly rules are returned as they are.
    public func anchored(to due: Date, calendar: Calendar = .current) -> RecurrenceRule {
        guard Self.usesAnchor(frequency) else { return self }
        var rule = self
        rule.anchorDay = targetDay(from: due, calendar: calendar)
        return rule
    }

    /// This rule picked from the Repeat menu for a task whose repeat was `previous` and which is due at
    /// `due`. Menu rules carry no anchor and compare equal to anchored ones, so picking "Every month" again
    /// on a "31st" task due Feb 28 must not forget the 31st: a monthly or yearly rule keeps the day
    /// `previous` returned to (same frequency) while `due` still matches it, and otherwise takes `due`'s
    /// day, as a completion would. A rule that already has an anchor, or has no use for one, is returned
    /// as it is; so is any rule for an undated task.
    public func keepingAnchor(of previous: RecurrenceRule?, due: Date?, calendar: Calendar = .current) -> RecurrenceRule {
        guard Self.usesAnchor(frequency), anchorDay == nil, let due else { return self }
        var rule = self
        if let previous, previous.frequency == frequency { rule.anchorDay = previous.anchorDay }
        return rule.anchored(to: due, calendar: calendar)
    }

    // MARK: Occurrence math

    /// The first occurrence strictly after `date`, preserving the time of day of `date`.
    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date)!
        case .monthly, .yearly:
            // Calendar clamps to the end of a shorter month (Jan 31 + 1 month = Feb 28); then move to the
            // target day, or as close to it as the new month allows. Adding days keeps the time of day.
            let stepped = calendar.date(byAdding: frequency == .monthly ? .month : .year, value: interval, to: date)!
            let monthLength = calendar.range(of: .day, in: .month, for: stepped)?.count ?? 28
            let day = min(targetDay(from: date, calendar: calendar), monthLength)
            let shift = day - calendar.component(.day, from: stepped)
            return shift == 0 ? stepped : calendar.date(byAdding: .day, value: shift, to: stepped)!
        case .weekly:
            guard let weekdays, !weekdays.isEmpty else {
                return calendar.date(byAdding: .day, value: 7 * interval, to: date)!
            }
            // Walk forward day by day; honor `interval` by only accepting weeks that are a
            // multiple of `interval` away from the anchor week.
            let anchorWeek = startOfWeek(date, calendar: calendar)
            var candidate = date
            for _ in 0..<(7 * interval + 7) {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
                let wd = calendar.component(.weekday, from: candidate)
                guard weekdays.contains(wd) else { continue }
                let week = startOfWeek(candidate, calendar: calendar)
                let weeksApart = calendar.dateComponents([.weekOfYear], from: anchorWeek, to: week).weekOfYear ?? 0
                if weeksApart % interval == 0 { return candidate }
            }
            return calendar.date(byAdding: .day, value: 7 * interval, to: date)!
        }
    }

    /// The due date to assign when a task due at `due` is completed at `now`:
    /// the next occurrence after `due` that is not already in the past (by day).
    public func nextDueDate(from due: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        var next = nextOccurrence(after: due, calendar: calendar)
        var guardCount = 0
        while calendar.startOfDay(for: next) < today && guardCount < 1000 {
            next = nextOccurrence(after: next, calendar: calendar)
            guardCount += 1
        }
        return next
    }

    /// The first occurrence on or after `date` (used to pick a start date for "every monday").
    public func firstOccurrence(onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        guard frequency == .weekly, let weekdays, !weekdays.isEmpty else { return date }
        let wd = calendar.component(.weekday, from: date)
        if weekdays.contains(wd) { return date }
        return nextOccurrence(after: date, calendar: calendar)
    }

    private func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        let d = calendar.startOfDay(for: date)
        let wd = calendar.component(.weekday, from: d)
        let diff = (wd - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -diff, to: d)!
    }

    // MARK: Display

    public var displayText: String {
        let shortDays = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
        switch frequency {
        case .daily: return interval == 1 ? "Every day" : "Every \(interval) days"
        case .monthly: return interval == 1 ? "Every month" : "Every \(interval) months"
        case .yearly: return interval == 1 ? "Every year" : "Every \(interval) years"
        case .weekly:
            if let weekdays, !weekdays.isEmpty {
                if weekdays == [2, 3, 4, 5, 6] { return interval == 1 ? "Every weekday" : "Every \(interval) weeks on weekdays" }
                let names = weekdays.sorted().compactMap { shortDays[$0] }.joined(separator: ", ")
                return interval == 1 ? "Every \(names)" : "Every \(interval) weeks on \(names)"
            }
            return interval == 1 ? "Every week" : "Every \(interval) weeks"
        }
    }
}
