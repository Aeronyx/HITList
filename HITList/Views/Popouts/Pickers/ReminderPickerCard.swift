import SwiftUI
import HITListCore

/// The Reminder chip's card. A task reminds at its time, or a while before it: the offsets (At time,
/// 5, 10, 15, 30 min, 1 hour, 1 day before) as chips two per row, the last cell a custom "N min
/// before" field; then the time row (typed, or 9 AM / Noon / 5 PM / 8 PM) and when it fires ("Fires
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

    @Environment(\.pickerFocusRequest) private var focusRequest

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
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            if let onOffset {
                header("Remind me before the time")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6, alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    ForEach(Self.offsetPresets, id: \.self) { minutes in
                        HITChip(Self.chipTitle(minutes: minutes), systemImage: minutes == 0 ? "bell" : "bell.badge",
                                tint: Theme.accent, isSelected: (offsetMinutes ?? 0) == minutes,
                                action: { onOffset(minutes == 0 ? nil : minutes) })
                            .accessibilityLabel(ReminderOffset.label(minutes: minutes))
                            .help(ReminderOffset.label(minutes: minutes))
                            .accessibilityIdentifier("reminderOffset\(minutes)")
                    }
                    CustomOffsetField(minutes: isCustomOffset ? offsetMinutes : nil, onCommit: onOffset)
                }
                Rectangle().fill(Theme.separator).frame(height: 1).padding(.vertical, HITSpacing.xs)
            }
            header(onOffset == nil ? "Remind me at" : "Time")
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
                if time != nil {
                    Button("No reminder", role: .destructive, action: onClear)
                        .buttonStyle(HITButtonStyle(.destructive, size: .small))
                }
            }
            .padding(.top, HITSpacing.xs)
        }
        .padding(HITSpacing.m)
    }

    private func header(_ title: String) -> some View {
        Text(title).font(HITType.sectionHeader).foregroundStyle(Theme.secondaryText)
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
