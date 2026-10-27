import SwiftUI
import SwiftData
import HITListCore

struct TaskDetailView: View {
    @Bindable var task: TaskItem
    var onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskLabel.name) private var labels: [TaskLabel]
    @State private var confirmDelete = false

    private var hasDate: Binding<Bool> {
        Binding(
            get: { task.dueDate != nil },
            set: { on in
                task.dueDate = on ? Calendar.current.startOfDay(for: Date()) : nil
                if !on { task.hasDueTime = false }
                save()
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(get: { task.dueDate ?? Date() }, set: { task.dueDate = $0; save() })
    }

    private var hasTime: Binding<Bool> {
        Binding(
            get: { task.hasDueTime },
            set: { on in
                task.hasDueTime = on
                if let d = task.dueDate {
                    let cal = Calendar.current
                    task.dueDate = on ? (cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d) : cal.startOfDay(for: d)
                }
                save()
            }
        )
    }

    private var projectBinding: Binding<UUID?> {
        Binding(get: { task.project?.id }, set: { id in task.project = projects.first { $0.id == id }; save() })
    }

    private var recurrenceBinding: Binding<String> {
        Binding(
            get: { task.recurrence ?? "" },
            set: { encoded in
                task.recurrence = encoded.isEmpty ? nil : encoded
                if !encoded.isEmpty, task.dueDate == nil { task.dueDate = Calendar.current.startOfDay(for: Date()) }
                save()
            }
        )
    }

    private static let recurrenceOptions: [(String, String)] = [
        ("None", ""),
        ("Every day", RecurrenceRule.daily.encoded),
        ("Every weekday", RecurrenceRule.weekdays.encoded),
        ("Every week", RecurrenceRule.weekly.encoded),
        ("Every 2 weeks", RecurrenceRule(frequency: .weekly, interval: 2).encoded),
        ("Every month", RecurrenceRule.monthly.encoded),
        ("Every 3 months", RecurrenceRule(frequency: .monthly, interval: 3).encoded),
        ("Every year", RecurrenceRule.yearly.encoded),
    ]

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $task.title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .onChange(of: task.title) { _, _ in save() }
                TextField("Notes", text: $task.notes, axis: .vertical)
                    .lineLimit(3...12)
                    .onChange(of: task.notes) { _, _ in save() }
            }
            .slateRow()

            Section("Schedule") {
                Toggle("Due date", isOn: hasDate)
                if task.dueDate != nil {
                    DatePicker("Date", selection: dueDateBinding, displayedComponents: .date)
                    Toggle("Time", isOn: hasTime)
                    if task.hasDueTime {
                        DatePicker("Time", selection: dueDateBinding, displayedComponents: .hourAndMinute)
                    }
                    HStack {
                        Button("Today") { TaskActions.reschedule(task, to: Calendar.current.startOfDay(for: Date()), in: context) }
                        Button("Tomorrow") { TaskActions.reschedule(task, to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())), in: context) }
                        Button("Next week") {
                            let p = DateExpressionParser()
                            TaskActions.reschedule(task, to: p.day(7, from: p.startOfWeek(containing: Date())), in: context)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Picker("Repeat", selection: recurrenceBinding) {
                    ForEach(Self.recurrenceOptions, id: \.1) { Text($0.0).tag($0.1) }
                    if let r = task.recurrence, !Self.recurrenceOptions.contains(where: { $0.1 == r }) {
                        Text(task.recurrenceRule?.displayText ?? r).tag(r)
                    }
                }
            }
            .slateRow()

            Section("Organize") {
                Picker("Priority", selection: Binding(get: { task.priorityValue }, set: { task.priorityValue = $0; save() })) {
                    ForEach(Priority.allCases, id: \.self) { p in
                        Label(p.displayName, systemImage: p.symbol).tag(p)
                    }
                }
                Picker("Project", selection: projectBinding) {
                    Text("Inbox").tag(UUID?.none)
                    ForEach(projects) { Text($0.name).tag(Optional($0.id)) }
                }
                if labels.isEmpty {
                    Text("No labels yet. Add one with @name in Quick Add.").foregroundStyle(.secondary).font(.callout)
                } else {
                    DisclosureGroup {
                        ForEach(labels) { label in
                            Toggle(isOn: Binding(
                                get: { (task.labels ?? []).contains { $0.id == label.id } },
                                set: { on in
                                    var current = task.labels ?? []
                                    if on { if !current.contains(where: { $0.id == label.id }) { current.append(label) } }
                                    else { current.removeAll { $0.id == label.id } }
                                    task.labels = current
                                    save()
                                }
                            )) {
                                Label(label.name, systemImage: "tag.fill").foregroundStyle(Color(hex: label.colorHex))
                            }
                        }
                    } label: {
                        HStack {
                            Text("Labels")
                            Spacer()
                            Text(task.labelList.map { "@" + $0.name }.joined(separator: " ")).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .slateRow()

            Section {
                Button(task.isCompleted ? "Mark Incomplete" : (task.recurrence == nil ? "Complete" : "Complete & Advance")) {
                    TaskActions.toggleCompletion(task, in: context)
                }
                Button("Delete Task", role: .destructive) { confirmDelete = true }
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created \(task.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    if let c = task.completedAt { Text("Completed \(c.formatted(date: .abbreviated, time: .shortened))") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .slateRow()
        }
        .formStyle(.grouped)
        .slateList()
        .navigationTitle("Task")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("Delete this task?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete()
                TaskActions.delete(task, in: context)
            }
        }
    }

    private func save() {
        task.touch()
        try? context.save()
        Task { await NotificationScheduler.reschedule(context: context) }
    }
}
