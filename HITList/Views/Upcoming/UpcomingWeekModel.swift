import Foundation
import HITListCore

/// Upcoming's two layouts (brief 161): today's (the list on iPhone, the board on the Mac and a wide iPad) and Week, the
/// week's tasks on a calendar. Kept per device in `AppGroup.defaults` under `key`; the default is today's layout, so
/// nobody's Upcoming changes until they choose.
enum UpcomingLayout: String, CaseIterable, Identifiable {
    case tasks
    case week

    static let key = "upcomingLayout"
    static let defaultValue = UpcomingLayout.tasks

    var id: String { rawValue }

    /// The menu's name for it: today's layout is named for what it shows on this device.
    func title(showsBoard: Bool) -> String {
        switch self {
        case .tasks: showsBoard ? "Board" : "List"
        case .week: "Week"
        }
    }

    func symbol(showsBoard: Bool) -> String {
        switch self {
        case .tasks: showsBoard ? "rectangle.split.3x1" : "list.bullet"
        case .week: "calendar.day.timeline.left"
        }
    }
}

/// A timed task on the Week layout's grid: its minute of the day, and its column among those that overlap it.
struct UpcomingWeekTimed<Item> {
    let item: Item
    /// Minutes from the start of its day.
    let minute: Int
    /// Its column among the tasks it overlaps (0 first), and how many columns they share.
    let column: Int
    let columns: Int
}

/// One day on the Week layout: exactly the tasks Upcoming's list shows on that day (`UpcomingSchedule`), in the list's
/// order, split into the all-day band (a date and no time) and the grid (a time).
struct UpcomingWeekDay<Item> {
    let date: Date
    /// The list's items for the day, in its order.
    let items: [Item]
    let allDay: [Item]
    let timed: [UpcomingWeekTimed<Item>]
}

/// The Week layout's arrangement, pure so a test can check it: the shown days, each with what the list shows on it, and
/// the overdue tasks (the list's Overdue section). Days before today show nothing, as the list does: what was due then
/// is overdue. A timed task takes `slotMinutes` of the grid (the chip's least height; tasks have no durations), and
/// tasks whose slots overlap share the column's width.
struct UpcomingWeekModel<Item: FilterableTask> {
    static var slotMinutes: Int { 30 }

    let days: [UpcomingWeekDay<Item>]
    let overdue: [Item]

    init(items: [Item], days shown: [Date], now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let starts = shown.map { calendar.startOfDay(for: $0) }
        let first = max(today, starts.min() ?? today)
        let last = starts.max() ?? today
        let count = last < first ? 0 : (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        let schedule = UpcomingSchedule(items: items, now: now, start: first, dayCount: count, calendar: calendar)
        var byDay: [Date: [Item]] = [:]
        for day in schedule.days { byDay[day.date] = day.items }
        overdue = schedule.overdue
        days = starts.map { date in
            let items = byDay[date] ?? []
            return UpcomingWeekDay(date: date, items: items,
                                   allDay: items.filter { !$0.filterHasDueTime },
                                   timed: Self.arrange(items.filter(\.filterHasDueTime), calendar: calendar))
        }
    }

    /// Timed items in time order, each in the first column free at its minute; items whose slots chain into each other
    /// make one group, and every item in a group shares the group's number of columns.
    static func arrange(_ items: [Item], calendar: Calendar = .current) -> [UpcomingWeekTimed<Item>] {
        let placed = items.enumerated().compactMap { index, item -> (Int, Int, Item)? in
            guard let due = item.filterDueDate else { return nil }
            let parts = calendar.dateComponents([.hour, .minute], from: due)
            return ((parts.hour ?? 0) * 60 + (parts.minute ?? 0), index, item)
        }
        .sorted { ($0.0, $0.1) < ($1.0, $1.1) }

        var result: [UpcomingWeekTimed<Item>] = []
        var group: [(minute: Int, column: Int, item: Item)] = []
        var columnEnds: [Int] = []
        var groupEnd = Int.min
        func close() {
            let columns = max(columnEnds.count, 1)
            result += group.map { UpcomingWeekTimed(item: $0.item, minute: $0.minute, column: $0.column, columns: columns) }
            group = []
            columnEnds = []
        }
        for (minute, _, item) in placed {
            if minute >= groupEnd, !group.isEmpty { close() }
            let end = minute + slotMinutes
            if let free = columnEnds.firstIndex(where: { $0 <= minute }) {
                columnEnds[free] = end
                group.append((minute, free, item))
            } else {
                columnEnds.append(end)
                group.append((minute, columnEnds.count - 1, item))
            }
            groupEnd = max(groupEnd == Int.min ? end : groupEnd, end)
        }
        if !group.isEmpty { close() }
        return result
    }
}

/// Which days the Week layout shows: `count` days from `first` (three on an iPhone, the seven of a week elsewhere).
/// Never before the current week's first day.
struct UpcomingWeekWindow: Equatable {
    /// Days from the start of today's week to the first day shown.
    private(set) var offset: Int

    init(offset: Int = 0) { self.offset = max(0, offset) }

    static func startingToday(strip: WeekStrip, now: Date) -> UpcomingWeekWindow {
        let today = strip.calendar.startOfDay(for: now)
        let start = strip.startOfWeek(containing: today)
        return UpcomingWeekWindow(offset: strip.calendar.dateComponents([.day], from: start, to: today).day ?? 0)
    }

    mutating func move(by days: Int) { offset = max(0, offset + days) }

    /// Whether there are earlier days to show `count` at a time. A whole week (`count` 7) opened on a Thursday has
    /// an offset of four and shows this week: a step back would change the offset and not one day on the screen, so
    /// "Previous week" was a live button that did nothing until it had been pressed once (round 35). Three days at
    /// a time can step back to the week's first day.
    func canMoveBack(count: Int) -> Bool { count == 7 ? offset >= 7 : offset > 0 }

    /// The shown days: `count` from the first; for a whole week (`count` 7) the first is always a week's first day.
    func days(count: Int, strip: WeekStrip, now: Date) -> [Date] {
        let base = strip.startOfWeek(containing: now)
        let shift = count == 7 ? (offset / 7) * 7 : offset
        return (0..<count).map { strip.calendar.date(byAdding: .day, value: shift + $0, to: base)! }
    }

    /// Whether today is among `count` shown days.
    func showsToday(count: Int, strip: WeekStrip, now: Date) -> Bool {
        let today = strip.calendar.startOfDay(for: now)
        return days(count: count, strip: strip, now: now).contains(today)
    }

    /// "November 2026", "Nov – Dec 2026", "Dec 2026 – Jan 2027": the month and year of the shown days.
    static func title(of days: [Date], calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let sameYear = calendar.component(.year, from: first) == calendar.component(.year, from: last)
        if sameYear, calendar.component(.month, from: first) == calendar.component(.month, from: last) {
            return first.formatted(style.month(.wide).year())
        }
        if sameYear {
            return "\(first.formatted(style.month(.abbreviated))) – \(last.formatted(style.month(.abbreviated).year()))"
        }
        return "\(first.formatted(style.month(.abbreviated).year())) – \(last.formatted(style.month(.abbreviated).year()))"
    }

    /// The week's place in its year ("Week 47"), by the calendar's own week numbering with the app's first weekday.
    static func weekNumber(of day: Date, strip: WeekStrip) -> Int {
        var calendar = strip.calendar
        calendar.firstWeekday = strip.weekStart
        return calendar.component(.weekOfYear, from: day)
    }
}
