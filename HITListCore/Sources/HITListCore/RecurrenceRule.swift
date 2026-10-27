import Foundation

/// A deliberately small recurrence model: every N days/weeks/months/years,
/// optionally restricted to specific weekdays (weekly only).
public struct RecurrenceRule: Codable, Equatable, Hashable, Sendable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency
    public var interval: Int
    /// Calendar weekdays (1 = Sunday ... 7 = Saturday). Only meaningful for `.weekly`.
    public var weekdays: Set<Int>?

    public init(frequency: Frequency, interval: Int = 1, weekdays: Set<Int>? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays?.isEmpty == true ? nil : weekdays
    }

    public static let daily = RecurrenceRule(frequency: .daily)
    public static let weekly = RecurrenceRule(frequency: .weekly)
    public static let monthly = RecurrenceRule(frequency: .monthly)
    public static let yearly = RecurrenceRule(frequency: .yearly)
    public static let weekdays = RecurrenceRule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])

    // MARK: Storage as a compact string ("weekly;2;2,4") so SwiftData/CloudKit can hold it.

    public var encoded: String {
        var s = "\(frequency.rawValue);\(interval)"
        if let weekdays { s += ";" + weekdays.sorted().map(String.init).joined(separator: ",") }
        return s
    }

    public init?(encoded: String) {
        let parts = encoded.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let freq = Frequency(rawValue: parts[0]), let interval = Int(parts[1]) else { return nil }
        var weekdays: Set<Int>? = nil
        if parts.count >= 3, !parts[2].isEmpty {
            weekdays = Set(parts[2].split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
        }
        self.init(frequency: freq, interval: interval, weekdays: weekdays)
    }

    // MARK: Occurrence math

    /// The first occurrence strictly after `date`, preserving the time of day of `date`.
    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date {
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date)!
        case .monthly:
            return calendar.date(byAdding: .month, value: interval, to: date)!
        case .yearly:
            return calendar.date(byAdding: .year, value: interval, to: date)!
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
