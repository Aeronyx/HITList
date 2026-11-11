import SwiftUI
import HITListCore

/// Custom… (brief 97, item 2; macOS Calendar's custom repeat, George's picture 5), drawn in our own controls, never a
/// system picker: the frequency (Daily · Weekly · Monthly · Yearly); "Every [n] weeks"; for a weekly repeat seven day
/// buttons from the first day of the week in Settings, at least one on; for a monthly one a day of the month, the
/// last day, or the first to fifth or last of a weekday; for a yearly one a month and its day; then one line saying
/// the rule in the row's words, and Cancel and Done. Core's `RepeatForm` decides what it shows and builds, so opening
/// it on any rule shows that rule, and Done with nothing changed gives the same rule back.
struct RepeatCustomCard: View {
    var onCancel: () -> Void
    var onDone: (RecurrenceRule) -> Void

    @State private var form: RepeatForm
    @State private var intervalText: String
    private let weekStart: Int

    init(rule: RecurrenceRule?, day: Date, weekStart: Int = Preferences.weekStartWeekday(),
         onCancel: @escaping () -> Void, onDone: @escaping (RecurrenceRule) -> Void) {
        let form = RepeatForm(rule: rule, day: day)
        _form = State(initialValue: form)
        _intervalText = State(initialValue: String(form.interval))
        self.weekStart = weekStart
        self.onCancel = onCancel
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: RepeatCustomMetrics.gap) {
                HITSegmented(selection: frequency, segments: [
                    HITSegment(.daily, "Daily"), HITSegment(.weekly, "Weekly"),
                    HITSegment(.monthly, "Monthly"), HITSegment(.yearly, "Yearly"),
                ])
                .accessibilityIdentifier("repeatCustomFrequency")
                intervalRow
                switch form.frequency {
                case .daily: EmptyView()
                case .weekly: weekdayButtons(selected: form.weekdays, multiple: true)
                case .monthly: monthlyPlace
                case .yearly: yearlyDate
                }
            }
            .padding(HITSpacing.m)
            Rectangle().fill(Theme.separator).frame(height: 1)
            footer
        }
        .animation(HITMotion.standard(reduceMotion: false), value: form.frequency)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("repeatCustomCard")
    }

    // MARK: Rows

    private var frequency: Binding<RecurrenceRule.Frequency> {
        Binding(get: { form.frequency }, set: { form.frequency = $0 })
    }

    /// "Every [ − 2 + ] weeks".
    private var intervalRow: some View {
        HStack(spacing: HITSpacing.s) {
            Text("Every").font(HITType.body).foregroundStyle(HITColor.text)
            RepeatIntervalField(value: form.interval, text: $intervalText) { n in
                form.interval = n
            } onSubmit: {
                onDone(form.rule)
            }
            Text(form.unit).font(HITType.body).foregroundStyle(HITColor.text)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
    }

    /// Seven day buttons in the order of the week in Settings: several on for a weekly repeat, one for a monthly
    /// repeat on a weekday.
    private func weekdayButtons(selected: Set<Int>, multiple: Bool) -> some View {
        SevenAcross(items: RepeatWords.week(from: weekStart)) { weekday in
            RepeatToggleCell(title: RepeatWords.initials[weekday - 1], isOn: selected.contains(weekday),
                             shape: .circle, outlined: true) {
                if multiple { form.toggle(weekday: weekday) } else { form.ordinalWeekday = weekday }
            }
            .accessibilityLabel(RepeatWords.weekdays[weekday - 1])
            .accessibilityIdentifier("repeatCustomWeekday\(weekday)")
        }
    }

    private var monthlyPlace: some View {
        VStack(alignment: .leading, spacing: RepeatCustomMetrics.gap) {
            HITSegmented(selection: Binding(get: { form.monthly }, set: { form.monthly = $0 }), segments: [
                HITSegment(.day, "Day"), HITSegment(.lastDay, "Last day"), HITSegment(.weekday, "Weekday"),
            ])
            .accessibilityIdentifier("repeatCustomMonthly")
            switch form.monthly {
            case .day:
                dayGrid(count: 31, selected: form.monthDay) { form.monthDay = $0 }
            case .lastDay:
                Text("The last day of each month: the 28th to the 31st.")
                    .font(HITType.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            case .weekday:
                HITSegmented(selection: Binding(get: { form.ordinal }, set: { form.ordinal = $0 }),
                             segments: [1, 2, 3, 4, 5, -1].map { HITSegment($0, $0 == -1 ? "Last" : RepeatWords.ordinal($0)) })
                    .accessibilityIdentifier("repeatCustomOrdinal")
                weekdayButtons(selected: [form.ordinalWeekday], multiple: false)
            }
        }
    }

    private var yearlyDate: some View {
        VStack(alignment: .leading, spacing: RepeatCustomMetrics.gap) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(1...12, id: \.self) { month in
                    RepeatToggleCell(title: RepeatWords.shortMonths[month - 1], isOn: form.month == month,
                                     shape: .capsule, outlined: false) { form.setMonth(month) }
                        .accessibilityLabel(RepeatWords.months[month - 1])
                        .accessibilityIdentifier("repeatCustomMonth\(month)")
                }
            }
            dayGrid(count: RepeatForm.days(inMonth: form.month), selected: form.yearDay) { form.yearDay = $0 }
        }
    }

    /// The days 1 to `count`, seven to a row, in the weekday buttons' columns.
    private func dayGrid(count: Int, selected: Int, pick: @escaping (Int) -> Void) -> some View {
        SevenAcross(items: Array(1...count), rowSpacing: 2) { day in
            RepeatToggleCell(title: "\(day)", isOn: selected == day, shape: .circle, outlined: false) { pick(day) }
                .accessibilityLabel(RepeatWords.ordinal(day))
                .accessibilityIdentifier("repeatCustomDay\(day)")
        }
    }

    /// The rule in the row's words, then Cancel and Done.
    private var footer: some View {
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "repeat")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PopoutTint.today)
                    .accessibilityHidden(true)
                Text(form.rule.displayText(weekStart: weekStart))
                    .font(HITType.callout)
                    .foregroundStyle(HITColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("repeatCustomSummary")
            }
            // Both on the right, as in Calendar's (picture 5): the card's left edge holds only its words.
            HStack(spacing: HITSpacing.s) {
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .buttonStyle(HITButtonStyle(.ghost, size: .small))
                    .accessibilityIdentifier("repeatCustomCancel")
                Button("Done") { onDone(form.rule) }
                    .buttonStyle(HITButtonStyle(.primary, size: .small))
                    .accessibilityIdentifier("repeatCustomDone")
            }
        }
        .padding(.horizontal, HITSpacing.m)
        .padding(.top, HITSpacing.s + 2)
        .padding(.bottom, HITSpacing.m)
    }
}

