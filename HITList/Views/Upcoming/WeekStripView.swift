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
    var onSelect: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shownWeek: Int { visibleWeek ?? 0 }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text(strip.title(forWeekStarting: strip.week(shownWeek, from: today)))
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()
                Button { show(week: shownWeek - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(shownWeek <= weeks.lowerBound)
                    .accessibilityLabel("Previous week")
                Button("Today") { show(week: 0); onSelect(today) }
                    .font(.subheadline.weight(.medium))
                Button { show(week: shownWeek + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(shownWeek >= weeks.upperBound)
                    .accessibilityLabel("Next week")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)

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
            .frame(height: 64)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.surface)
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
        return Button { onSelect(day) } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(isToday ? Theme.accent : Theme.secondaryText)
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.weight(isToday ? .bold : .medium))
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(day, count: count, isToday: isToday))
    }

    private func accessibilityLabel(_ day: Date, count: Int, isToday: Bool) -> String {
        var text = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if isToday { text += ", Today" }
        if count > 0 { text += ", \(count) \(count == 1 ? "task" : "tasks")" }
        return text
    }
}
