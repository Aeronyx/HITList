import SwiftUI
import HITListCore

/// A calendar event among the tasks (brief 77). Not a task: no checkbox, no priority, no swipe, no drag, no editor,
/// and a tap does nothing. As tall as a task row so the list keeps its rhythm: a 3 pt bar in the calendar's colour
/// where the checkbox would be, the title in the secondary text colour, and the time on the second line in the meta
/// style ("9:30 – 10:15 AM", "All day"). Today's past events dim.
///
/// Built from the task row's measurements (`TaskRowMetrics`, `ListMetrics`, `HITType`), never from `TaskRow` itself.
struct CalendarEventRow: View {
    let event: DayEvent
    let now: Date
    var calendar: Calendar = .current
    /// Beside the upright island (the Duo's outer display) a step larger, as the task rows are.
    @Environment(\.listIslandPlacement) private var islandPlacement

    /// The checkbox's column: the bar sits centred in it, so titles line up with the tasks' titles.
    static let markerWidth = TaskRowMetrics.checkSize + 2
    static let barWidth: CGFloat = 3
    /// Past events of today.
    static let pastOpacity = 0.5

    private var timeText: String { CalendarDay.timeText(event, calendar: calendar) }
    private var isPast: Bool { CalendarDay.isPast(event, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: ListMetrics.rowLineGap) {
            Text(event.event.title.isEmpty ? "Untitled event" : event.event.title)
                .font(HITType.taskTitle(for: islandPlacement))
                .tracking(HITType.taskTitleTracking)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minHeight: TaskRowMetrics.lineHeight, alignment: .leading)
            Text(timeText)
                .font(HITType.taskMeta(for: islandPlacement))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.leading, Self.markerWidth + TaskRowMetrics.checkGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            // From the title's first line to the time's last, in the checkbox's column.
            Capsule()
                .fill(Color(hex: event.event.colorHex))
                .frame(width: Self.barWidth)
                .padding(.vertical, 2)
                .frame(width: Self.markerWidth)
        }
        .opacity(isPast ? Self.pastOpacity : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.event.title), \(timeText)")
        .accessibilityHint("Calendar event")
        .accessibilityIdentifier("calendarEvent")
    }
}

extension View {
    /// A calendar event's place in a task list: a task row's insets and hairline, and nothing to select.
    func calendarEventListRow(compact: Bool) -> some View {
        self
            .listRowInsets(ListMetrics.rowInsets(compact: compact))
            .listRowSeparatorTint(Theme.separator)
            .selectionDisabled()
    }
}

/// The quiet header over Today's events.
struct CalendarEventsHeader: View {
    static let title = "Calendar"

    var body: some View {
        Text(Self.title)
            .taskSectionHeader(color: Theme.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

/// An event on the Upcoming board (Mac, iPad), at the top of its day's column: the row in a task card's frame
/// (`Theme.surface`, the card radius, a hairline), with no hover, since a click does nothing.
struct CalendarEventCard: View {
    let event: DayEvent
    let now: Date
    var calendar: Calendar = .current

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.card, style: .continuous)
        CalendarEventRow(event: event, now: now, calendar: calendar)
            .padding(.horizontal, HITSpacing.m)
            .padding(.vertical, HITSpacing.s + 2)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
    }
}
