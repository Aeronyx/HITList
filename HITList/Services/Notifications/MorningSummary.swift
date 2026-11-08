import Foundation
import HITListCore

/// The morning summary and the app icon badge: both count the Today screen's tasks (overdue + due
/// today, `TaskOrdering.todaySection`), timed or not, as Today shows them (brief 64): shared tasks among yours, and a
/// red Flipboard switch as one of today's, never overdue.
extension NotificationPlan {
    static let morningSummaryIdentifier = "HITList.morningSummary"
    static let morningSummaryTitle = "Today in HITList"

    /// The next morning summary: one request at `minutes` after midnight (today if that is still ahead,
    /// otherwise tomorrow), its text computed now for that day: "5 tasks today, 2 overdue · first:
    /// Haircut 11:00". Nil when that day has nothing due and nothing overdue.
    ///
    /// `tasks` should include every open dated task, timed or not; the scheduler recomputes it on every
    /// reschedule (edits, imports, the day changing), so the text is as fresh as the last one.
    static func summaryRequest(tasks: [Item], at minutes: Int, now: Date, calendar: Calendar = .current,
                               locale: Locale = .current) -> Request? {
        let minutes = min(max(0, minutes), 24 * 60 - 1)
        let todayFire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now)!
        let fire = todayFire > now ? todayFire : calendar.date(byAdding: .day, value: 1, to: todayFire)!
        var overdue = 0
        var today: [Item] = []
        for item in tasks where !item.isCompleted {
            switch item.todaySection(now: fire, calendar: calendar) {
            case .overdue?: overdue += 1
            case .today?: today.append(item)
            case nil: break
            }
        }
        guard overdue + today.count > 0 else { return nil }

        var counts: [String] = []
        if !today.isEmpty { counts.append("\(today.count) \(today.count == 1 ? "task" : "tasks") today") }
        if overdue > 0 { counts.append("\(overdue) overdue") }
        var body = counts.joined(separator: ", ")
        let first = today
            .filter { $0.hasDueTime && ($0.dueDate ?? .distantPast) >= fire }
            .min { a, b in a.dueDate! != b.dueDate! ? a.dueDate! < b.dueDate! : a.priority.rawValue < b.priority.rawValue }
        if let first, let due = first.dueDate {
            let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                        timeZone: calendar.timeZone)
            body += " · first: \(first.title) \(due.formatted(time))"
        }
        let zone = calendar.timeZone.identifier
        return Request(identifier: morningSummaryIdentifier, kind: .morningSummary, taskID: nil,
                       title: morningSummaryTitle, body: body, triggerDate: fire, dueDate: nil,
                       fingerprint: fingerprint([morningSummaryTitle, body, String(Int(fire.timeIntervalSince1970)), zone]))
    }

    /// The app icon badge: open tasks that are overdue or due today, a red switch once.
    static func badgeCount(tasks: [Item], now: Date, calendar: Calendar = .current) -> Int {
        tasks.filter { !$0.isCompleted && $0.todaySection(now: now, calendar: calendar) != nil }.count
    }

    /// What the badge and the summary count: your dated tasks and your switches (dated or not), and the open shared
    /// tasks with a date (brief 64).
    static func todayItems(own: [Item], shared: [SharedRow]) -> [Item] {
        own.filter { $0.dueDate != nil || $0.isSwitch }
            + shared.filter { !$0.filterIsCompleted && $0.filterDueDate != nil }.map(Item.init)
    }
}

extension NotificationPlan.Item {
    /// A shared task as the badge and the morning summary count it (brief 64). It never reminds: no offset, no moment.
    init(_ row: SharedRow) {
        self.init(id: row.id, title: row.filterTitle, projectName: SharedTasksGroup.name,
                  priority: Priority(clamping: row.filterPriority), dueDate: row.filterDueDate, hasDueTime: row.filterHasDueTime,
                  isCompleted: row.filterIsCompleted, updatedAt: row.task.createdAt)
    }

    /// The Today section it is listed in at `now`: a red switch is today's, a green one in neither (`FlipboardSwitch`),
    /// anything else by its date.
    func todaySection(now: Date, calendar: Calendar = .current) -> TaskOrdering.TodaySection? {
        if isSwitch { return FlipboardSwitch.side(due: dueDate, now: now, calendar: calendar) == .red ? .today : nil }
        return TaskOrdering.todaySection(for: dueDate, now: now, calendar: calendar)
    }
}