/// Seven cells to a row, the first flush with the card's left edge and the seventh with its right, so the weekday
/// buttons and the days under them share their columns and the edges of the rows above.
private struct SevenAcross<Item: Hashable, Cell: View>: View {
    let items: [Item]
    var rowSpacing: CGFloat = 0
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 7).map { Array(items[$0..<min($0 + 7, items.count)]) }
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        if column > 0 { Spacer(minLength: 0) }
                        if column < row.count {
                            cell(row[column])
                        } else {
                            Color.clear.frame(width: RepeatCustomMetrics.cell, height: RepeatCustomMetrics.cell)
                        }
                    }
                }
            }
        }
    }
}

enum RepeatCustomMetrics {
    #if os(macOS)
    static let gap: CGFloat = HITSpacing.m
    static let cell: CGFloat = 30
    #else
    static let gap: CGFloat = HITSpacing.m
    static let cell: CGFloat = 34
    #endif
}

/// A day, a weekday or a month to pick: the calendar's look (`HITCalendar`), filled with the accent when on; the
/// weekday buttons are outlined while off so seven of them read as buttons.
struct RepeatToggleCell: View {
    enum Shape { case circle, capsule }

    let title: String
    let isOn: Bool
    var shape: Shape = .circle
    var outlined = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isOn ? HITType.calloutBold : HITType.callout)
                .monospacedDigit()
                .foregroundStyle(isOn ? HITColor.onAccent : HITColor.text)
                .lineLimit(1)
                .frame(width: shape == .circle ? RepeatCustomMetrics.cell : nil, height: RepeatCustomMetrics.cell)
                .frame(maxWidth: shape == .capsule ? .infinity : nil)
                .background(background)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isHovered)
        .animation(HITMotion.quick(reduceMotion: reduceMotion), value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private var background: some View {
        let fill = isOn ? Theme.accent : isHovered ? Theme.elevated : Color.clear
        let border = isOn || !outlined ? Color.clear : Theme.separator
        switch shape {
        case .circle:
            Circle().fill(fill).overlay(Circle().strokeBorder(border, lineWidth: 1))
        case .capsule:
            Capsule().fill(fill).overlay(Capsule().strokeBorder(border, lineWidth: 1))
        }
    }
}

/// "[ − 2 + ]": the interval, typed or stepped, 1 to 999.
struct RepeatIntervalField: View {
    let value: Int
    @Binding var text: String
    var onChange: (Int) -> Void
    var onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.pickerFocusRequest) private var focusRequest

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HITRadius.field, style: .continuous)
        HStack(spacing: 0) {
            step(-1, systemImage: "minus", label: "Fewer")
                .disabled(value <= 1)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(HITType.body)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(width: 36)
                .focused($isFocused)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onSubmit {
                    commit()
                    onSubmit()
                }
                .onChange(of: text) { _, typed in
                    if let n = RepeatForm.interval(from: typed) { onChange(n) }
                }
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                .accessibilityLabel("Interval")
                .accessibilityIdentifier("repeatCustomInterval")
            step(1, systemImage: "plus", label: "More")
                .disabled(value >= RecurrenceRule.maxInterval)
        }
        .frame(height: HITButtonStyle.Size.small.height)
        .background(shape.fill(Theme.elevated))
        .overlay(shape.strokeBorder(isFocused ? Theme.accent : Theme.separator, lineWidth: isFocused ? 1.5 : 1))
        .onChange(of: focusRequest) { _, _ in isFocused = true }
    }

    private func step(_ by: Int, systemImage: String, label: String) -> some View {
        Button {
            let n = min(max(value + by, 1), RecurrenceRule.maxInterval)
            text = String(n)
            onChange(n)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: HITButtonStyle.Size.small.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(HITIconButtonStyle(font: .system(size: 11, weight: .bold)))
        .accessibilityLabel(label)
    }

    /// A field left blank or out of range shows the interval again.
    private func commit() {
        if RepeatForm.interval(from: text) == nil { text = String(value) }
    }
}
