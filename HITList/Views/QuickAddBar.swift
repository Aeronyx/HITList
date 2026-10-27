import SwiftUI
import SwiftData
import HITListCore

/// Natural-language task entry with live token chips, autocomplete, and attribute autofill.
struct QuickAddBar: View {
    var defaultProject: Project?
    var defaultLabel: TaskLabel?

    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]

    @State private var text = ""
    @State private var engine: AutocompleteEngine?
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var parser: QuickAddParser {
        QuickAddParser(knownProjects: projects.map(\.name), knownLabels: labels.map(\.name))
    }
    private var parsed: QuickAddResult { parser.parse(text) }

    private var currentEngine: AutocompleteEngine {
        engine ?? AutocompleteEngine(tasks: allTasks, projects: projects.map(\.name), labels: labels.map(\.name))
    }

    private var suggestions: [AutocompleteEngine.Suggestion] {
        guard !text.isEmpty else { return [] }
        return currentEngine.suggestions(for: text)
    }

    private var autofill: AutocompleteEngine.AttributeSuggestion? {
        let p = parsed
        guard p.title.count >= 3 else { return nil }
        guard var s = currentEngine.attributeSuggestion(forTitle: p.title) else { return nil }
        if p.projectName != nil || defaultProject != nil { s.projectName = nil }
        s.labelNames.removeAll { name in p.labelNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        if p.priority != .p4 { s.priority = nil }
        return s.isEmpty ? nil : s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor).font(.title2)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
                    #if os(iOS)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    #endif
                if !text.isEmpty {
                    Button(action: add) { Image(systemName: "return") }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            if !text.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        tokenChips
                        if let autofill {
                            Divider().frame(height: 16)
                            autofillChips(autofill)
                        }
                    }
                }
                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(suggestions, id: \.replacement) { s in
                                Button { apply(s) } label: {
                                    Label(s.text, systemImage: icon(for: s.kind))
                                        .font(.caption)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(.quaternary, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { rebuildEngine() }
        .onChange(of: allTasks.count) { _, _ in rebuildEngine() }
        .onChange(of: projects.count) { _, _ in rebuildEngine() }
        .onChange(of: labels.count) { _, _ in rebuildEngine() }
        .onReceive(NotificationCenter.default.publisher(for: .focusQuickAdd)) { _ in focused = true }
    }

    private var placeholder: String {
        if let p = defaultProject { return "Add to \(p.name)… e.g. Draft plan fri 3pm p2" }
        if let l = defaultLabel { return "Add @\(l.name) task… e.g. Reply to Sam tomorrow" }
        return "Add a task… e.g. Call mom tomorrow 5pm p2 #Family"
    }

    @ViewBuilder
    private var tokenChips: some View {
        let p = parsed
        if let due = p.dueDate {
            chip(DueFormatter.text(for: due, hasTime: p.hasDueTime), "calendar", .blue)
        }
        if let r = p.recurrence { chip(r.displayText, "repeat", .teal) }
        if p.priority != .p4 { chip(p.priority.shortName, "flag.fill", p.priority.color) }
        if let name = p.projectName {
            let known = projects.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            chip(known ? "#\(name)" : "#\(name) (new)", "number", known ? .purple : .orange)
        } else if let d = defaultProject {
            chip("#\(d.name)", "number", Color(hex: d.colorHex).opacity(0.8))
        }
        ForEach(p.labelNames, id: \.self) { chip("@\($0)", "tag", .gray) }
    }

    @ViewBuilder
    private func autofillChips(_ s: AutocompleteEngine.AttributeSuggestion) -> some View {
        Image(systemName: "sparkles").font(.caption).foregroundStyle(.secondary)
        if let p = s.projectName {
            Button { append(p.contains(" ") ? "#\"\(p)\"" : "#\(p)") } label: { chip("#\(p)", "plus", .purple) }.buttonStyle(.plain)
        }
        ForEach(s.labelNames, id: \.self) { l in
            Button { append("@\(l)") } label: { chip("@\(l)", "plus", .gray) }.buttonStyle(.plain)
        }
        if let pr = s.priority {
            Button { append(pr.shortName.lowercased()) } label: { chip(pr.shortName, "plus", pr.color) }.buttonStyle(.plain)
        }
    }

    private func chip(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func icon(for kind: AutocompleteEngine.Suggestion.Kind) -> String {
        switch kind {
        case .title: return "clock.arrow.circlepath"
        case .project: return "number"
        case .label: return "tag"
        case .keyword: return "calendar"
        }
    }

    private func apply(_ s: AutocompleteEngine.Suggestion) {
        if s.kind == .title {
            text = s.replacement + " "
        } else if let lastSpace = text.lastIndex(where: { $0.isWhitespace }) {
            text = String(text[...lastSpace]) + s.replacement + " "
        } else {
            text = s.replacement + " "
        }
        focused = true
    }

    private func append(_ token: String) {
        text = text.trimmingCharacters(in: .whitespaces) + " " + token + " "
        focused = true
    }

    private func rebuildEngine() {
        engine = AutocompleteEngine(tasks: allTasks, projects: projects.map(\.name), labels: labels.map(\.name))
    }

    private func add() {
        let result = parsed
        do {
            try TaskActions.create(from: result, defaultProject: defaultProject, defaultLabel: defaultLabel, in: context)
            text = ""
            errorMessage = nil
            focused = true
            Task { await NotificationScheduler.reschedule(context: context) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
