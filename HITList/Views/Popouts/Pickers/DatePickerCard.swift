import SwiftUI
import HITListCore

/// The Date chip's card (and the Deadline chip's, with `title: "Deadline"`): a row of presets (Today,
/// Tomorrow, Next week, Weekend, No date), `HITCalendar`, then the time row and the Repeat button when the
/// caller handles them. About 320 pt wide, well inside the 560 pt panel. Picking a day (a preset, a
/// click, or Return in the calendar) or committing a time reports it; the caller closes the card.
///
/// The Repeat button (brief 97, Todoist's in picture 4) opens the Repeat menu for the card's day, so a task that
/// does not repeat yet gets a day and a repeat in one visit; once it repeats the button says the rule. On the Mac
/// the menu drops over the calendar, just above the button, and Escape or a click beside it closes only the menu;
/// on iPhone and iPad it takes the card's place, with a way back. Custom… takes the card's place on both; its
/// Cancel comes back to the date. The card's height and presets do not change.
struct DatePickerCard: View {
    var selected: Date?
    var now = Date()
    /// Shown above the presets when set ("Deadline").
    var title: String?
    var clearTitle = "No date"
    /// False turns the No date preset off (Review Inbox schedules; it does not take a date away).
    var canClear = true
    var onPick: (Date?) -> Void
    /// The time of day; shown only when `onTime` is set.
    var time: PickerTime?
    /// Nil hides the time row; called with nil when the time is removed.
    var onTime: ((PickerTime?) -> Void)?
    var recurrence: RecurrenceRule?
    /// Nil hides the Repeat button. Called with the rule picked (nil: Don't repeat); not called when the rule in force
    /// is picked again.
    var onRepeat: ((RecurrenceRule?) -> Void)?
    /// The rule in force was picked again: nothing changes; the caller may close the card.
    var onRepeatKept: (() -> Void)?

    @Environment(\.pickerFocusRequest) private var focusRequest
    @Environment(\.pickerEscape) private var pickerEscape
    @HITEffectsSetting private var effects
    /// The Repeat menu (a dropdown on the Mac, the card's page on iPhone and iPad) or Custom…, while open.
    @State private var repeatPage: RepeatPage?

    enum RepeatPage { case menu, custom }

    init(selected: Date?, now: Date = Date(), title: String? = nil, clearTitle: String = "No date", canClear: Bool = true,
         onPick: @escaping (Date?) -> Void,
         time: PickerTime? = nil, onTime: ((PickerTime?) -> Void)? = nil,
         recurrence: RecurrenceRule? = nil, onRepeat: ((RecurrenceRule?) -> Void)? = nil,
         onRepeatKept: (() -> Void)? = nil) {
        self.selected = selected
        self.now = now
        self.title = title
        self.clearTitle = clearTitle
        self.canClear = canClear
        self.onPick = onPick
        self.time = time
        self.onTime = onTime
        self.recurrence = recurrence
        self.onRepeat = onRepeat
        self.onRepeatKept = onRepeatKept
    }

    /// The day the Repeat menu is worded for: the card's day, or today.
    private var repeatDay: Date { selected ?? now }

    var body: some View {
        Group {
            switch repeatPage {
            case .custom?:
                RepeatCustomCard(rule: recurrence, day: repeatDay, onCancel: { show(nil) }, onDone: pickCustom)
                    .transition(.opacity)
            #if !os(macOS)
            case .menu?:
                repeatMenuPage
                    .transition(.opacity)
            #endif
            default:
                dateContent
                    .transition(.opacity)
            }
        }
        .onChange(of: repeatPage) { _, page in
            // Escape closes the dropdown, not the card (the Mac's picker layer asks first).
            pickerEscape?.action = page == .menu ? { show(nil) } : nil
        }
        .onDisappear { pickerEscape?.action = nil }
    }

