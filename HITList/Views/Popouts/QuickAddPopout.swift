import SwiftUI
import SwiftData
import HITListCore

/// The quick-add card, the same everywhere: docked above the keyboard on iPhone, a panel near the top
/// of the window on the Mac, or expanded in place of a list's "Add task" row.
///
/// Type naturally ("Call mom tomorrow 5pm #Family @calls p2"); tokens light up and the chips follow.
/// Tapping a chip writes its token into the text. Return adds the task and keeps the card open, empty,
/// for the next one; Escape or × closes it.
struct QuickAddPopout: View {
    enum Style { case floating, inline }

    let context: QuickAddContext
    var style: Style = .floating
    var onClose: () -> Void
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]

    @State private var draft: QuickAddDraft
    @State private var engine: AutocompleteEngine?
    @State private var openChip: Chip?
    @State private var errorMessage: String?
    @State private var added: String?
    @State private var addedGeneration = 0
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    enum Chip: Hashable { case date, priority, reminder, project, labels }

    init(context: QuickAddContext, style: Style = .floating, onClose: @escaping () -> Void, onSaved: @escaping () -> Void = {}) {
        self.context = context
        self.style = style
        self.onClose = onClose
        self.onSaved = onSaved
        _draft = State(initialValue: QuickAddDraft(context: context))
    }

    private var parser: QuickAddParser {
        QuickAddParser(knownProjects: projects.map(\.name), knownLabels: labels.map(\.name))
    }

    var body: some View {
        let parser = parser
        let parsed = parser.parse(draft.text)
        let chips = draft.chips(parser)
        VStack(alignment: .leading, spacing: HITSpacing.s + 2) {
            TokenHighlightField(placeholder: placeholder, text: $draft.text, tokens: parsed.tokens,
                                priority: parsed.priority, focus: $titleFocused, onSubmit: save)
            if draft.showsNotes {
                HITField("Description", text: $draft.notes, axis: .vertical, lineLimit: 1...5)
                    .focused($notesFocused)
                    .transition(.opacity)
            }
            suggestionRow(parsed)
            chipRow(chips, parser: parser)
            if let errorMessage {
                Text(errorMessage).font(HITType.caption).foregroundStyle(HITColor.danger)
            }
            Rectangle().fill(Theme.separator).frame(height: 1)
            footer(chips)
        }
        .padding(HITSpacing.l)
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: draft.showsNotes)
        .onAppear {
            rebuildEngine()
            titleFocused = true
        }
        .onChange(of: allTasks.count) { _, _ in rebuildEngine() }
        .onChange(of: projects.count) { _, _ in rebuildEngine() }
        .onChange(of: labels.count) { _, _ in rebuildEngine() }
        .onChange(of: openChip) { _, chip in
            // iPhone: the keyboard steps aside while a chip's popover needs the room, then comes back.
            #if os(iOS)
            if chip != nil { titleFocused = false; notesFocused = false } else { titleFocused = true }
            #endif
        }
        #if os(macOS)
        .onExitCommand(perform: onClose)
        #endif
    }

    private var placeholder: String {
        switch context {
        case .project(let name): return "Add to \(name)… e.g. Draft plan fri 3pm p2"
        case .label(let name): return "Add @\(name) task… e.g. Reply to Sam tomorrow"
        case .day(let day): return "Task for \(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        default: return "Task name, e.g. Call mom tomorrow 5pm #Family p2"
        }
    }

    // MARK: Suggestions

    private var currentEngine: AutocompleteEngine {
        engine ?? AutocompleteEngine(tasks: allTasks, projects: projects.map(\.name), labels: labels.map(\.name))
    }

    /// Autocomplete for the word being typed, then "you usually add these" attributes for the title.
    @ViewBuilder
    private func suggestionRow(_ parsed: QuickAddResult) -> some View {
        let suggestions = draft.text.isEmpty ? [] : currentEngine.suggestions(for: draft.text, limit: 5)
        let autofill = autofill(parsed)
        if !suggestions.isEmpty || autofill != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HITSpacing.xs + 2) {
                    ForEach(suggestions, id: \.replacement) { s in
                        Button { draft.apply(s); titleFocused = true } label: {
                            Label(s.text, systemImage: icon(for: s.kind)).lineLimit(1)
                        }
                        .buttonStyle(SuggestionStyle())
                    }
                    if let autofill {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(Theme.secondaryText)
                        if let p = autofill.projectName {
                            Button("#\(p)") { appendToken(QuickAddTokens.project(p)) }.buttonStyle(SuggestionStyle())
                        }
                        ForEach(autofill.labelNames, id: \.self) { l in
                            Button("@\(l)") { appendToken(QuickAddTokens.label(l)) }.buttonStyle(SuggestionStyle())
                        }
                        if let pr = autofill.priority {
                            Button(pr.shortName) { appendToken(QuickAddTokens.priority(pr)) }.buttonStyle(SuggestionStyle())
                        }
                    }
                }
            }
            .frame(height: 24)
            .transition(.opacity)
        }
    }

    private func autofill(_ parsed: QuickAddResult) -> AutocompleteEngine.AttributeSuggestion? {
        guard parsed.title.count >= 3, var s = currentEngine.attributeSuggestion(forTitle: parsed.title) else { return nil }
        if parsed.projectName != nil || context.defaultProjectName != nil { s.projectName = nil }
        s.labelNames.removeAll { name in parsed.labelNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        if parsed.priority != .p4 { s.priority = nil }
        return s.isEmpty ? nil : s
    }

    private func icon(for kind: AutocompleteEngine.Suggestion.Kind) -> String {
        switch kind {
        case .title: return "clock.arrow.circlepath"
        case .project: return "number"
        case .label: return "tag"
        case .keyword: return "calendar"
        }
    }

    private func appendToken(_ token: String) {
        draft.text = QuickAddDraft.appending(token, to: draft.text)
        titleFocused = true
    }

    private func rebuildEngine() {
        engine = AutocompleteEngine(tasks: allTasks, projects: projects.map(\.name), labels: labels.map(\.name))
    }

    // MARK: Chips

    private func chipBinding(_ chip: Chip) -> Binding<Bool> {
        Binding(get: { openChip == chip }, set: { if !$0, openChip == chip { openChip = nil } })
    }

    @ViewBuilder
    private func chipRow(_ chips: QuickAddChips, parser: QuickAddParser) -> some View {
        let now = parser.dateParser.now
        HITChipRow {
            HITChip(chips.dueDate.map { DueFormatter.text(for: $0, hasTime: false, now: now) } ?? "Date",
                    systemImage: chips.recurrence == nil ? "calendar" : "repeat",
                    tint: chips.dueDate == nil ? Theme.secondaryText : PopoutTint.date(chips.dueDate, now: now),
                    isSelected: chips.dueDate != nil, action: { openChip = .date })
                .popover(isPresented: chipBinding(.date)) {
                    DateChipPopover(selected: chips.dueDate, now: now, onPick: { day in
                        draft.setDate(day, parser)
                        openChip = nil
                        titleFocused = true
                    }, recurrence: chips.recurrence, onRepeat: { rule in
                        draft.setRecurrence(rule, parser)
                        openChip = nil
                        titleFocused = true
                    })
                }

            HITChip(chips.priority == .p4 ? "Priority" : chips.priority.shortName, systemImage: chips.priority.symbol,
                    tint: chips.priority == .p4 ? Theme.secondaryText : chips.priority.color,
                    isSelected: chips.priority != .p4, action: { openChip = .priority })
                .popover(isPresented: chipBinding(.priority)) {
                    PriorityChipPopover(selection: chips.priority) { p in
                        draft.setPriority(p, parser)
                        openChip = nil
                        titleFocused = true
                    }
                }

            HITChip(chips.hasDueTime ? (chips.dueDate?.formatted(date: .omitted, time: .shortened) ?? "Reminder") : "Reminder",
                    systemImage: "alarm", tint: chips.hasDueTime ? Theme.accent : Theme.secondaryText,
                    isSelected: chips.hasDueTime, action: { openChip = .reminder })
                .popover(isPresented: chipBinding(.reminder)) {
                    let parts = chips.dueDate.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
                    ReminderChipPopover(hour: chips.hasDueTime ? parts?.hour : nil, minute: chips.hasDueTime ? parts?.minute : nil,
                                        onPick: { h, m in
                                            draft.setTime(hour: h, minute: m, parser)
                                            openChip = nil
                                            titleFocused = true
                                        }, onClear: {
                                            draft.clearTime(parser)
                                            openChip = nil
                                            titleFocused = true
                                        })
                }

            HITChip(chips.projectName ?? "Inbox", systemImage: chips.projectName == nil ? "tray" : "number",
                    tint: projectTint(chips.projectName), isSelected: chips.projectName != nil, action: { openChip = .project })
                .popover(isPresented: chipBinding(.project)) {
                    ProjectChipPopover(projects: projects, selectedName: chips.projectName) { project in
                        draft.setProject(project?.name, parser)
                        openChip = nil
                        titleFocused = true
                    }
                }

            HITChip(chips.labelNames.isEmpty ? "Labels" : chips.labelNames.map { "@" + $0 }.joined(separator: " "),
                    systemImage: "tag", tint: chips.labelNames.isEmpty ? Theme.secondaryText : PopoutTint.label,
                    isSelected: !chips.labelNames.isEmpty, action: { openChip = .labels })
                .popover(isPresented: chipBinding(.labels)) {
                    LabelsChipPopover(labels: labels, selected: chips.labelNames) { name in
                        draft.toggleLabel(name, parser)
                    }
                }

            if let rule = chips.recurrence {
                HITChip(rule.displayText, systemImage: "repeat", tint: PopoutTint.today, isSelected: true,
                        onDismiss: { draft.setRecurrence(nil, parser) }) { openChip = .date }
            }
        }
    }

    private func projectTint(_ name: String?) -> Color {
        guard let name else { return Theme.accent }
        return projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map { Color(hex: $0.colorHex) } ?? PopoutTint.project
    }

    // MARK: Footer

    private func footer(_ chips: QuickAddChips) -> some View {
        HStack(spacing: HITSpacing.s) {
            if !draft.showsNotes {
                Button {
                    draft.showsNotes = true
                    notesFocused = true
                } label: {
                    Label("Description", systemImage: "text.alignleft")
                }
                .buttonStyle(HITButtonStyle(.ghost, size: .small))
            }
            if let added {
                Label(added, systemImage: "checkmark.circle.fill")
                    .font(HITType.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .transition(.opacity)
            }
            Spacer(minLength: HITSpacing.s)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(HITButtonStyle(.ghost, size: .small, shape: .circle))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .help("Close (Esc)")
            Button(action: save) {
                Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(HITButtonStyle(.primary, shape: .circle))
            .disabled(draft.result(parser).title.isEmpty)
            .accessibilityLabel("Add task")
            .help("Add task (Return)")
        }
    }

    // MARK: Saving

    private func save() {
        let result = draft.result(parser)
        guard !result.title.isEmpty else { return }
        do {
            let task = try TaskActions.create(from: result, defaultProject: nil, defaultLabel: nil, in: modelContext)
            let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                task.notes = notes
                try? modelContext.save()
            }
            errorMessage = nil
            withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) {
                draft.reset()
                added = "Added ‘\(result.title)’"
            }
            addedGeneration += 1
            let generation = addedGeneration
            Task {
                try? await Task.sleep(for: .seconds(3))
                if generation == addedGeneration { withAnimation { added = nil } }
            }
            titleFocused = true
            onSaved()
            AccessibilityNotification.Announcement("Added \(result.title)").post()
            Task { await NotificationScheduler.reschedule(context: modelContext) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A thin suggestion pill above the chips.
private struct SuggestionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HITType.caption)
            .foregroundStyle(configuration.isPressed ? HITColor.text : Theme.secondaryText)
            .padding(.horizontal, HITSpacing.s)
            .frame(height: 22)
            .background(Capsule().fill(Theme.elevated))
            .contentShape(Capsule())
    }
}
