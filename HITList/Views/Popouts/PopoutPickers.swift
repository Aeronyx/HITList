import SwiftUI
import HITListCore

// The cards behind the popouts' chips, shared by the quick-add card and the task popout. Each one
// reports a pick through a closure and leaves storing it to the caller. `pickerAnchor` (Pickers/)
// presents them: inside the window on the Mac, as popovers on iPhone and iPad; it sets the width.

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

// The Date and Deadline card is `DatePickerCard`, the Reminder card `ReminderPickerCard` (Pickers/).

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
    }
}

// MARK: - Reminder (the due time, and how long before it)

/// What the Reminder chip reads: "11:00 AM", "11:00 AM · 15 min before", "15 min before" (an offset
/// still waiting for a time), or "Reminder".
enum ReminderChipText {
    static func title(time: Date?, offsetMinutes: Int?) -> String {
        let offset = (offsetMinutes ?? 0) > 0 ? ReminderOffset.label(minutes: offsetMinutes!) : nil
        guard let time else { return offset ?? "Reminder" }
        let clock = time.formatted(date: .omitted, time: .shortened)
        return offset.map { "\(clock) · \($0)" } ?? clock
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

// MARK: - Location

/// Where the task happens, as plain text (no geofencing). Return or Done keeps it; closing the popover
/// keeps what was typed too; Remove clears it.
struct LocationChipPopover: View {
    var name: String?
    /// Nil removes the location.
    var onSave: (String?) -> Void

    @State private var text: String
    @State private var committed = false

    init(name: String?, onSave: @escaping (String?) -> Void) {
        self.name = name
        self.onSave = onSave
        _text = State(initialValue: name ?? "")
    }

    private var trimmed: String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            Text("Location").font(HITType.sectionHeader).foregroundStyle(Theme.secondaryText)
            HITField("Where, e.g. Main St Barbers", text: $text, systemImage: "mappin.and.ellipse", clearable: true, autofocus: true)
                .onSubmit { commit(trimmed) }
                .accessibilityIdentifier("locationField")
            HStack {
                if name != nil {
                    Button("Remove", role: .destructive) { commit(nil) }
                        .buttonStyle(HITButtonStyle(.destructive, size: .small))
                }
                Spacer()
                Button("Done") { commit(trimmed) }
                    .buttonStyle(HITButtonStyle(.primary, size: .small))
            }
        }
        .padding(HITSpacing.m)
        .onDisappear {
            // Tapping outside keeps what was typed.
            if !committed, trimmed != name { onSave(trimmed) }
        }
    }

    private func commit(_ value: String?) {
        committed = true
        onSave(value)
    }
}