    private var dateContent: some View {
        let weekStart = Preferences.weekStartWeekday()
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    Text(title).font(HITType.sectionHeader).foregroundStyle(Theme.secondaryText)
                        .padding([.horizontal, .top], HITSpacing.m)
                        .padding(.bottom, -HITSpacing.xs)
                }
                HStack(spacing: HITSpacing.xs) {
                    ForEach(DatePreset.all(now: now, weekStart: weekStart, clearTitle: clearTitle)) { preset in
                        DatePresetTile(preset: preset, isSelected: isPicked(preset)) { onPick(preset.date) }
                            .disabled(preset.kind == .none && (selected == nil || !canClear))
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
            }
            #if os(macOS)
            .overlay(alignment: .bottom) { repeatDropdown }
            #endif
            if onTime != nil || onRepeat != nil {
                separator
                // One height for the time field and the Repeat button beside it.
                HStack(spacing: HITSpacing.s) {
                    if let onTime {
                        PickerTimeField(time: time, onCommit: onTime)
                            .frame(minWidth: DatePickerCardMetrics.timeFieldMinWidth, maxWidth: .infinity)
                            .frame(maxHeight: .infinity)
                    }
                    if onRepeat != nil {
                        repeatButton
                            .frame(maxWidth: onTime == nil ? .infinity : nil, maxHeight: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, HITSpacing.m)
                .padding(.vertical, HITSpacing.s)
            }
        }
    }

    /// "Repeat", or the rule once there is one ("Every month on the 11th", or "Every month" where that does not fit),
    /// green as the Repeat chip is; a box the time field's height and shape beside it.
    private var repeatButton: some View {
        let isOpen = repeatPage == .menu
        let tint = recurrence == nil ? Theme.secondaryText : PopoutTint.today
        return Button { show(isOpen ? nil : .menu) } label: {
            ViewThatFits(in: .horizontal) {
                repeatWords(recurrence?.rowText ?? "Repeat", tint: tint)
                if let recurrence { repeatWords(recurrence.shortText, tint: tint) }
            }
        }
        .buttonStyle(RepeatFootButtonStyle(tint: recurrence == nil ? nil : PopoutTint.today, isOpen: isOpen))
        .layoutPriority(1)
        .accessibilityLabel(ChipSpeech.repeats(recurrence?.rowText))
        .accessibilityIdentifier("datePickerRepeat")
    }

    private func repeatWords(_ words: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "repeat")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint == Theme.secondaryText ? HITColor.text : tint)
            Text(words)
                .font(HITType.control)
                .foregroundStyle(tint == Theme.secondaryText ? HITColor.text : tint)
                .lineLimit(1)
        }
        .fixedSize()
    }

    #if os(macOS)
    /// The Repeat menu over the calendar, its foot just above the button (picture 4); a click beside it closes it.
    @ViewBuilder
    private var repeatDropdown: some View {
        if repeatPage == .menu {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { show(nil) }
                    .accessibilityHidden(true)
                let shape = RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous)
                RepeatMenuList(rule: recurrence, day: repeatDay, density: .dropdown, onPick: pickFromMenu,
                               onKeep: keep, onCustom: { show(.custom) })
                    .background(shape.fill(Theme.elevated))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1).allowsHitTesting(false))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    // The presets' and the foot's edges.
                    .padding(.horizontal, HITSpacing.m)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .offset(y: 4)))
                    .accessibilityIdentifier("datePickerRepeatMenu")
            }
        }
    }
    #else
    /// The Repeat menu in the card's place, under a way back to the date.
    private var repeatMenuPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { show(nil) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    Text(repeatDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(HITType.body)
                }
                .foregroundStyle(Theme.accent)
                .frame(minHeight: HITRowMetrics.minHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, HITSpacing.m)
            .accessibilityLabel("Back to the date")
            .accessibilityIdentifier("datePickerRepeatBack")
            separator
            RepeatMenuList(rule: recurrence, day: repeatDay, onPick: pickFromMenu, onKeep: keep,
                           onCustom: { show(.custom) })
                .accessibilityIdentifier("datePickerRepeatMenu")
        }
    }
    #endif

    private func show(_ page: RepeatPage?) {
        withAnimation(effects.animation(page == nil ? .exit : .enter)) { repeatPage = page }
    }

    private func pickFromMenu(_ rule: RecurrenceRule?) {
        repeatPage = nil
        onRepeat?(rule)
    }

    private func pickCustom(_ rule: RecurrenceRule) {
        if let recurrence, rule == recurrence, rule.encoded == recurrence.encoded { keep() } else { pickFromMenu(rule) }
    }

    private func keep() {
        show(nil)
        onRepeatKept?()
    }

    private var separator: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }

    private func isPicked(_ preset: DatePreset) -> Bool {
        guard let date = preset.date, let selected else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selected)
    }
}

enum DatePickerCardMetrics {
    /// "12:30 PM" and its ×, whole, beside a long Repeat button.
    #if os(macOS)
    static let timeFieldMinWidth: CGFloat = 132
    #else
    static let timeFieldMinWidth: CGFloat = 150
    #endif
}

/// The date card's Repeat button: the time field's rounded box, elevated, an outline to say it is a button; filled
/// with the repeat's green once set, and while its menu is open.
private struct RepeatFootButtonStyle: ButtonStyle {
    var tint: Color?
    var isOpen: Bool

    func makeBody(configuration: Configuration) -> some View {
        RepeatFootButtonBody(configuration: configuration, tint: tint, isOpen: isOpen)
    }
}

private struct RepeatFootButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color?
    let isOpen: Bool
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous)
        let lit = isHovered || isOpen || configuration.isPressed
        let fill: Color = tint.map { $0.opacity(lit ? 0.24 : 0.16) } ?? (lit ? Theme.separator : Theme.elevated)
        let border: Color = tint.map { $0.opacity(0.45) } ?? Theme.separator
        configuration.label
            .padding(.horizontal, HITSpacing.m)
            .frame(maxHeight: .infinity)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .contentShape(shape)
            .onHover { isHovered = $0 }
            .animation(HITMotion.quick(reduceMotion: reduceMotion), value: lit)
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
