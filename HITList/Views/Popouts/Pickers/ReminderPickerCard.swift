import SwiftUI
import HITListCore

/// The Reminder chip's card. First, a reminder of its own from now (brief 48): "In 15 minutes", "In 1 hour"
/// (they write `!15m` / `!1h`) and "Later today…" (a time; tomorrow's if it has passed), whatever the task's
/// date; tapping the chosen one again takes it away. Then a task reminds at its time, or a while before it:
/// the offsets (At time, 5, 10, 15, 30 min, 1 hour, 1 day before) as chips two per row, the last cell a custom
/// "N min before" field; then the time row (typed, or 9 AM / Noon / 5 PM / 8 PM) and when it fires ("Fires
/// 10:45 AM"). Offsets write `!15mb` and keep the card open so a time can follow; a time closes it.
struct ReminderPickerCard: View {
    /// The task's day (nil: today).
    var day: Date?
    var time: PickerTime?
    /// Minutes before the time; nil or 0 is at the time.
    var offsetMinutes: Int?
    var now = Date()
    /// Nil removes the time.
    var onTime: (PickerTime?) -> Void
    /// "No reminder": no time, no offset.
    var onClear: () -> Void
    /// Nil hides the offsets.
    var onOffset: ((Int?) -> Void)?
    /// The task's own reminder moment ("!15m"), and the span it was typed as (quick add, before it is saved).
    var reminderDate: Date? = nil
    var fromNow: ReminderSpan? = nil
    /// A "from now" choice; nil takes the moment away. Nil hides the choices.
    var onMoment: ((ReminderMomentPick?) -> Void)? = nil

    @Environment(\.pickerFocusRequest) private var focusRequest
    /// iPhone: the height the card has beside its chip (`PhonePickerPlacement`).
    @Environment(\.pickerRoom) private var pickerRoom
    /// "Later today…" was tapped: its time field shows.
    @State private var picksLater = false

    /// The short layout (brief 107): the regular card is about 490 pt tall, and beside the editor's Reminder pill on the
    /// iPhone Duo's outer display there are about 330. Wider (`PickerKind.width(room:)`), three offsets to a row and the
    /// "from now" choices and the times on one row each, the "Time" header left to the field's own "Add time", tighter
    /// spacing: about 325 pt.
    private var isShort: Bool { PickerKind.reminder.isShort(room: pickerRoom) }

    /// The "from now" spans offered as chips.
    static let fromNowPresets: [ReminderSpan] = [ReminderSpan(minutes: 15), ReminderSpan(minutes: 60)]

    /// "Later today…" at `time`: today, or tomorrow when that time has already gone.
    static func laterToday(_ time: PickerTime, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = time.on(now, calendar: calendar)
        return today > now ? today : time.on(calendar.date(byAdding: .day, value: 1, to: now) ?? now, calendar: calendar)
    }

    /// "In 15 minutes", "In 1 hour"; "In 15 min" in the short layout, for the three to share a row.
    static func fromNowTitle(_ span: ReminderSpan, short: Bool = false) -> String {
        span.totalMinutes == 60 ? "In 1 hour" : span.totalMinutes == 15 ? (short ? "In 15 min" : "In 15 minutes") : "In " + span.text
    }

    /// The offsets, in minutes before the time.
    static let offsetPresets: [Int] = [0, 5, 10, 15, 30, 60, 1440]

    /// The time chips: (label, time).
    static let timePresets: [(String, PickerTime)] = [
        ("9 AM", PickerTime(hour: 9, minute: 0)), ("Noon", PickerTime(hour: 12, minute: 0)),
        ("5 PM", PickerTime(hour: 17, minute: 0)), ("8 PM", PickerTime(hour: 20, minute: 0)),
    ]

    /// "Fires 10:45 AM" (on the task's day), "Fires Mon 11:00 AM" (an offset reaching an earlier day);
    /// nil without a time.
    static func fireText(day: Date?, time: PickerTime?, offsetMinutes: Int?, now: Date = Date(),
                         calendar: Calendar = .current) -> String? {
        guard let time else { return nil }
        let due = time.on(day ?? now, calendar: calendar)
        let fire = due.addingTimeInterval(-Double(max(offsetMinutes ?? 0, 0)) * 60)
        let clock = fire.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(fire, inSameDayAs: due) { return "Fires " + clock }
        return "Fires " + fire.formatted(.dateTime.weekday(.abbreviated)) + " " + clock
    }

