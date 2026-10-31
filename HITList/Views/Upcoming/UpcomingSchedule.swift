import Foundation
import HITListCore

/// Date math for the Upcoming week strip. Weeks start on Monday, the same as "next week" in quick add
/// and the filter language (`DateExpressionParser.weekStart`).
struct WeekStrip {
    var calendar: Calendar = .current
    /// Calendar weekday a week starts on (1 = Sunday, 2 = Monday).
    var weekStart: Int = 2

    private var parser: DateExpressionParser { DateExpressionParser(calendar: calendar, weekStart: weekStart) }

    func startOfWeek(containing date: Date) -> Date { parser.startOfWeek(containing: date) }

    /// The start of the week `offset` weeks after the one containing `date` (negative goes back).
    func week(_ offset: Int, from date: Date) -> Date {
        parser.day(7 * offset, from: startOfWeek(containing: date))
    }

    /// The seven days of a week, each at the start of its day.
    func days(ofWeekStarting start: Date) -> [Date] {
        (0..<7).map { parser.day($0, from: start) }
    }

    /// Whole weeks from the week containing `reference` to the week containing `date`.
    func weekOffset(of date: Date, from reference: Date) -> Int {
        let days = calendar.dateComponents([.day], from: startOfWeek(containing: reference), to: startOfWeek(containing: date)).day ?? 0
        return Int((Double(days) / 7).rounded(.down))
    }

    /// "October 2026", "Oct – Nov 2026", or "Dec 2026 – Jan 2027" for a week that spans a year.
    func title(forWeekStarting start: Date, locale: Locale = .current) -> String {
        let end = parser.day(6, from: start)
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        if calendar.component(.month, from: start) == calendar.component(.month, from: end), sameYear {
            return start.formatted(style.month(.wide).year())
        }
        if sameYear {
            return "\(start.formatted(style.month(.abbreviated))) – \(end.formatted(style.month(.abbreviated).year()))"
        }
        return "\(start.formatted(style.month(.abbreviated).year())) – \(end.formatted(style.month(.abbreviated).year()))"
    }
}

/// One day in the Upcoming list.
struct UpcomingDay<Item>: Identifiable {
    /// Start of the day.
    let date: Date
    var items: [Item]
    var id: Date { date }
}

/// Open dated tasks grouped the way the Upcoming view lists them: everything due before today in
/// `overdue`, then one entry per day from today for `dayCount` days, empty days included. Undated,
/// completed, and later tasks are left out. Each group is in `TaskOrdering` order, the same as Today:
/// priority first (P1 on top), then all-day before timed and timed in time order, then title.
struct UpcomingSchedule<Item: FilterableTask> {
    let overdue: [Item]
    let days: [UpcomingDay<Item>]

    init(items: [Item], now: Date, dayCount: Int, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        var overdue: [Item] = []
        var buckets: [Int: [Item]] = [:]
        for item in items where !item.filterIsCompleted {
            guard let due = item.filterDueDate else { continue }
            let day = calendar.startOfDay(for: due)
            if day < today {
                overdue.append(item)
                continue
            }
            let index = calendar.dateComponents([.day], from: today, to: day).day ?? 0
            if index < dayCount { buckets[index, default: []].append(item) }
        }
        self.overdue = TaskOrdering.sorted(overdue)
        self.days = (0..<max(dayCount, 0)).map { index in
            UpcomingDay(date: calendar.date(byAdding: .day, value: index, to: today)!,
                        items: TaskOrdering.sorted(buckets[index] ?? []))
        }
    }

    /// Open tasks per day (start of day), for the dots under the week strip. Not limited to the list's days.
    static func counts(of items: [Item], calendar: Calendar = .current) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for item in items where !item.filterIsCompleted {
            guard let due = item.filterDueDate else { continue }
            counts[calendar.startOfDay(for: due), default: 0] += 1
        }
        return counts
    }
}

enum UpcomingFormat {
    /// "Tue · Oct 28 · Today", "Wed · Oct 29 · Tomorrow", "Thu · Oct 30", "Fri · Jan 1, 2027".
    static func header(for day: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        var parts = [
            day.formatted(style.weekday(.abbreviated)),
            day.formatted(sameYear ? style.month(.abbreviated).day() : style.month(.abbreviated).day().year()),
        ]
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day ?? 0
        if offset == 0 { parts.append("Today") }
        if offset == 1 { parts.append("Tomorrow") }
        return parts.joined(separator: " · ")
    }
}
