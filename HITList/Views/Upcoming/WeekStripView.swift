import SwiftUI

/// Seven day cells per page, swiped (or stepped with the arrows) a week at a time. Today is filled
/// with the accent, the day at the top of the list below gets a ring, and a dot marks days with tasks.
struct WeekStripView: View {
    let strip: WeekStrip
    let today: Date
    /// The day the list is showing at its top.
    let focusedDay: Date?
    /// Open tasks per day (start of day).
    let counts: [Date: Int]
    /// Pages are week offsets from the current week.
    let weeks: ClosedRange<Int>
    @Binding var visibleWeek: Int?
    /// The day a dragged task hovers over.
    @Binding var dropTarget: Date?
    /// Dropped task payloads on a day; false if the drop was refused.
    var onDrop: ([String], Date) -> Bool
    var onSelect: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The Duo's outer display: the strip and its band stop at the system's bar column.
    @Environment(\.listIslandPlacement) private var islandPlacement

    private var shownWeek: Int { visibleWeek ?? 0 }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text(strip.title(forWeekStarting: strip.week(shownWeek, from: today)))
                    .font(HITType.headline)
                    .contentTransition(.numericText())
                Spacer()
                // Each takes a press across the gaps beside it and down to the days (brief 94: 13 x 17 pt targets).
                Button { show(week: shownWeek - 1) } label: {
                    Image(systemName: "chevron.left").hitOutset(horizontal: 12, vertical: 6)
                }
                    .hitOutsetLayout(horizontal: 12, vertical: 6)
                    .disabled(shownWeek <= weeks.lowerBound)
                    .accessibilityLabel("Previous week")
                Button { show(week: 0); onSelect(today) } label: { Text("Today").hitOutset(vertical: 6) }
                    .hitOutsetLayout(vertical: 6)
                    .font(HITType.subheadlineMedium)
                Button { show(week: shownWeek + 1) } label: {
                    Image(systemName: "chevron.right").hitOutset(horizontal: 12, vertical: 6)
                }
                    .hitOutsetLayout(horizontal: 12, vertical: 6)
                    .disabled(shownWeek >= weeks.upperBound)
                    .accessibilityLabel("Next week")
            }
            .buttonStyle(.borderless)
            .listMarginPadding() // the rows' and the large title's edge (brief 99)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(weeks), id: \.self) { offset in
                        HStack(spacing: 0) {
                            ForEach(strip.days(ofWeekStarting: strip.week(offset, from: today)), id: \.self) { day in
                                dayCell(day)
                            }
                        }
                        .padding(.horizontal, 8)
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleWeek)
            // The iPhone shell gives every scroll view a bottom margin for the island; this strip is
            // horizontal and 64 pt tall, so that margin would push its days out of view.
            .contentMargins(.bottom, 0, for: .automatic)
            .frame(height: 64)
            // Beside the Duo's bar column the next week's first day ran under the battery ring (brief 106).
            .endsBeforeTheBarColumn()
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.surface, ignoresSafeAreaEdges: islandPlacement.stripBackgroundEdges)
    }

    private func show(week: Int) {
        let clamped = min(max(week, weeks.lowerBound), weeks.upperBound)
        withAnimation(reduceMotion ? nil : .snappy) { visibleWeek = clamped }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = day == today
        let isPast = day < today
        let isFocused = day == focusedDay
        let count = counts[day] ?? 0
        let isDropTarget = day == dropTarget
        return Button { onSelect(day) } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(HITType.caption2)
                    .foregroundStyle(isToday ? Theme.accent : Theme.secondaryText)
                Text(day.formatted(.dateTime.day()))
                    .font(isToday ? HITType.calloutBold : HITType.calloutMedium)
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Theme.background : .primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isToday ? Theme.accent : .clear))
                    .overlay(Circle().strokeBorder(Theme.accent, lineWidth: isFocused && !isToday ? 1.5 : 0))
                Circle()
                    .fill(count > 0 ? (isToday ? Theme.accent : Theme.secondaryText) : .clear)
                    .frame(width: 4, height: 4)
            }
            .opacity(isPast ? 0.45 : 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(isDropTarget ? 0.22 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: isDropTarget ? 1.5 : 0))
            .scaleEffect(isDropTarget && !reduceMotion ? 1.06 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            onDrop(items, day)
        } isTargeted: { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                if hovering, !isPast { dropTarget = day } else if dropTarget == day { dropTarget = nil }
            }
        }
        .accessibilityLabel(accessibilityLabel(day, count: count, isToday: isToday))
    }

    private func accessibilityLabel(_ day: Date, count: Int, isToday: Bool) -> String {
        var text = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if isToday { text += ", Today" }
        if count > 0 { text += ", \(count) \(count == 1 ? "task" : "tasks")" }
        return text
    }
}
