import SwiftUI
import SwiftData
import HITListCore

/// Brief 137: Settings → iCloud & data → "Import from Todoist…". The files picked are read and planned, and nothing is
/// written until the person has seen the plan here and pressed its one button. Then a backup, the import in batches,
/// a line saying what came in, and "Undo last import" on the rows above until the next import replaces the receipt.
@MainActor @Observable
final class TodoistImportModel {
    enum Phase: Equatable {
        case idle
        case preview
        case importing(done: Int, of: Int)
    }

    var phase: Phase = .idle
    var projects: [TodoistProject] = []
    var plan: TodoistPlan?
    var sectionsAsLabels = true
    var message: String?
    var receipt: TodoistImporter.Receipt? = TodoistImporter.loadReceipt()
    /// The fixture opens once per launch (`-todoistImportFixture`).
    static var fixtureShown = false

    /// The person's files: read, planned against the store, shown. Errors in plain words.
    func load(_ files: [TodoistFiles.File], context: ModelContext) {
        message = nil
        do {
            projects = try TodoistFiles.projects(from: files)
            try replan(context: context)
            guard let plan, !plan.isEmpty else {
                self.plan = nil
                phase = .idle
                message = "Nothing to import: the file has no tasks."
                return
            }
            phase = .preview
        } catch {
            plan = nil
            phase = .idle
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func replan(context: ModelContext) throws {
        plan = TodoistMapping.plan(projects, existing: try TodoistImporter.existing(in: context),
                                   options: TodoistImportOptions(sectionsAsLabels: sectionsAsLabels))
    }

    func cancel() {
        plan = nil
        projects = []
        phase = .idle
    }

    func run(context: ModelContext) async {
        guard let plan, plan.taskCount > 0 else { return }
        phase = .importing(done: 0, of: plan.taskCount)
        do {
            let receipt = try await TodoistImporter.run(plan, in: context) { [weak self] done in
                self?.phase = .importing(done: done, of: plan.taskCount)
            }
            self.receipt = receipt
            // As quick add does after it makes a task: reminders (and the badge) follow the store.
            Task { await NotificationScheduler.reschedule(context: context) }
            message = "Imported \(receipt.summary) from Todoist."
                + (plan.skipped.isEmpty ? "" : " \(TodoistMapping.count(plan.skipped.count, "task")) already here were skipped.")
        } catch {
            message = "Import stopped before anything was written: \(error.localizedDescription)"
        }
        self.plan = nil
        projects = []
        phase = .idle
    }

    func undo(context: ModelContext) {
        guard let receipt else { return }
        do {
            let undone = try TodoistImporter.undo(receipt, in: context)
            self.receipt = nil
            Task { await NotificationScheduler.reschedule(context: context) }
            var parts = [TodoistMapping.count(undone.tasks, "task")]
            if undone.groups > 0 { parts.append(TodoistMapping.count(undone.groups, "Group")) }
            if undone.labels > 0 { parts.append(TodoistMapping.count(undone.labels, "label")) }
            message = "Removed \(parts.joined(separator: ", ")) from the last import."
                + (undone.kept > 0 ? " \(undone.kept) that now hold something of yours stayed." : "")
            // A preview still open was planned against the tasks just removed.
            if plan != nil { try? replan(context: context) }
        } catch {
            message = "Undo failed: \(error.localizedDescription)"
        }
    }

    /// The question before undo, naming the counts.
    var undoQuestion: String {
        guard let receipt else { return "" }
        return "The import of \(receipt.date.formatted(date: .abbreviated, time: .shortened)) made \(receipt.summary). "
            + "They are removed, even ones changed since. A Group or label that now holds something of yours stays."
    }
}

/// The preview: each project and where it goes, what will be made, what is skipped or not understood, the one switch,
/// and the one button.
struct TodoistImportCard: View {
    @Bindable var model: TodoistImportModel
    let plan: TodoistPlan
    @Environment(\.modelContext) private var context
    @State private var showUnread = false

    var body: some View {
        HITGroup("Import from Todoist", footer: plan.choices.joined(separator: " ")) {
            ForEach(plan.projects) { project in
                HITMenuRow(project.name, subtitle: Self.destination(project.destination), systemImage: "folder",
                           value: TodoistMapping.count(project.taskCount, "task"))
            }
            HITMenuRow("Tasks", systemImage: "checkmark.circle", value: "\(plan.taskCount)")
                .accessibilityIdentifier("todoist-preview-tasks")
            if plan.checklistLineCount > 0 {
                HITMenuRow("Checklist lines", systemImage: "checklist", value: "\(plan.checklistLineCount)")
            }
            if plan.subtasksAsTasks > 0 {
                HITMenuRow("Sub-tasks made tasks", systemImage: "arrow.turn.down.right", value: "\(plan.subtasksAsTasks)")
            }
            if !plan.labelsToMake.isEmpty {
                HITMenuRow("Labels to make", systemImage: "tag", value: plan.labelsToMake.joined(separator: ", "))
            }
            if plan.repeatingCount > 0 {
                HITMenuRow("Repeating", systemImage: "repeat", value: "\(plan.repeatingCount)")
            }
            if !plan.unreadDates.isEmpty {
                HITMenuRow("Dates not understood", systemImage: "calendar.badge.exclamationmark",
                           value: "\(plan.unreadDates.count)", accessory: .expand(isExpanded: showUnread)) { showUnread.toggle() }
                    .accessibilityIdentifier("todoist-preview-unread")
                if showUnread {
                    SettingsNote(text: plan.unreadDates.map { "\($0.title): “\($0.unreadDate ?? "")”" }.joined(separator: "\n")
                                 + "\nThey come in without a date; the words are the first line of their notes.")
                }
            }
            if !plan.skipped.isEmpty {
                HITMenuRow("Already in HITList (skipped)", systemImage: "equal.circle", value: "\(plan.skipped.count)")
                    .accessibilityIdentifier("todoist-preview-skipped")
            }
            Toggle(isOn: Binding(get: { model.sectionsAsLabels }, set: { on in
                model.sectionsAsLabels = on
                try? model.replan(context: context)
            })) {
                HITMenuRowLabel("Keep sections as labels", subtitle: "Off: the section's name goes in each task's notes", systemImage: "square.stack")
            }
            .toggleStyle(.hit)
            .hitRowPadding()
            buttons
        }
        .accessibilityIdentifier("todoist-preview")
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: HITSpacing.s) {
            if case .importing(let done, let total) = model.phase {
                Text("Importing… \(done) of \(total)")
                    .font(HITType.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .contentTransition(.numericText(value: Double(done)))
                Spacer(minLength: 0)
            } else {
                Button("Cancel") { model.cancel() }
                    .buttonStyle(HITButtonStyle(.secondary))
                Spacer(minLength: 0)
                Button(plan.taskCount == 0 ? "Nothing new to import" : "Import \(TodoistMapping.count(plan.taskCount, "task"))") {
                    Task { await model.run(context: context) }
                }
                .buttonStyle(.hitPrimary)
                .disabled(plan.taskCount == 0)
                .accessibilityIdentifier("todoist-import-confirm")
            }
        }
        .hitRowPadding()
    }

    static func destination(_ destination: TodoistPlan.Destination) -> String {
        switch destination {
        case .inbox: "Your Inbox"
        case .newGroup: "New Group"
        case .existingGroup(let name): "Your Group \(name)"
        }
    }
}
