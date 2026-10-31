import SwiftUI
import HITListCore

// The compact popovers behind the popouts' chips, shared by the quick-add card and the task popout.
// Each one reports a pick through a closure and leaves storing it to the caller.

/// How each chip and highlighted token is tinted.
enum PopoutTint {
    static let today = HITColor.dueToday
    static let tomorrow = HITColor.dueTomorrow
    static let later = HITColor.dueLater
    static let overdue = HITColor.dueOverdue
    static let label = Color(hex: "#E5A05C")
    static let project = Color(hex: "#B07CF5")

    /// Green today, orange tomorrow, purple later, red when overdue (`HITColor.due`).
    static func date(_ date: Date?, hasTime: Bool = false, now: Date = Date(), calendar: Calendar = .current) -> Color {
        HITColor.due(date, hasTime: hasTime, now: now, calendar: calendar)
    }

    static func token(_ kind: QuickAddToken.Kind, priority: Priority) -> Color {
        switch kind {
        case .date, .time, .recurrence, .reminder: return today
        case .priority: return priority.color
        case .project: return project
        case .label: return label
        }
    }
}

/// The popover chrome: elevated slate, a small title, dark, accent tint, a popover on iPhone too.
private struct PopoverChrome: ViewModifier {
    var width: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: width)
            .background(Theme.surface)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .presentationBackground(Theme.surface)
            .presentationCompactAdaptation(.popover)
    }
}

extension View {
    fileprivate func popoverChrome(width: CGFloat = 300) -> some View { modifier(PopoverChrome(width: width)) }
}

// MARK: - Date

/// Today, Tomorrow, This weekend, Next week, No date, then a month calendar; optionally a repeat menu.
/// The Deadline chip uses it too, with `title: "Deadline"` and `clearTitle: "No deadline"`.
struct DateChipPopover: View {
    var selected: Date?
    var now = Date()
    var onPick: (Date?) -> Void
    var recurrence: RecurrenceRule?
    var onRepeat: ((RecurrenceRule?) -> Void)?
    /// Shown above the presets when set ("Deadline").
    var title: String?
    var clearTitle = "No date"

    @State private var calendarDay: Date

    init(selected: Date?, now: Date = Date(), title: String? = nil, clearTitle: String = "No date",
         onPick: @escaping (Date?) -> Void,
         recurrence: RecurrenceRule? = nil, onRepeat: ((RecurrenceRule?) -> Void)? = nil) {
        self.selected = selected
        self.now = now
        self.title = title
        self.clearTitle = clearTitle
        self.onPick = onPick
        self.recurrence = recurrence
        self.onRepeat = onRepeat
        _calendarDay = State(initialValue: selected ?? now)
    }

    private var parser: DateExpressionParser { DateExpressionParser(now: now) }

    private struct Preset: Identifiable {
        let id: String
        let symbol: String
        let tint: Color
        let date: Date?
    }

    private var presets: [Preset] {
        let p = parser
        let weekend = p.spanWeekend().start
        var list = [
            Preset(id: "Today", symbol: "star", tint: PopoutTint.today, date: p.today),
            Preset(id: "Tomorrow", symbol: "sunrise", tint: PopoutTint.tomorrow, date: p.day(1)),
        ]
        if weekend > p.day(1) { list.append(Preset(id: "This weekend", symbol: "sofa", tint: Theme.accent, date: weekend)) }
        list.append(Preset(id: "Next week", symbol: "arrow.right.circle", tint: PopoutTint.later,
                           date: p.day(7, from: p.startOfWeek(containing: now))))
        if selected != nil { list.append(Preset(id: clearTitle, symbol: "circle.slash", tint: Theme.secondaryText, date: nil)) }
        return list
    }

