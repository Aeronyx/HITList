import Foundation

/// Upcoming's day rules (brief 74), pure so the app's Upcoming and the Upcoming widget judge a task the same way: an
/// open top-level task that isn't a Flipboard switch is scheduled on its due day; a switch is on the Flipboard only
/// (a green one is done for now, a red one is Today's when it opted in). The app's `UpcomingSchedule.isScheduled` and
/// `counts` (Views/Upcoming/UpcomingSchedule.swift) say the same today and can call these.
public enum UpcomingDays {
    /// An open top-level task that isn't a switch.
    public static func isScheduled<T: FilterableTask>(_ task: T, now: Date, calendar: Calendar = .current) -> Bool {
        !task.filterIsCompleted && !task.filterIsSubtask
            && FlipboardSwitch.listing(for: task, now: now, calendar: calendar) == .unchanged
    }

    /// Scheduled tasks per day (each a start of day), for the dots under a week or a month: every dated one, the days
    /// before today too.
    public static func counts<T: FilterableTask>(_ tasks: [T], now: Date, calendar: Calendar = .current) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for task in tasks where isScheduled(task, now: now, calendar: calendar) {
            guard let due = task.filterDueDate else { continue }
            counts[calendar.startOfDay(for: due), default: 0] += 1
        }
        return counts
    }

    /// The scheduled tasks of `dayCount` days from today, by day (each a start of day), in Today's order
    /// (`TaskOrdering.sorted`); days without tasks are left out.
    public static func days<T: FilterableTask>(_ tasks: [T], now: Date, dayCount: Int,
                                               calendar: Calendar = .current) -> [(date: Date, tasks: [T])] {
        let today = calendar.startOfDay(for: now)
        var buckets: [Int: [T]] = [:]
        for task in tasks where isScheduled(task, now: now, calendar: calendar) {
            guard let due = task.filterDueDate else { continue }
            let index = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day ?? -1
            if (0..<dayCount).contains(index) { buckets[index, default: []].append(task) }
        }
        return buckets.keys.sorted().map { index in
            (calendar.date(byAdding: .day, value: index, to: today).map { calendar.startOfDay(for: $0) } ?? today,
             TaskOrdering.sorted(buckets[index] ?? [], now: now, calendar: calendar))
        }
    }
}
