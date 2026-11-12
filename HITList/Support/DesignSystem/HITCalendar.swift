import SwiftUI

/// HITList's month calendar: the month and year in Inter with ‹ › and a "today" dot between them,
/// weekday initials, then six weeks of 32 pt day circles. Today is ringed in the accent, the selected
/// day is filled with it (`HITColor.onAccent` text), days of the neighbouring months are dimmed and past
/// days a little dimmer. With keyboard focus the arrow keys move the selection (across months) and
/// Return picks it; a click picks at once. Weeks start on `weekStart` (1 = Sunday … 7 = Saturday,
/// `Preferences.weekStartWeekday()`).
///
///     HITCalendar(selection: task.dueDate, weekStart: Preferences.weekStartWeekday()) { day in reschedule(to: day) }
struct HITCalendar: View {
    /// One cell of the grid.
    struct Day: Hashable {
        /// Start of the day.
        let date: Date
        /// False for the neighbouring months' days that fill the first and last weeks.
        let isInMonth: Bool
    }

    /// How many weeks the grid always shows, so the card never changes height between months.
    static let weeksShown = 6
    static let cellSize: CGFloat = 32
    static let rowSpacing: CGFloat = 1

    var selection: Date?
    var today: Date
    var weekStart: Int
    var calendar: Calendar
    /// Changing it gives the calendar keyboard focus (a picker card passes its focus request).
    var focusTrigger: Int
    /// The day circles' side: `cellSize`, or less in a picker card's short layout (brief 107: the iPhone Duo's outer
    /// display, 678 pt tall, had no room for the editor's date card).
    var daySize: CGFloat
    /// The first and last columns' circles on the calendar's own edges, under the month's name and the arrows, the
    /// grid reaching out past them by the columns' spare room (brief 114: the date card's month and days did not share
    /// a left edge). Off, the columns fill the width and each circle sits in the middle of its own.
    var circlesOnEdges: Bool
    var onPick: (Date) -> Void

    /// How far the grid reaches past each side with `circlesOnEdges`.
    @State private var outset: CGFloat = 0

