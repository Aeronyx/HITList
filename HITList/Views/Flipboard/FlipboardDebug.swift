#if DEBUG
import Foundation
import SwiftData
import HITListCore

/// Developer aid for screenshots and checks of the board's lights (2026-11-08): `-seedFlipboardStates` puts a switch of
/// every look on a side store's board the first time it opens: overdue (the breathing light), a charger counting, a
/// charger charged, a green switch, a long title and an overdue charger. Debug builds only, side stores only, once.
@MainActor
enum FlipboardDebug {
    /// `-flipboardNow 2026-11-11T03:30` (local time): the board's clock reads that moment, for screenshots either
    /// side of a Switchboard's reset (brief 72). Debug builds only; it changes what the board shows, not the store.
    nonisolated static let nowArgument = "-flipboardNow"

    nonisolated static var now: Date? { now(arguments: CommandLine.arguments) }

    nonisolated static func now(arguments: [String], timeZone: TimeZone = .current) -> Date? {
        guard let index = arguments.firstIndex(of: nowArgument), arguments.indices.contains(index + 1) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: arguments[index + 1])
    }

    static let argument = "-seedFlipboardStates"
    /// The first switch it makes; its presence means the board was seeded already.
    static let marker = "Clean the litter box"

    static func seedStatesIfRequested(in context: ModelContext, arguments: [String] = CommandLine.arguments,
                                      now: Date = Date()) {
        guard arguments.contains(argument), ModelContainerFactory.storeName != ModelContainerFactory.mainStoreName else { return }
        let existing = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        guard !existing.contains(where: { $0.title == marker }) else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        let states: [(title: String, rule: RecurrenceRule, target: Int, due: Date, count: Int, periodStart: Date?)] = [
            (marker, RecurrenceRule(frequency: .daily, interval: 2), 1, day(-2), 0, nil),
            ("Go to the gym", .weekly, 3, today, 1, today),
            ("Practice guitar", .weekly, 4, day(4), 4, day(-3)),
            ("Change the bed sheets", RecurrenceRule(frequency: .weekly, interval: 2), 1, day(10), 0, day(-4)),
            ("Descale the coffee machine and wash the filter basket", .monthly, 1, today, 0, nil),
            ("Run", .weekly, 2, day(-3), 0, nil),
        ]
        for state in states {
            guard let task = try? Flipboard.createSwitch(title: state.title, rule: state.rule, flipTarget: state.target,
                                                         in: context, now: now) else { continue }
            task.dueDate = state.due
            task.flipCount = state.count
            task.flipPeriodStart = state.periodStart
        }
        try? context.save()
    }
}
#endif
