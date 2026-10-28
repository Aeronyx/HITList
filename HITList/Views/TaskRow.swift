import SwiftUI
import SwiftData
import HITListCore

struct TaskRow: View {
    @Bindable var task: TaskItem
    var now: Date
    var showProject: Bool = true
    /// Set while the list animates this row's completion (see `CompletionAnimator`).
    var completionPhase: CompletionPhase? = nil
    /// Completes or un-completes the task; the list owns this so it can animate the row out.
    var onToggleCompletion: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pops = 0

    /// A recurring task never becomes completed (its date advances), so the row also counts as checked
    /// while its completion animates.
    private var isChecked: Bool { task.isCompleted || completionPhase != nil }

    private var checkColor: Color {
        if completionPhase != nil { return task.priorityValue == .p4 ? Theme.accent : task.priorityValue.color }
        return task.isCompleted ? Color.secondary : task.priorityValue.color
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                if !isChecked && !reduceMotion { pops += 1 }
                onToggleCompletion()
            } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checkColor)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .keyframeAnimator(initialValue: 1.0, trigger: pops) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.15, duration: 0.1, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.15, spring: .smooth)
                    }
                    .animation(.easeOut(duration: 0.15), value: isChecked)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isChecked ? "Mark incomplete" : "Complete task")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                    .lineLimit(2)
                    .overlay { strikeLine }
                    .animation(.easeOut(duration: 0.2), value: isChecked)
                HStack(spacing: 8) {
                    if let due = task.dueDate {
                        let overdue = DueFormatter.isOverdue(due, hasTime: task.hasDueTime, isCompleted: task.isCompleted, now: now)
                        Label(DueFormatter.text(for: due, hasTime: task.hasDueTime, now: now),
                              systemImage: task.recurrence == nil ? "calendar" : "repeat")
                            .foregroundStyle(overdue ? .red : .secondary)
                    }
                    if showProject, let project = task.project {
                        Label(project.name, systemImage: "circle.fill")
                            .foregroundStyle(Color(hex: project.colorHex))
                    }
                    ForEach(task.labelList) { label in
                        Text("@" + label.name).foregroundStyle(Color(hex: label.colorHex))
                    }
                    if !task.notes.isEmpty { Image(systemName: "note.text").foregroundStyle(.secondary) }
                }
                .font(.caption)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if task.priorityValue != .p4 {
                Text(task.priorityValue.shortName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(task.priorityValue.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(task.priorityValue.color)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Menu("Priority") {
                ForEach(Priority.allCases, id: \.self) { p in
                    Button {
                        task.priorityValue = p; task.touch(); try? context.save()
                    } label: { Label(p.displayName, systemImage: p.symbol) }
                }
            }
            Menu("Reschedule") {
                Button("Today") { TaskActions.reschedule(task, to: Calendar.current.startOfDay(for: now), in: context) }
                Button("Tomorrow") { TaskActions.reschedule(task, to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)), in: context) }
                Button("Next Week") {
                    let p = DateExpressionParser(now: now)
                    TaskActions.reschedule(task, to: p.day(7, from: p.startOfWeek(containing: now)), in: context)
                }
                Button("Remove Date") { TaskActions.reschedule(task, to: nil, in: context) }
            }
            Divider()
            Button(role: .destructive) { TaskActions.delete(task, in: context) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// The title's strike-through, drawn on its own so it can sweep left to right when the task is
    /// completed (a mask over a copy of the title with clear glyphs). It fades out when un-completed,
    /// and only cross-fades with Reduce Motion on.
    private var strikeLine: some View {
        Text(task.title)
            .lineLimit(2)
            .foregroundStyle(.clear)
            .strikethrough(color: .secondary)
            .mask(alignment: .leading) {
                Rectangle().scaleEffect(x: isChecked || reduceMotion ? 1 : 0, y: 1, anchor: .leading)
            }
            // Sweep in; on un-complete, reset only after the fade below has hidden the line.
            .animation(reduceMotion ? nil : isChecked ? .easeOut(duration: 0.2) : .linear(duration: 0).delay(0.2), value: isChecked)
            .opacity(isChecked ? 1 : 0)
            .animation(isChecked && !reduceMotion ? nil : .easeOut(duration: 0.2), value: isChecked)
            .accessibilityHidden(true)
    }
}