    @State private var month: Date
    /// The keyboard's selection before Return; nil follows `selection`.
    @State private var cursor: Date?
    @State private var hovered: Date?
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selection: Date?, today: Date = Date(), weekStart: Int = 2, calendar: Calendar = .current,
         focusTrigger: Int = 0, daySize: CGFloat = HITCalendar.cellSize, circlesOnEdges: Bool = false,
         onPick: @escaping (Date) -> Void) {
        self.selection = selection.map { calendar.startOfDay(for: $0) }
        self.today = calendar.startOfDay(for: today)
        self.weekStart = weekStart
        self.calendar = calendar
        self.focusTrigger = focusTrigger
        self.daySize = daySize
        self.circlesOnEdges = circlesOnEdges
        self.onPick = onPick
        _month = State(initialValue: Self.firstOfMonth(selection ?? today, calendar: calendar))
    }

    // MARK: Pure layout helpers

    /// The first day of the month containing `date`.
    static func firstOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    /// The month `offset` months after the one starting `month`.
    static func month(_ month: Date, adding offset: Int, calendar: Calendar) -> Date {
        firstOfMonth(calendar.date(byAdding: .month, value: offset, to: month)!, calendar: calendar)
    }

    /// The six weeks shown for `month` (1…12) of `year`: each week seven days long and starting on
    /// `weekStart`; the first week holds the 1st (which may be its first day).
    static func weeks(for year: Int, month: Int, weekStart: Int, calendar: Calendar) -> [[Day]] {
        let first = calendar.startOfDay(for: calendar.date(from: DateComponents(year: year, month: month, day: 1))!)
        let lead = (calendar.component(.weekday, from: first) - weekStart + 7) % 7
        let start = calendar.date(byAdding: .day, value: -lead, to: first)!
        return (0..<weeksShown).map { week in
            (0..<7).map { weekday in
                let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: week * 7 + weekday, to: start)!)
                let parts = calendar.dateComponents([.year, .month], from: date)
                return Day(date: date, isInMonth: parts.year == year && parts.month == month)
            }
        }
    }

    /// The weekday initials in grid order ("M T W T F S S" from Monday).
    static func weekdayInitials(weekStart: Int, calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(weekStart - 1 + $0) % 7] }
    }

    /// With `circlesOnEdges`: how far the grid reaches past each side of a calendar `width` wide for the first and last
    /// columns' circles to sit on its edges. A column is (width + 2 × outset) / 7 and its circle is in its middle, so
    /// (column − daySize) / 2 = outset, which is (width − 7 × daySize) / 12.
    static func outset(width: CGFloat, daySize: CGFloat) -> CGFloat {
        let spare = width - 7 * daySize
        return max(0, spare / 12)
    }

    enum Move { case previousDay, nextDay, previousWeek, nextWeek }

    /// Where an arrow key takes the selection.
    static func moved(_ day: Date, _ move: Move, calendar: Calendar) -> Date {
        let offset = switch move {
        case .previousDay: -1
        case .nextDay: 1
        case .previousWeek: -7
        case .nextWeek: 7
        }
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: day)!)
    }

    // MARK: View

    private var shownSelection: Date? { cursor ?? selection }

    var body: some View {
        VStack(spacing: HITSpacing.xs) {
            header
            grid
                .padding(.horizontal, -outset)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            circlesOnEdges ? Self.outset(width: proxy.size.width, daySize: daySize) : 0
        } action: { outset = $0 }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return]) { press in
            handle(press.key)
        }
        .onChange(of: focusTrigger) { _, _ in isFocused = true }
    }

    private var header: some View {
        let parts = calendar.dateComponents([.year, .month], from: month)
        let todayMonth = Self.firstOfMonth(today, calendar: calendar)
        return HStack(spacing: 6) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(HITType.headline)
                .foregroundStyle(HITColor.text)
                .accessibilityAddTraits(.isHeader)
                .id(parts.month! + 12 * parts.year!)
                .transition(.opacity)
            Spacer(minLength: HITSpacing.s)
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(HITIconButtonStyle(font: .system(size: 12, weight: .semibold)))
                .accessibilityLabel("Previous month")
                .help("Previous month")
            Button { show(todayMonth) } label: {
                Circle()
                    .fill(month == todayMonth ? Theme.secondaryText.opacity(0.5) : Theme.accent)
                    .frame(width: 7, height: 7)
                    .frame(width: 18, height: 24)
                    // Taller into the empty space above and below (brief 94); not wider: ‹ and › are beside it. Written out
                    // rather than `hitOutset`, which the widget extension (it compiles this file) does not have.
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -6)
            .accessibilityLabel("This month")
            .help("Today")
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(HITIconButtonStyle(font: .system(size: 12, weight: .semibold)))
                .accessibilityLabel("Next month")
                .help("Next month")
        }
        .frame(height: 22)
    }

    private var grid: some View {
        let parts = calendar.dateComponents([.year, .month], from: month)
        let weeks = Self.weeks(for: parts.year!, month: parts.month!, weekStart: weekStart, calendar: calendar)
        return VStack(spacing: Self.rowSpacing) {
            HStack(spacing: 0) {
                ForEach(Array(Self.weekdayInitials(weekStart: weekStart, calendar: calendar).enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(HITType.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: daySize < Self.cellSize ? 14 : 16)
            .accessibilityHidden(true)
            ForEach(weeks, id: \.first!.date) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.date) { day in cell(day) }
                }
            }
        }
    }

    private func cell(_ day: Day) -> some View {
        let isSelected = shownSelection == day.date
        let isToday = day.date == today
        let isPast = day.date < today
        let isHovered = hovered == day.date && !isSelected
        let dim: Double = isSelected ? 1 : !day.isInMonth ? (isPast ? 0.25 : 0.35) : isPast ? 0.55 : 1
        return Button { pick(day.date) } label: {
            Text(day.date.formatted(.dateTime.day()))
                .font(isSelected || isToday ? HITType.calloutBold : HITType.callout)
                .monospacedDigit()
                .foregroundStyle(isSelected ? HITColor.onAccent : isToday ? Theme.accent : HITColor.text)
                .opacity(dim)
                .frame(width: daySize, height: daySize)
                .background(Circle().fill(isSelected ? Theme.accent : isHovered ? Theme.elevated : .clear))
                .overlay(Circle().strokeBorder(Theme.accent, lineWidth: isToday && !isSelected ? 1.5 : 0))
                // The keyboard's place, while the calendar has focus.
                .overlay(Circle().strokeBorder(HITColor.text.opacity(0.6), lineWidth: isFocused && isSelected ? 1.5 : 0).padding(-3))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = day.date } else if hovered == day.date { hovered = nil }
        }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
        .accessibilityLabel(accessibilityLabel(day.date, isToday: isToday))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityLabel(_ day: Date, isToday: Bool) -> String {
        day.formatted(.dateTime.weekday(.wide).month(.wide).day()) + (isToday ? ", Today" : "")
    }

    // MARK: Actions

    private func pick(_ day: Date) {
        cursor = day
        onPick(day)
    }

    private func step(_ months: Int) {
        show(Self.month(month, adding: months, calendar: calendar))
    }

    private func show(_ newMonth: Date) {
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) { month = newMonth }
    }

    private func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        if key == .return {
            guard let day = shownSelection else { return .ignored }
            onPick(day)
            return .handled
        }
        let move: Move = switch key {
        case .leftArrow: .previousDay
        case .rightArrow: .nextDay
        case .upArrow: .previousWeek
        default: .nextWeek
        }
        let day = Self.moved(shownSelection ?? today, move, calendar: calendar)
        cursor = day
        let dayMonth = Self.firstOfMonth(day, calendar: calendar)
        if dayMonth != month { show(dayMonth) }
        return .handled
    }
}