    private func isPicked(_ preset: Preset) -> Bool {
        guard let date = preset.date, let selected else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).font(HITType.sectionHeader).foregroundStyle(Theme.secondaryText)
                    .padding([.horizontal, .top], HITSpacing.m)
            }
            HITChipRow {
                ForEach(presets) { preset in
                    HITChip(preset.id, systemImage: preset.symbol, tint: preset.tint, isSelected: isPicked(preset),
                            action: { onPick(preset.date) })
                        .help(preset.date.map { $0.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) } ?? clearTitle)
                }
            }
            .padding(HITSpacing.m)
            Rectangle().fill(Theme.separator).frame(height: 1)
            DatePicker(title ?? "Due date", selection: $calendarDay, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, HITSpacing.m)
                .padding(.vertical, HITSpacing.s)
                .onChange(of: calendarDay) { _, day in onPick(Calendar.current.startOfDay(for: day)) }
            if let onRepeat {
                Rectangle().fill(Theme.separator).frame(height: 1)
                RepeatMenu(rule: recurrence, onPick: onRepeat)
                    .padding(HITSpacing.m)
            }
        }
        .popoverChrome(width: 320)
    }
}

// MARK: - Repeat

/// The repeat presets offered everywhere.
enum RepeatPresets {
    static let all: [(title: String, rule: RecurrenceRule)] = [
        ("Every day", .daily),
        ("Every weekday", .weekdays),
        ("Every week", .weekly),
        ("Every 2 weeks", RecurrenceRule(frequency: .weekly, interval: 2)),
        ("Every month", .monthly),
        ("Every 3 months", RecurrenceRule(frequency: .monthly, interval: 3)),
        ("Every year", .yearly),
    ]
}

/// A chip-styled menu of repeat presets, for the date popover.
struct RepeatMenu: View {
    var rule: RecurrenceRule?
    var onPick: (RecurrenceRule?) -> Void

    var body: some View {
        Menu {
            ForEach(RepeatPresets.all, id: \.title) { preset in
                Button(preset.title) { onPick(preset.rule) }
            }
            if rule != nil {
                Divider()
                Button("Don’t repeat", role: .destructive) { onPick(nil) }
            }
        } label: {
            HITChipLabel(rule?.displayText ?? "Repeat", systemImage: "repeat", tint: PopoutTint.today, isSelected: rule != nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The repeat presets as rows, for the task popout's Repeat chip.
struct RepeatChipPopover: View {
    var rule: RecurrenceRule?
    var onPick: (RecurrenceRule?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(RepeatPresets.all, id: \.title) { preset in
                HITMenuRow(preset.title, systemImage: preset.rule == rule ? "checkmark" : "repeat",
                           iconTint: preset.rule == rule ? Theme.accent : Theme.secondaryText, accessory: .none) {
                    onPick(preset.rule)
                }
            }
            if let rule, !RepeatPresets.all.contains(where: { $0.rule == rule }) {
                HITMenuRow(rule.displayText, systemImage: "checkmark", iconTint: Theme.accent, accessory: .none) { onPick(rule) }
            }
            if rule != nil {
                Rectangle().fill(Theme.separator).frame(height: 1)
                HITMenuRow("Don’t repeat", systemImage: "xmark", role: .destructive, accessory: .none) { onPick(nil) }
            }
        }
        .padding(.vertical, HITSpacing.xs)
        .popoverChrome(width: 260)
    }
}

// MARK: - Priority

struct PriorityChipPopover: View {
    @State var selection: Priority
    var onPick: (Priority) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            Text("Priority").font(HITType.sectionHeader).foregroundStyle(Theme.secondaryText)
            HITSegmented(selection: $selection, segments: Priority.allCases.map {
                HITSegment($0, "P\($0.rawValue)", systemImage: $0.symbol, tint: $0.color)
            })
        }
        .padding(HITSpacing.m)
        .onChange(of: selection) { _, picked in onPick(picked) }
        .popoverChrome(width: 280)
    }
}

// MARK: - Reminder (the due time)

/// A task reminds at its due time, so the reminder is the time of day: presets, or type one.
struct ReminderChipPopover: View {
    var hour: Int?
    var minute: Int?
    var onPick: (_ hour: Int, _ minute: Int) -> Void
    var onClear: () -> Void

    @State private var typed = ""
    @State private var invalid = false

