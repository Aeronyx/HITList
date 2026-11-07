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
/// `overdue`, then one entry per day from `start` (today unless given; never before today) for
/// `dayCount` days, empty days included. Undated, completed, sub-tasks and tasks outside the days are
/// left out, and so are Flipboard switches (brief 59): a green one is on the Flipboard only and a red one
/// is Today's, every day, not a dated task. Each group is in `TaskOrdering` order, the same as Today:
/// priority first (P1 on top), then all-day before timed and timed in time order, then title.
struct UpcomingSchedule<Item: FilterableTask> {
    let overdue: [Item]
    let days: [UpcomingDay<Item>]

    init(items: [Item], now: Date, start: Date? = nil, dayCount: Int, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let first = max(today, calendar.startOfDay(for: start ?? today))
        var overdue: [Item] = []
        var buckets: [Int: [Item]] = [:]
        for item in items where Self.isScheduled(item, now: now, calendar: calendar) {
            guard let due = item.filterDueDate else { continue }
            let day = calendar.startOfDay(for: due)
            if day < today {
                overdue.append(item)
                continue
            }
            let index = calendar.dateComponents([.day], from: first, to: day).day ?? 0
            if day >= first, index < dayCount { buckets[index, default: []].append(item) }
        }
        self.overdue = TaskOrdering.sorted(overdue)
        self.days = (0..<max(dayCount, 0)).map { index in
            UpcomingDay(date: calendar.date(byAdding: .day, value: index, to: first)!,
                        items: TaskOrdering.sorted(buckets[index] ?? []))
        }
    }

    /// An open top-level task that isn't a Flipboard switch.
    static func isScheduled(_ item: Item, now: Date, calendar: Calendar = .current) -> Bool {
        !item.filterIsCompleted && !item.filterIsSubtask
            && FlipboardSwitch.listing(for: item, now: now, calendar: calendar) == .unchanged
    }

    /// Open tasks per day (start of day), for the dots under the week strip. Not limited to the list's days.
    static func counts(of items: [Item], now: Date = Date(), calendar: Calendar = .current) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for item in items where isScheduled(item, now: now, calendar: calendar) {
            guard let due = item.filterDueDate else { continue }
            counts[calendar.startOfDay(for: due), default: 0] += 1
        }
        return counts
    }
}

// MARK: - Board (Mac, and iPad full width)

/// Which seven days the board shows: `offset` days after today onward. Counting from today (rather
/// than holding a date) keeps the window on today across midnight. It never goes before today; the days
/// before are the Overdue column.
struct UpcomingWindow: Equatable {
    static let dayCount = 7

    private(set) var offset: Int

    init(offset: Int = 0) { self.offset = max(0, offset) }

    var isAtToday: Bool { offset == 0 }

    /// ‹ and › move by one day.
    mutating func move(by days: Int) { offset = max(0, offset + days) }

    mutating func goToToday() { offset = 0 }

    /// The window starting on `day` (today for a day already past).
    mutating func jump(to day: Date, now: Date, calendar: Calendar = .current) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day ?? 0
        offset = max(0, days)
    }

    /// The first day shown, at the start of the day.
    func start(now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    func days(now: Date, calendar: Calendar = .current) -> [Date] {
        let start = start(now: now, calendar: calendar)
        return (0..<Self.dayCount).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    /// The header's month: "November 2026", "November – December 2026" when the seven days cross a month
    /// end, "December 2026 – January 2027" across a year.
    func title(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = days(now: now, calendar: calendar)
        let first = days[0], last = days[days.count - 1]
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let sameYear = calendar.component(.year, from: first) == calendar.component(.year, from: last)
        if sameYear, calendar.component(.month, from: first) == calendar.component(.month, from: last) {
            return first.formatted(style.month(.wide).year())
        }
        if sameYear {
            return "\(first.formatted(style.month(.wide))) – \(last.formatted(style.month(.wide).year()))"
        }
        return "\(first.formatted(style.month(.wide).year())) – \(last.formatted(style.month(.wide).year()))"
    }
}

/// The board's columns: Overdue first when it is shown and has tasks, then the window's seven days. Tasks
/// are grouped and ordered exactly as the Upcoming list does (`UpcomingSchedule`).
struct UpcomingBoardModel<Item: FilterableTask> {
    enum ColumnID: Hashable {
        case overdue
        case day(Date)
    }

    struct Column: Identifiable {
        let id: ColumnID
        let items: [Item]

        var count: Int { items.count }

        /// The column's day (start of day); nil for Overdue.
        var day: Date? {
            if case .day(let day) = id { return day }
            return nil
        }

        /// Cards dropped here move to this day; Overdue takes none.
        var acceptsDrops: Bool { day != nil }

        /// What its "+ Add task" opens the quick add with; Overdue has no add row.
        var addContext: QuickAddContext? { day.map { .day($0) } }
    }

    let columns: [Column]

    init(items: [Item], window: UpcomingWindow, now: Date, showOverdue: Bool, calendar: Calendar = .current) {
        let schedule = UpcomingSchedule(items: items, now: now, start: window.start(now: now, calendar: calendar),
                                        dayCount: UpcomingWindow.dayCount, calendar: calendar)
        var columns = schedule.days.map { Column(id: .day($0.date), items: $0.items) }
        if showOverdue, !schedule.overdue.isEmpty {
            columns.insert(Column(id: .overdue, items: schedule.overdue), at: 0)
        }
        self.columns = columns
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

    /// The board's column header: "Nov 4 · Today · Wednesday", "Nov 5 · Tomorrow · Thursday",
    /// "Nov 6 · Friday", "Jan 1, 2027 · Friday".
    static func boardHeader(for day: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        var parts = [day.formatted(sameYear ? style.month(.abbreviated).day() : style.month(.abbreviated).day().year())]
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day ?? 0
        if offset == 0 { parts.append("Today") }
        if offset == 1 { parts.append("Tomorrow") }
        parts.append(day.formatted(style.weekday(.wide)))
        return parts.joined(separator: " · ")
    }
}
