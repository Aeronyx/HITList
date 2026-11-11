import Foundation
import HITListCore

/// A believable few days for the widget gallery and the placeholder, before the app has written a snapshot of its own
/// (a fresh install). The same flavour as the app's demo week (`TaskActions.demoLines`).
enum WidgetSamples {
    static func snapshot(now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int? = nil, _ minute: Int = 0) -> Date {
            let start = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            guard let hour else { return start }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
        }
        func task(_ title: String, _ due: Date, time: Bool = false, priority: Int = 4, group: (String, String)? = nil,
                  repeats: Bool = false, labels: [String] = []) -> WidgetSnapshot.Task {
            WidgetSnapshot.Task(id: UUID(), title: title, priority: priority, due: due, hasTime: time,
                                groupName: group?.0, groupColorHex: group?.1, labelNames: labels, isRecurring: repeats,
                                createdAt: day(-7), isShared: false, switchOptedIn: false, switchboardID: nil, clock: nil)
        }
        let home = ("Home", "#E5484D"), work = ("Work", "#F76B15"), health = ("Health", "#12A594")
        let water = task("Water the plants", day(-1), repeats: true, labels: ["flipboard"])
        let recycling = task("Take out the recycling", day(3), repeats: true, labels: ["flipboard"])
        return WidgetSnapshot(
            writtenAt: now, themeID: "slate", weekStart: 2,
            tasks: [
                task("Reply to Sam about the lease", day(0), priority: 2, group: work),
                task("Gym", day(0, 7), time: true, group: health, repeats: true),
                task("Buy groceries", day(0, 18), time: true, group: home),
                task("Call the dentist", day(1, 9), time: true, priority: 2, group: home),
                task("Finish the quarterly report", day(3), priority: 1, group: work),
                task("Book flights for the trip", day(6)),
                water, recycling,
            ],
            looseSwitchIDs: [water.id, recycling.id],
            switchboards: [])
    }
}