    private static let presets: [(String, Int, Int)] = [("9:00 AM", 9, 0), ("12:00 PM", 12, 0), ("5:00 PM", 17, 0), ("8:00 PM", 20, 0)]

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            Text("Remind me at").font(HITType.sectionHeader).foregroundStyle(Theme.secondaryText)
            HITChipRow {
                ForEach(Self.presets, id: \.0) { preset in
                    HITChip(preset.0, systemImage: "alarm", tint: Theme.accent,
                            isSelected: hour == preset.1 && minute == preset.2, action: { onPick(preset.1, preset.2) })
                }
            }
            HITField("Other time, e.g. 6:30pm", text: $typed, systemImage: "clock", isInvalid: invalid)
                .onSubmit(submitTyped)
                .onChange(of: typed) { _, _ in invalid = false }
            if hour != nil {
                Button("No reminder", role: .destructive, action: onClear)
                    .buttonStyle(HITButtonStyle(.destructive, size: .small))
            }
            Text("Reminders arrive at the task’s time when notifications are on in Settings.")
                .font(HITType.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HITSpacing.m)
        .popoverChrome(width: 300)
    }

    private func submitTyped() {
        let words = typed.lowercased().split(separator: " ").map(String.init)
        guard let time = DateExpressionParser().matchTime(in: words, at: 0) ?? DateExpressionParser().matchTime(in: ["at"] + words, at: 0) else {
            invalid = true
            return
        }
        onPick(time.hour, time.minute)
    }
}

// MARK: - Project

/// Inbox and the projects, filtered by a search field; picking closes it.
struct ProjectChipPopover: View {
    var projects: [Project]
    /// Nil is the Inbox.
    var selectedName: String?
    var onPick: (Project?) -> Void

    @State private var search = ""

    private var matches: [Project] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? projects : projects.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HITField("Search groups", text: $search, systemImage: "magnifyingglass", clearable: true)
                .padding(HITSpacing.m)
            ScrollView {
                VStack(spacing: 0) {
                    if search.isEmpty || "inbox".contains(search.lowercased()) {
                        HITMenuRow("Inbox", systemImage: "tray", iconTint: Theme.accent,
                                   value: selectedName == nil ? "✓" : nil, accessory: .none) { onPick(nil) }
                    }
                    ForEach(matches) { project in
                        let isSelected = selectedName?.caseInsensitiveCompare(project.name) == .orderedSame
                        HITMenuRow(project.name, systemImage: "number", iconTint: Color(hex: project.colorHex),
                                   value: isSelected ? "✓" : nil, accessory: .none) { onPick(project) }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(.bottom, HITSpacing.xs)
        .popoverChrome(width: 280)
    }
}

// MARK: - Labels

/// Every label with a check, filtered by a search field that can also create one. Stays open.
struct LabelsChipPopover: View {
    var labels: [TaskLabel]
    var selected: [String]
    var onToggle: (String) -> Void

    @State private var search = ""

    private func isSelected(_ name: String) -> Bool {
        selected.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private var query: String {
        search.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    private var matches: [TaskLabel] {
        query.isEmpty ? labels : labels.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Selected names that aren't labels yet (typed in quick add; created on save).
    private var pending: [String] {
        selected.filter { name in !labels.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HITField("Search or create a label", text: $search, systemImage: "tag", clearable: true)
                .onSubmit(createTyped)
                .padding(HITSpacing.m)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(pending, id: \.self) { name in
                        row(name, color: PopoutTint.label)
                    }
                    ForEach(matches) { label in
                        row(label.name, color: Color(hex: label.colorHex))
                    }
                    if !query.isEmpty, !labels.contains(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame }) {
                        HITMenuRow("Create “@\(query)”", systemImage: "plus", iconTint: Theme.accent, accessory: .none) {
                            createTyped()
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(.bottom, HITSpacing.xs)
        .popoverChrome(width: 280)
    }

    private func row(_ name: String, color: Color) -> some View {
        HITMenuRow("@" + name, systemImage: isSelected(name) ? "checkmark.square.fill" : "square",
                   iconTint: isSelected(name) ? color : Theme.secondaryText, accessory: .none) {
            onToggle(name)
        }
    }

    private func createTyped() {
        let name = query
        guard !name.isEmpty else { return }
        if !isSelected(name) { onToggle(labels.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.name ?? name) }
        search = ""
    }
}
