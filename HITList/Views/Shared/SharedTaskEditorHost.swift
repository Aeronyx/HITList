import SwiftUI
import HITListCore

extension View {
    /// Draws the editor of a shared task this list opened (brief 62, `PopoutController.openShared`): the one
    /// `SharedListScreen` uses, in a sheet on the iPhone and iPad and in the panel on the Mac, where a task of yours
    /// opens too. `owner` is the list's own id, so on the iPhone a list under another on its stack never presents it
    /// as well.
    func sharedTaskEditor(owner: UUID) -> some View {
        modifier(SharedTaskEditorHost(owner: owner))
    }
}

private struct SharedTaskEditorHost: ViewModifier {
    let owner: UUID
    @Environment(PopoutController.self) private var popouts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .overlay {
                if let ref = popouts.sharedTask(for: owner) {
                    // The panel a task of yours opens in: dimmed behind, 560 pt wide, near the top. It covers this
                    // list's column; the sidebar dims itself to match (`SidebarView`).
                    PanelBackdrop(onDismiss: close) {
                        editor(ref)
                            .frame(idealHeight: 530)
                            .panelChrome()
                    }
                    .transition(.opacity)
                }
            }
            .animation(HITMotion.enter(reduceMotion: reduceMotion), value: popouts.sharedTask(for: owner) != nil)
        #else
        content
            .sheet(item: Binding(get: { popouts.sharedTask(for: owner) }, set: { if $0 == nil { close() } })) { ref in
                editor(ref).slateSheet()
            }
        #endif
    }

    @ViewBuilder
    private func editor(_ ref: SharedTaskRef) -> some View {
        if let list = SharedRows.shared.list(ref.listID), let task = list.task(ref.taskID) {
            SharedTaskEditor(task: task, list: list, now: Date(), onClose: close)
                .id(ref.taskID)
        } else {
            // Deleted, or its list left, on another device while it was open: nothing to edit.
            Color.clear.onAppear(perform: close)
        }
    }

    private func close() { popouts.closeSharedTask() }
}

/// Edit a shared task: name, description, priority, day; or delete it. In a sheet (the Shared screen, the iPhone's
/// lists) or the Mac's panel (brief 62), which passes `onClose` since nothing presented it to dismiss.
struct SharedTaskEditor: View {
    let task: SharedTask
    let list: SharedList
    var now: Date
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var priority: Int
    @State private var dueDay: Date?
    @State private var dueHasTime: Bool
    @State private var showCalendar = false

    init(task: SharedTask, list: SharedList, now: Date, onClose: (() -> Void)? = nil) {
        self.task = task
        self.list = list
        self.now = now
        self.onClose = onClose
        _title = State(initialValue: task.title.value)
        _notes = State(initialValue: task.notes.value)
        _priority = State(initialValue: task.priority.value)
        _dueDay = State(initialValue: task.due.value?.date)
        _dueHasTime = State(initialValue: task.due.value?.hasTime ?? false)
    }

    var body: some View {
        HITSheetChrome("Task", isPrimaryEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty, onCancel: onClose,
                       onPrimary: save) {
            HITSection("Name") { HITField("Task name", text: $title) }
            HITSection("Description") { HITField("Description", text: $notes, axis: .vertical, lineLimit: 1...6) }
            HITSection("Priority") {
                HITSegmented(selection: $priority, segments: Priority.allCases.map {
                    HITSegment($0.rawValue, $0.shortName, systemImage: "flag.fill", tint: $0.color)
                })
            }
            HITSection("Date") {
                HITChipRow {
                    HITChip("None", isSelected: dueDay == nil, action: { dueDay = nil; showCalendar = false })
                    HITChip("Today", systemImage: "calendar", tint: HITColor.dueToday, isSelected: isDay(0), action: { pick(offset: 0) })
                    HITChip("Tomorrow", systemImage: "sun.max", tint: HITColor.dueTomorrow, isSelected: isDay(1), action: { pick(offset: 1) })
                    HITChip("Pick…", systemImage: "calendar.badge.plus", isSelected: showCalendar, action: { showCalendar.toggle() })
                }
                if showCalendar {
                    HITCalendar(selection: dueDay, today: now, weekStart: Preferences.weekStartWeekday()) { day in
                        dueDay = day
                        dueHasTime = false
                    }
                }
                if let dueDay {
                    Text(DueFormatter.text(for: dueDay, hasTime: dueHasTime, now: now))
                        .font(HITType.footnote)
                        .foregroundStyle(HITColor.due(dueDay, hasTime: dueHasTime, now: now))
                }
            }
            if let line = SharedPeople.completedBy(task, in: list, me: SharedTasksCenter.shared.store?.me) {
                HITSection { Label(line, systemImage: "checkmark.circle").font(HITType.footnote).foregroundStyle(Theme.secondaryText) }
            }
            if SharedTasksPermissions.allows(.deleteTask, in: list) {
                HITSection {
                    Button("Delete Task", role: .destructive) {
                        try? SharedTasksCenter.shared.store?.deleteTask(task.id, in: list.id)
                        close()
                    }
                    .buttonStyle(.hitDestructive)
                }
            }
        }
    }

    private func isDay(_ offset: Int) -> Bool {
        guard let dueDay, let day = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: now)) else { return false }
        return Calendar.current.isDate(dueDay, inSameDayAs: day)
    }

    private func pick(offset: Int) {
        dueDay = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: now))
        dueHasTime = false
        showCalendar = false
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func save() {
        guard let store = SharedTasksCenter.shared.store else { close(); return }
        do {
            try store.setTitle(title, task: task.id, in: list.id)
            try store.setNotes(notes, task: task.id, in: list.id)
            try store.setPriority(priority, task: task.id, in: list.id)
            // Keep the time when the day didn't change.
            let due: SharedDue? = dueDay.map { day in
                if let old = task.due.value, Calendar.current.isDate(old.date, inSameDayAs: day) { return old }
                return SharedDue(date: Calendar.current.startOfDay(for: day), hasTime: false)
            }
            try store.setDue(due, task: task.id, in: list.id)
        } catch {
            // The task went (deleted elsewhere) or the list did: nothing to save into.
        }
        close()
    }
}

