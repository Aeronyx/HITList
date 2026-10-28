import SwiftUI
import HITListCore

/// Moving tasks between days: what a dragged row carries, and the quick dates the row menu offers.
enum TaskRescheduling {
    /// A dragged row carries its task's id as a plain string, so a drop elsewhere just pastes the id.
    static func dragPayload(for id: UUID) -> String { id.uuidString }

    /// The task ids in a drop, ignoring anything that isn't one.
    static func taskIDs(in payload: [String]) -> [UUID] {
        payload.compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// The day `offset` days from the task's due day, or from today for an undated task (⌘← / ⌘→).
    static func day(_ offset: Int, from due: Date?, now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: due ?? now))!
    }

    enum QuickDate: CaseIterable {
        case today, tomorrow, nextWeek

        var title: String {
            switch self {
            case .today: "Today"
            case .tomorrow: "Tomorrow"
            case .nextWeek: "Next Week"
            }
        }

        var symbol: String {
            switch self {
            case .today: "star"
            case .tomorrow: "sunrise"
            case .nextWeek: "arrow.right.circle"
            }
        }

        /// Next week is the Monday after this week, as in quick add's "next week".
        func date(now: Date, calendar: Calendar = .current) -> Date {
            let parser = DateExpressionParser(calendar: calendar, now: now)
            switch self {
            case .today: return parser.today
            case .tomorrow: return parser.day(1)
            case .nextWeek: return parser.day(7, from: parser.startOfWeek(containing: now))
            }
        }
    }
}

/// A graphical month picker that applies the date as soon as one is tapped.
struct PickDatePopover: View {
    let initial: Date
    var onPick: (Date) -> Void
    var onRemove: (() -> Void)?

    @State private var date: Date

    init(initial: Date, onPick: @escaping (Date) -> Void, onRemove: (() -> Void)? = nil) {
        self.initial = initial
        self.onPick = onPick
        self.onRemove = onRemove
        _date = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("Due date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .onChange(of: date) { _, picked in onPick(picked) }
            if let onRemove {
                Button("Remove Date", systemImage: "calendar.badge.minus", role: .destructive, action: onRemove)
                    .buttonStyle(.borderless)
            }
        }
        .padding()
        .frame(minWidth: 300)
        .background(Theme.elevated)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .presentationCompactAdaptation(.popover)
    }
}
