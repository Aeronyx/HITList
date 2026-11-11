import SwiftUI
import HITListCore

/// The Date chip's card (and the Deadline chip's, with `title: "Deadline"`): a row of presets (Today,
/// Tomorrow, Next week, Weekend, No date), `HITCalendar`, then the time row and the Repeat chip when the
/// caller handles them. About 320 pt wide, well inside the 560 pt panel. Picking a day (a preset, a
/// click, or Return in the calendar) or committing a time reports it; the caller closes the card.
struct DatePickerCard: View {
    var selected: Date?
    var now = Date()
    /// Shown above the presets when set ("Deadline").
    var title: String?
    var clearTitle = "No date"
    var onPick: (Date?) -> Void
    /// The time of day; shown only when `onTime` is set.
    var time: PickerTime?
    /// Nil hides the time row; called with nil when the time is removed.
    var onTime: ((PickerTime?) -> Void)?
    var recurrence: RecurrenceRule?
    /// Nil hides the Repeat chip.
    var onRepeat: ((RecurrenceRule?) -> Void)?

    @Environment(\.pickerFocusRequest) private var focusRequest

    init(selected: Date?, now: Date = Date(), title: String? = nil, clearTitle: String = "No date",
         onPick: @escaping (Date?) -> Void,
         time: PickerTime? = nil, onTime: ((PickerTime?) -> Void)? = nil,
         recurrence: RecurrenceRule? = nil, onRepeat: ((RecurrenceRule?) -> Void)? = nil) {
        self.selected = selected
        self.now = now
        self.title = title
        self.clearTitle = clearTitle
        self.onPick = onPick
        self.time = time
        self.onTime = onTime
        self.recurrence = recurrence
        self.onRepeat = onRepeat
    }

    var body: some View {
        let weekStart = Preferences.weekStartWeekday()
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).font(HITType.sectionHeader).foregroundStyle(Theme.secondaryText)
                    .padding([.horizontal, .top], HITSpacing.m)
                    .padding(.bottom, -HITSpacing.xs)
            }
            HStack(spacing: HITSpacing.xs) {
                ForEach(DatePreset.all(now: now, weekStart: weekStart, clearTitle: clearTitle)) { preset in
                    DatePresetTile(preset: preset, isSelected: isPicked(preset)) { onPick(preset.date) }
                        .disabled(preset.kind == .none && selected == nil)
                }
            }
            .padding(.horizontal, HITSpacing.m)
            .padding(.vertical, HITSpacing.s)
            separator
            HITCalendar(selection: selected, today: now, weekStart: weekStart, focusTrigger: focusRequest) { day in
                onPick(day)
            }
            .padding(.horizontal, HITSpacing.m)
            .padding(.top, HITSpacing.s)
            .padding(.bottom, HITSpacing.xs)
            if onTime != nil || onRepeat != nil {
                separator
                HStack(spacing: HITSpacing.s) {
                    if let onTime {
                        PickerTimeField(time: time, onCommit: onTime)
                            .frame(maxWidth: .infinity)
                    }
                    if let onRepeat {
                        RepeatMenu(rule: recurrence, day: selected ?? now, onPick: onRepeat)
                    }
                }
                .padding(.horizontal, HITSpacing.m)
                .padding(.vertical, HITSpacing.s)
            }
        }
    }

    private var separator: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }

    private func isPicked(_ preset: DatePreset) -> Bool {
        guard let date = preset.date, let selected else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selected)
    }
}

/// One of the date card's presets. Pure, so tests can pin the days.
struct DatePreset: Identifiable, Equatable {
    enum Kind: Hashable { case today, tomorrow, nextWeek, weekend, none }

    let kind: Kind
    let title: String
    /// Nil removes the date.
    let date: Date?

    var id: Kind { kind }

    /// Today; tomorrow; the first day of next week (the user's week start); the next Saturday after
    /// today; no date.
    static func all(now: Date, weekStart: Int, calendar: Calendar = .current, clearTitle: String = "No date") -> [DatePreset] {
        let parser = DateExpressionParser(calendar: calendar, now: now, weekStart: weekStart)
        return [
            DatePreset(kind: .today, title: "Today", date: parser.today),
            DatePreset(kind: .tomorrow, title: "Tomorrow", date: parser.day(1)),
            DatePreset(kind: .nextWeek, title: "Next week", date: parser.day(7, from: parser.startOfWeek(containing: now))),
            DatePreset(kind: .weekend, title: "Weekend", date: parser.nextWeekday(7, after: parser.today, inclusive: false)),
            DatePreset(kind: .none, title: clearTitle, date: nil),
        ]
    }

    var symbol: String {
        switch kind {
        case .today: "star"
        case .tomorrow: "sunrise"
        case .nextWeek: "arrow.right.circle"
        case .weekend: "sofa"
        case .none: "circle.slash"
        }
    }

    var tint: Color {
        switch kind {
        case .today: PopoutTint.today
        case .tomorrow: PopoutTint.tomorrow
        case .nextWeek: PopoutTint.later
        case .weekend: Theme.accent
        case .none: Theme.secondaryText
        }
    }
}

/// A preset as a small tile: tinted icon over its name, the chip's colours (`HITChipAppearance`).
private struct DatePresetTile: View {
    let preset: DatePreset
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let look = HITChipAppearance(tint: preset.tint, isSelected: isSelected, isHovered: isHovered && isEnabled)
        let shape = RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous)
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(look.icon)
                Text(preset.title)
                    .font(HITType.caption2)
                    .foregroundStyle(look.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // Five tiles of a fixed 40 pt share the card's width: one size up, "Tomorrow" and "Next week" were
                    // cut ("Tomorr…"). They keep the default size from there, as the tab island's names do (brief 94).
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(shape.fill(look.fill))
            .overlay(shape.strokeBorder(look.border, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : HITButtonStyle.Appearance.disabledOpacity)
        .onHover { isHovered = $0 }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
        .help(preset.date.map { $0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) } ?? preset.title)
        .accessibilityLabel(preset.date.map { "\(preset.title), \($0.formatted(.dateTime.weekday(.wide).month(.wide).day()))" } ?? preset.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
