import SwiftUI
import WidgetKit
import HITListCore

/// The Upcoming widget (brief 74): a little calendar and the next tasks. Medium: this week as a strip (from the week
/// start in Settings) with a dot under each day that has tasks and today marked as `HITCalendar` marks it (ringed in the
/// accent), then the next tasks under their day. Large: the month as `HITCalendar`'s grid with the same dots, then the
/// next tasks. A row opens its task; the rest opens Upcoming.
struct UpcomingWidgetView: View {
    let snapshot: WidgetSnapshot?
    let now: Date
    let family: WidgetFamily
    @Environment(\.widgetPalette) private var palette
    @Environment(\.widgetOffscreen) private var offscreen

    private var content: WidgetContent.Upcoming? { snapshot.map { WidgetContent.upcoming($0, at: now) } }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 6) {
            header
            if let content {
                if family == .systemLarge {
                    UpcomingMonthGrid(content: content, now: now)
                } else {
                    UpcomingWeekStrip(content: content)
                }
                nextTasks(content)
            } else {
                WidgetNote(text: "Open HITList to fill this in.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(DeepLink.upcoming.url)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Upcoming").font(WidgetLook.header).foregroundStyle(palette.text)
            Spacer(minLength: HITSpacing.s)
            Text(now.formatted(.dateTime.month(.wide).year()))
                .font(WidgetLook.section)
                .foregroundStyle(palette.secondaryText)
        }
    }

    /// The next days' tasks under their day, as many as fit; "Nothing coming up." when there are none.
    @ViewBuilder
    private func nextTasks(_ content: WidgetContent.Upcoming) -> some View {
        if content.days.isEmpty {
            WidgetNote(text: "Nothing coming up.", systemImage: "checkmark")
        } else {
            if family == .systemLarge { stacked(content) } else { inline(content) }
        }
    }

    /// Large: each day's name on its own line over its tasks, as Upcoming's list has them.
    private func stacked(_ content: WidgetContent.Upcoming) -> some View {
        GeometryReader { proxy in
                let items = Self.items(content.days, now: now, style: .full)
                let shown = Self.fit(items, in: proxy.size.height)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(items.prefix(shown).enumerated()), id: \.offset) { _, item in
                        if let row = item.row {
                            if offscreen || row.task.isShared {
                                row
                            } else {
                                Link(destination: DeepLink.task(row.task.id).url) { row }
                            }
                        } else {
                            Text(item.title)
                                .font(WidgetLook.section)
                                .foregroundStyle(item.color)
                                .frame(height: Self.dayLine, alignment: .bottom)
                        }
                    }
                }
        }
    }

    /// Medium: each day's name at the left of its first task, so two or three tasks fit under the strip.
    private func inline(_ content: WidgetContent.Upcoming) -> some View {
        GeometryReader { proxy in
            let rows = content.days.flatMap { day in day.tasks.enumerated().map { (day.date, $0.offset == 0, $0.element) } }
            let shown = WidgetLook.rowsThatFit(rows.map { _ in WidgetLook.rowTitleLine }, in: proxy.size.height, reserve: 0,
                                               spacing: 5)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(rows.prefix(shown).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: HITSpacing.s) {
                        Text(item.1 ? Self.dayName(item.0, now: now) : "")
                            .font(WidgetLook.section)
                            .foregroundStyle(DueFormatter.sectionColor(for: item.0, now: now))
                            .lineLimit(1)
                            .frame(width: Self.dayColumn, height: WidgetLook.rowTitleLine, alignment: .leading)
                        let row = WidgetTaskRow(task: item.2, now: now, style: .titleAndTime)
                        if offscreen || row.task.isShared { row } else { Link(destination: DeepLink.task(row.task.id).url) { row } }
                    }
                }
            }
        }
    }

    private static let dayColumn: CGFloat = 58

    /// "Today", "Tomorrow", then the weekday within the week, then "Nov 23".
    private static func dayName(_ day: Date, now: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: day).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return day.formatted(.dateTime.weekday(.wide))
        default: return day.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private struct Item {
        var row: WidgetTaskRow?
        var title = ""
        var color = Color.clear
        var height: CGFloat { row?.height() ?? UpcomingWidgetView.dayLine }
    }

    private static let dayLine: CGFloat = 13

    private static func items(_ days: [WidgetContent.Upcoming.Day], now: Date, style: WidgetTaskRow.Style) -> [Item] {
        days.flatMap { day in
            [Item(title: DueFormatter.sectionTitle(for: day.date, now: now), color: DueFormatter.sectionColor(for: day.date, now: now))]
                + day.tasks.map { Item(row: WidgetTaskRow(task: $0, now: now, style: style)) }
        }
    }

    /// Whole days' heads and as many rows as fit; never a day's head without a row under it.
    private static func fit(_ items: [Item], in height: CGFloat) -> Int {
        var shown = WidgetLook.rowsThatFit(items.map(\.height), in: height, reserve: 0, spacing: 5)
        while shown > 0, items[shown - 1].row == nil { shown -= 1 }
        return shown
    }
}