    /// An offset chip's title, short enough for two per row at iPhone sizes: "At time", "5 min", "1 hour",
    /// "1 day" (the header says "before the time"; the chip on the bar keeps the long "15 min before").
    static func chipTitle(minutes: Int) -> String {
        minutes > 0 ? ReminderOffset.duration(minutes: minutes) : "At time"
    }

    /// The custom field's minutes: a whole number from 1 up to the grammar's four weeks.
    static func customOffset(_ text: String) -> Int? {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)), (1...ReminderOffset.maxMinutes).contains(n) else { return nil }
        return n
    }

    private var isCustomOffset: Bool {
        guard let offsetMinutes, offsetMinutes > 0 else { return false }
        return !Self.offsetPresets.contains(offsetMinutes)
    }

    var body: some View {
        let short = isShort
        VStack(alignment: .leading, spacing: short ? 5 : HITSpacing.s) {
            if let onMoment {
                fromNowSection(onMoment)
                sectionRule
            }
            if let onOffset {
                header("Remind me before the time")
                if short {
                    shortOffsets(onOffset)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6, alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 6) {
                        ForEach(Self.offsetPresets, id: \.self) { minutes in offsetChip(minutes, onOffset) }
                        CustomOffsetField(minutes: isCustomOffset ? offsetMinutes : nil, onCommit: onOffset)
                    }
                }
                sectionRule
            }
            if onOffset == nil || !short {
                header(onOffset == nil ? "Remind me at" : "Time")
            }
            PickerTimeField(time: time, focusTrigger: focusRequest, onCommit: onTime)
            HITChipRow {
                ForEach(Self.timePresets, id: \.0) { preset in
                    HITChip(preset.0, systemImage: "alarm", tint: Theme.accent, isSelected: time == preset.1,
                            action: { onTime(preset.1) })
                }
            }
            HStack(alignment: .center, spacing: HITSpacing.s) {
                if let fire = Self.fireText(day: day, time: time, offsetMinutes: offsetMinutes, now: now) {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.fill").font(.system(size: 10, weight: .semibold))
                        Text(fire).font(HITType.captionBold)
                    }
                    .foregroundStyle(Theme.accent)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("reminderFires")
                } else {
                    Text((offsetMinutes ?? 0) > 0 ? "Pick a time too: the reminder counts back from it."
                                                  : "Reminders arrive at the task’s time when notifications are on.")
                        .font(HITType.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if time != nil || reminderDate != nil {
                    Button("No reminder", role: .destructive, action: onClear)
                        .buttonStyle(HITButtonStyle(.destructive, size: .small))
                }
            }
            .padding(.top, short ? 2 : HITSpacing.xs)
        }
        .padding(.horizontal, short ? HITSpacing.s : HITSpacing.m)
        .padding(.vertical, short ? HITSpacing.s + 2 : HITSpacing.m)
    }

    private func header(_ title: String) -> some View {
        Text(title).font(HITType.sectionHeader).foregroundStyle(Theme.secondaryText)
    }

    /// The hairline between the sections.
    private var sectionRule: some View {
        Rectangle().fill(Theme.separator).frame(height: 1).padding(.vertical, isShort ? 2 : HITSpacing.xs)
    }

    private func offsetChip(_ minutes: Int, _ onOffset: @escaping (Int?) -> Void) -> some View {
        HITChip(Self.chipTitle(minutes: minutes), systemImage: minutes == 0 ? "bell" : "bell.badge",
                tint: Theme.accent, isSelected: (offsetMinutes ?? 0) == minutes,
                action: { onOffset(minutes == 0 ? nil : minutes) })
            .accessibilityLabel(ReminderOffset.label(minutes: minutes))
            .help(ReminderOffset.label(minutes: minutes))
            .accessibilityIdentifier("reminderOffset\(minutes)")
    }

    /// The short layout's offsets: three to a row, the custom minutes after "1 day" taking the rest of its row.
    private func shortOffsets(_ onOffset: @escaping (Int?) -> Void) -> some View {
        let presets = Self.offsetPresets
        return Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 5) {
            GridRow { ForEach(presets[0..<3], id: \.self) { offsetChip($0, onOffset) } }
            GridRow { ForEach(presets[3..<6], id: \.self) { offsetChip($0, onOffset) } }
            GridRow {
                offsetChip(presets[6], onOffset)
                CustomOffsetField(minutes: isCustomOffset ? offsetMinutes : nil, onCommit: onOffset)
                    .gridCellColumns(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Remind me from now": the spans, "Later today…" and its time field, and when it goes off.
    @ViewBuilder
    private func fromNowSection(_ onMoment: @escaping (ReminderMomentPick?) -> Void) -> some View {
        let picked = reminderDate != nil && !Self.fromNowPresets.contains { $0 == fromNow }
        header("Remind me from now")
        let chips = Group {
            ForEach(Self.fromNowPresets, id: \.self) { span in
                let selected = reminderDate != nil && fromNow == span
                HITChip(Self.fromNowTitle(span, short: isShort), systemImage: "timer", tint: Theme.accent, isSelected: selected,
                        action: { onMoment(selected ? nil : .span(span)) })
                    .accessibilityIdentifier("reminderFromNow\(span.totalMinutes)")
            }
            HITChip("Later today…", systemImage: "clock", tint: Theme.accent, isSelected: picked || picksLater,
                    action: {
                        if picked { onMoment(nil); picksLater = false } else { picksLater.toggle() }
                    })
                .accessibilityIdentifier("reminderLaterToday")
        }
        if isShort {
            // One row in the short layout's width.
            HITChipRow { chips }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6, alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 6) {
                chips
            }
        }
        if picksLater || picked {
            PickerTimeField(time: picked ? reminderDate.map { PickerTime($0) } : nil, placeholder: "Remind at…") { time in
                onMoment(time.map { .at(Self.laterToday($0, now: now)) })
                if time == nil { picksLater = false }
            }
            .accessibilityIdentifier("reminderLaterTodayTime")
        }
        // A span says when it goes off; a picked moment's time is in its field already.
        if let reminderDate, !picked {
            HStack(spacing: 4) {
                Image(systemName: "bell.fill").font(.system(size: 10, weight: .semibold))
                Text("Goes off " + ReminderChipText.when(reminderDate, now: now))
                    .font(HITType.captionBold)
            }
            .foregroundStyle(Theme.accent)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("reminderMomentFires")
        }
    }
}

/// The offsets' last cell: a chip-sized box holding "[ 45 ] min" (before); Return sets it.
private struct CustomOffsetField: View {
    /// The current offset when it isn't one of the presets.
    var minutes: Int?
    var onCommit: (Int?) -> Void

    @State private var text: String
    @State private var invalid = false
    @FocusState private var isFocused: Bool

    init(minutes: Int?, onCommit: @escaping (Int?) -> Void) {
        self.minutes = minutes
        self.onCommit = onCommit
        _text = State(initialValue: minutes.map(String.init) ?? "")
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.chip, style: .continuous)
        let selected = minutes != nil
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
            TextField(text: $text) { Text("N").foregroundStyle(Theme.secondaryText) }
                .textFieldStyle(.plain)
                .font(HITType.control)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 36)
                .focused($isFocused)
                .onSubmit(commit)
                .accessibilityLabel("Custom minutes before")
                .accessibilityIdentifier("reminderCustomOffset")
            Text("min")
                .font(HITType.control)
                .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, HITSpacing.s + 2)
        .frame(height: HITChip.Size.regular.height)
        .background(shape.fill(selected ? Theme.accent.opacity(0.16) : .clear))
        .overlay(shape.strokeBorder(invalid ? HITColor.danger : isFocused ? Theme.accent : selected ? Theme.accent.opacity(0.45) : Theme.separator,
                                    lineWidth: isFocused || invalid ? 1.5 : 1))
        .help("Type a number of minutes, then Return")
        .onChange(of: text) { _, _ in invalid = false }
        .onChange(of: minutes) { _, value in if !isFocused { text = value.map(String.init) ?? "" } }
    }

    private func commit() {
        guard let n = ReminderPickerCard.customOffset(text) else {
            invalid = !text.isEmpty
            return
        }
        onCommit(n)
    }
}
