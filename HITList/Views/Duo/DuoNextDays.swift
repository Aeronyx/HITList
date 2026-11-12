import SwiftUI
import SwiftData
import HITListCore

/// On the Duo's inner display, beside Today where it fits (`DuoColumns.plan`): Upcoming's next days,
/// tomorrow through a week out, each day under its header in the lists' one form ("Nov 12 · Tomorrow · Thursday",
/// brief 108; it was "Tomorrow", "Friday, Nov 13" in the system's header style beside Today's own). A tap opens the
/// task in the editor column; the circle completes it, as in Browse's search results.
struct DuoNextDays: View {
    @Environment(\.modelContext) private var context
    @Environment(PopoutController.self) private var popouts
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted && $0.dueDate != nil }, sort: \TaskItem.dueDate)
    private var dated: [TaskItem]
    @State private var now = Date()

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Tomorrow and the six days after it.
    static let dayCount = 7

    /// `items` grouped under the day each is due, for the `days` days after `now`'s, in order; days with
    /// nothing are left out. Generic so `DuoLayoutTests` can feed it plain values.
    static func group<Item>(_ items: [Item], due: (Item) -> Date?, now: Date, days: Int = dayCount,
                            calendar: Calendar = .current) -> [(day: Date, items: [Item])] {
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: 1, to: today),
              let end = calendar.date(byAdding: .day, value: days + 1, to: today) else { return [] }
        var byDay: [Date: [Item]] = [:]
        for item in items {
            guard let date = due(item), date >= first, date < end else { continue }
            byDay[calendar.startOfDay(for: date), default: []].append(item)
        }
        return byDay.keys.sorted().map { (day: $0, items: byDay[$0] ?? []) }
    }

    /// The tasks it lists: top-level ones, without green Flipboard switches (brief 59: those are on the
    /// Flipboard only; a red one is due today, so never in the next days anyway).
    static func listed<Item: FilterableTask>(_ items: [Item], now: Date, calendar: Calendar = .current) -> [Item] {
        items.filter { !$0.filterIsSubtask && FlipboardSwitch.listing(for: $0, now: now, calendar: calendar) != .hidden }
    }

    var body: some View {
        let open = Self.listed(dated, now: now)
        let days = Self.group(open, due: \.dueDate, now: now)
        VStack(alignment: .leading, spacing: 0) {
            Text("Next days")
                .font(HITType.title3)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, HITSpacing.l)
                .padding(.top, HITSpacing.m)
                .padding(.bottom, HITSpacing.xs)
            if days.isEmpty {
                Text("Nothing in the next week")
                    .font(HITType.body)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, HITSpacing.l)
                    .padding(.top, HITSpacing.s)
                Spacer(minLength: 0)
            } else {
                List(selection: popouts.selection) {
                    ForEach(days, id: \.day) { day in
                        Section {
                            ForEach(day.items) { task in
                                TaskRow(task: task, now: now, hidesDay: true) { complete(task) }
                                    .tag(task)
                                    // Flat on the background, as Today's rows beside it (brief 108: they were cards).
                                    .completionRowBackground(flashing: false)
                            }
                        } header: {
                            // The lists' one day form and header style (brief 99), as Today beside it writes its own day.
                            DayHeadingLine(full: DueFormatter.dayHeading(for: day.day, now: now),
                                           short: DueFormatter.dayHeading(for: day.day, now: now, shortWeekday: true))
                                .taskSectionHeader(color: DueFormatter.sectionColor(for: day.day, now: now))
                        }
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListHeaderHeight, 0)
                .slateList()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .onReceive(clock) { now = $0 }
        .onReceive(CalendarChange.moments) { now = $0 } // brief 82's follow-up: a new zone or day shows at once, not at the next minute
    }

    private func complete(_ task: TaskItem) {
        let wasCompleted = task.isCompleted
        withAnimation(HITMotion.standard) { TaskActions.toggleCompletion(task, in: context) }
        if !wasCompleted { CompletionFeedback.shared.taskCompleted() }
        Task { await NotificationScheduler.reschedule(context: context) }
    }
}