/// This week as a strip: weekday initials, the days, a dot under each day with tasks. Today is ringed in the accent and
/// its number bold in the accent, as `HITCalendar` marks it; days already past are dimmer.
struct UpcomingWeekStrip: View {
    let content: WidgetContent.Upcoming
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        let initials = HITCalendar.weekdayInitials(weekStart: content.weekStart, calendar: .current)
        HStack(spacing: 0) {
            ForEach(Array(content.week.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 2) {
                    Text(initials[index]).font(HITType.caption2).foregroundStyle(palette.secondaryText)
                    UpcomingDayNumber(day: day, today: content.today, size: 24, inMonth: true, font: UpcomingDayNumber.stripFont)
                    UpcomingDot(count: content.counts[day] ?? 0, isToday: day == content.today)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week")
    }
}

/// The month as `HITCalendar`'s grid (six weeks, so the height never changes), with the strip's dots.
struct UpcomingMonthGrid: View {
    let content: WidgetContent.Upcoming
    let now: Date
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month], from: now)
        let weeks = HITCalendar.weeks(for: parts.year ?? 2026, month: parts.month ?? 1, weekStart: content.weekStart,
                                      calendar: calendar)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(HITCalendar.weekdayInitials(weekStart: content.weekStart, calendar: calendar).enumerated()),
                        id: \.offset) { _, initial in
                    Text(initial).font(HITType.caption2).foregroundStyle(palette.secondaryText).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 14)
            ForEach(weeks, id: \.first!.date) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.date) { day in
                        VStack(spacing: 1) {
                            UpcomingDayNumber(day: day.date, today: content.today, size: 21, inMonth: day.isInMonth,
                                              font: UpcomingDayNumber.gridFont)
                            UpcomingDot(count: day.isInMonth ? content.counts[day.date] ?? 0 : 0,
                                        isToday: day.date == content.today, size: 3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(now.formatted(.dateTime.month(.wide).year()))
    }
}

/// A day's number: today ringed in the accent with its number bold in the accent (`HITCalendar`'s mark), past days and
/// the neighbouring months' days dimmed as the calendar dims them.
struct UpcomingDayNumber: View {
    let day: Date
    let today: Date
    /// The today ring's diameter.
    let size: CGFloat
    let inMonth: Bool
    let font: (regular: Font, bold: Font)
    @Environment(\.widgetPalette) private var palette

    /// The week strip's numbers: `HITCalendar`'s own roles.
    static let stripFont = (regular: HITType.callout, bold: HITType.calloutBold)
    /// The month grid's: a step smaller, so two digits sit inside the ring on the iPhone.
    #if os(macOS)
    static let gridFont = (regular: HITType.callout, bold: HITType.calloutBold)
    #else
    static let gridFont = (regular: HITType.footnote, bold: HITFont.inter(13, .bold, relativeTo: .footnote))
    #endif

    var body: some View {
        let isToday = day == today
        let isPast = day < today
        let dim: Double = !inMonth ? (isPast ? 0.25 : 0.35) : isPast ? 0.55 : 1
        Text(day.formatted(.dateTime.day()))
            .font((isToday ? font.bold : font.regular).monospacedDigit())
            .foregroundStyle(isToday ? palette.accent : palette.text)
            .opacity(isToday ? 1 : dim)
            .lineLimit(1)
            .fixedSize()
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(palette.accent, lineWidth: isToday ? 1.5 : 0))
            .widgetAccentable(isToday)
    }
}

/// The dot under a day with tasks: the accent under today, grey under the rest; an empty space keeps the line.
struct UpcomingDot: View {
    let count: Int
    let isToday: Bool
    var size: CGFloat = 4
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        Circle()
            .fill(count > 0 ? (isToday ? palette.accent : palette.secondaryText) : .clear)
            .frame(width: size, height: size)
    }
}
