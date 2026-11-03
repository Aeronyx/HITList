import SwiftUI
import SwiftData
import HITListCore

/// The editor's "Sub-tasks" section: a header with the progress ("2 of 5"), a chevron that folds the
/// list and a "+", then one card holding the checklist and its "Add Sub-task" row.
///
/// Ticking lands at once. Tapping a title renames it in place (Return or leaving the field lands it).
/// The "Add Sub-task" row turns into a field: Return adds and keeps it open for the next, an empty Return
/// closes it, and the editor's Confirm adds what is left in it. Long-press (right-click) for Move Up,
/// Move Down and Delete; drag a sub-task onto another to reorder.
struct SubtaskChecklist: View {
    let task: TaskItem
    @Binding var draft: TaskEditorDraft

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = true
    @State private var pops: [UUID: Int] = [:]
    @State private var dropTarget: UUID?
    /// Mac: the row under the pointer shows its ×.
    @State private var hoveredRow: UUID?
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case new
        case rename(UUID)
    }

    var body: some View {
        let subtasks = task.orderedSubtasks
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            header(progress: task.subtaskProgress)
            if isExpanded {
                EditorCard {
                    ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                        row(subtask, index: index, count: subtasks.count)
                        EditorHairline()
                    }
                    addRow
                }
                .transition(.opacity)
            }
        }
        .animation(HITMotion.standard(reduceMotion: reduceMotion), value: isExpanded)
        .onChange(of: focus) { old, new in
            // Leaving a title being renamed lands it (a close with × has already dropped the rename).
            if case .rename = old, new != old { draft.finishRenaming(in: context) }
        }
    }

    // MARK: Header

    private func header(progress: SubtaskProgress?) -> some View {
        HStack(spacing: HITSpacing.s) {
            Text("Sub-tasks")
                .font(HITType.headline)
                .foregroundStyle(HITColor.text)
            if let progress { SubtaskProgressBadge(progress: progress) }
            Spacer(minLength: HITSpacing.s)
            Button { isExpanded.toggle() } label: {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HITIconButtonStyle(font: .system(size: 14, weight: .semibold)))
            .accessibilityLabel(isExpanded ? "Hide sub-tasks" : "Show sub-tasks")
            Button(action: startAdding) {
                Image(systemName: "plus")
                    .frame(width: 32, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HITIconButtonStyle(font: .system(size: 16, weight: .semibold)))
            .accessibilityLabel("Add sub-task")
            .accessibilityIdentifier("subtasksPlus")
        }
        .padding(.leading, HITSpacing.xs)
    }

    // MARK: Rows

    private func row(_ subtask: TaskItem, index: Int, count: Int) -> some View {
        let isRenaming = draft.renaming?.id == subtask.id
        return HStack(alignment: .top, spacing: EditorMetrics.gap) {
            Button { toggle(subtask) } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: EditorMetrics.subtaskCheckSize))
                    .foregroundStyle(subtask.isCompleted ? Theme.accent : Theme.secondaryText)
                    .contentTransition(subtask.isCompleted && !reduceMotion ? .symbolEffect(.replace) : .opacity)
                    .hitCelebratePop(trigger: pops[subtask.id, default: 0])
                    .frame(width: EditorMetrics.iconColumn, height: EditorMetrics.subtaskLine)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.isCompleted ? "Mark \(subtask.title) not done" : "Tick \(subtask.title)")

            if isRenaming {
                TextField("Sub-task", text: renameText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(HITType.body)
                    .foregroundStyle(HITColor.text)
                    .lineLimit(1...4)
                    .frame(minHeight: EditorMetrics.subtaskLine, alignment: .leading)
                    .focused($focus, equals: .rename(subtask.id))
                    .onSubmit { focus = nil }
                    .accessibilityIdentifier("subtaskRename")
            } else {
                Text(subtask.title)
                    .font(HITType.body)
                    .foregroundStyle(subtask.isCompleted ? Theme.secondaryText : HITColor.text)
                    .strikethrough(subtask.isCompleted, color: Theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: EditorMetrics.subtaskLine, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { beginRenaming(subtask) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Rename")
            }
            #if os(macOS)
            SubtaskDeleteButton { delete(subtask) }
                .opacity(hoveredRow == subtask.id ? 1 : 0)
            #endif
        }
        .padding(.horizontal, EditorMetrics.inset)
        .padding(.vertical, (EditorMetrics.rowHeight - EditorMetrics.subtaskLine) / 2)
        .background(dropTarget == subtask.id ? Theme.elevated : .clear)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredRow = subtask.id } else if hoveredRow == subtask.id { hoveredRow = nil }
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { beginRenaming(subtask) }
            Button("Move Up", systemImage: "arrow.up") { move(subtask, to: index - 1) }
                .disabled(index == 0)
            Button("Move Down", systemImage: "arrow.down") { move(subtask, to: index + 1) }
                .disabled(index == count - 1)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { delete(subtask) }
        }
        .draggable(subtask.id.uuidString) {
            Text(subtask.title)
                .font(HITType.body)
                .padding(.horizontal, HITSpacing.m)
                .padding(.vertical, HITSpacing.s)
                .background(RoundedRectangle(cornerRadius: HITRadius.field).fill(Theme.elevated))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)),
                  let dragged = task.orderedSubtasks.first(where: { $0.id == id }) else { return false }
            move(dragged, to: index)
            return true
        } isTargeted: { targeted in
            if targeted { dropTarget = subtask.id } else if dropTarget == subtask.id { dropTarget = nil }
        }
        .accessibilityIdentifier("subtaskRow")
    }

    /// The "Add Sub-task" row, or the field it turns into.
    @ViewBuilder
    private var addRow: some View {
        if draft.isAddingSubtask {
            HStack(spacing: EditorMetrics.gap) {
                Image(systemName: "circle")
                    .font(.system(size: EditorMetrics.subtaskCheckSize))
                    .foregroundStyle(Theme.secondaryText.opacity(0.5))
                    .frame(width: EditorMetrics.iconColumn)
                TextField("Sub-task name", text: $draft.newSubtask)
                    .textFieldStyle(.plain)
                    .font(HITType.body)
                    .foregroundStyle(HITColor.text)
                    .focused($focus, equals: .new)
                    .onSubmit(submitNew)
                    .submitLabel(.next)
                    .accessibilityIdentifier("subtaskField")
            }
            .padding(.horizontal, EditorMetrics.inset)
            .frame(minHeight: EditorMetrics.rowHeight)
        } else {
            Button(action: startAdding) {
                HStack(spacing: EditorMetrics.gap) {
                    Image(systemName: "plus")
                        .font(.system(size: EditorMetrics.iconSize, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: EditorMetrics.iconColumn)
                    Text("Add Sub-task")
                        .font(HITType.body)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, EditorMetrics.inset)
                .frame(minHeight: EditorMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(EditorRowStyle())
            .accessibilityIdentifier("addSubtask")
        }
    }

    // MARK: Changes

    private var renameText: Binding<String> {
        Binding(get: { draft.renaming?.text ?? "" }, set: { text in
            guard draft.renaming != nil else { return }
            if text.contains(where: \.isNewline) {
                // Return finishes the rename instead of adding a line.
                draft.renaming?.text = TaskLimits.singleLine(text)
                focus = nil
            } else {
                draft.renaming?.text = text
            }
        })
    }

    private func startAdding() {
        if !isExpanded { isExpanded = true }
        draft.startAddingSubtask()
        Task { @MainActor in focus = .new }
    }

    private func submitNew() {
        let added = (try? draft.submitNewSubtask(to: task, in: context)) ?? false
        // iOS drops the keyboard on Return; the field stays open for the next one.
        if added { Task { @MainActor in focus = .new } }
    }

    private func beginRenaming(_ subtask: TaskItem) {
        if draft.renaming != nil { draft.finishRenaming(in: context) }
        draft.beginRenaming(subtask)
        Task { @MainActor in focus = .rename(subtask.id) }
    }

    private func toggle(_ subtask: TaskItem) {
        if !subtask.isCompleted {
            if !reduceMotion { pops[subtask.id, default: 0] += 1 }
            CompletionFeedback.shared.taskCompleted()
        }
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) {
            TaskActions.toggleCompletion(subtask, in: context)
        }
    }

    private func move(_ subtask: TaskItem, to index: Int) {
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) {
            TaskActions.moveSubtask(subtask, to: index, in: context)
        }
    }

    private func delete(_ subtask: TaskItem) {
        if draft.renaming?.id == subtask.id { draft.renaming = nil }
        withAnimation(HITMotion.standard(reduceMotion: reduceMotion)) {
            TaskActions.delete(subtask, in: context)
        }
    }
}

#if os(macOS)
/// The Mac's quiet × at the end of the sub-task under the pointer.
private struct SubtaskDeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .frame(width: 20, height: EditorMetrics.subtaskLine)
                .contentShape(Rectangle())
        }
        .buttonStyle(HITIconButtonStyle(font: .system(size: 10, weight: .bold)))
        .accessibilityLabel("Delete sub-task")
        .help("Delete")
    }
}
#endif
