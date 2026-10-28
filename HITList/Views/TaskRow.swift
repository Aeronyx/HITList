import SwiftUI
import SwiftData
import HITListCore

struct TaskRow: View {
    @Bindable var task: TaskItem
    var now: Date
    var showProject: Bool = true
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                let completing = !task.isCompleted
                withAnimation(.snappy) { TaskActions.toggleCompletion(task, in: context) }
                if completing { CompletionFeedback.shared.taskCompleted() }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? Color.secondary : task.priorityValue.color)
                    .symbolEffect(.bounce, value: task.isCompleted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Complete task")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
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
}
