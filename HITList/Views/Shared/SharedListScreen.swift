import SwiftUI
import CloudKit
import HITListCore

/// One shared list (brief 51): quick add at the top (the quick-add language for the day, time and priority:
/// "Milk tomorrow p2"), the open tasks, then the completed ones with who completed them. The title bar carries the
/// list's people (the Collaboration-style marker, which opens People) and, for the owner, Invite.
struct SharedListScreen: View {
    let listID: UUID
    /// Opens People as the screen appears (Debug launch hooks).
    var opensPeople = false
    private var center: SharedTasksCenter { SharedTasksCenter.shared }
    @State private var draft = ""
    @State private var editing: SharedTask?
    @State private var showPeople = false
    @State private var error: String?
    @State private var now = Date()
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        if let store = center.store, let list = store.list(listID) {
            content(list, me: store.me)
        } else {
            ContentUnavailableView("This list isn't here any more", systemImage: "person.2.slash",
                                   description: Text("Its owner may have stopped sharing it, or you left it."))
                .background(Theme.background)
        }
    }

    private func content(_ list: SharedList, me: SharedMemberID?) -> some View {
        let ordered = SharedTaskOrdering.sorted(list.tasks)
        let open = ordered.filter { !$0.isCompleted }
        let done = ordered.filter(\.isCompleted)
        let canAdd = SharedTasksPermissions.allows(.addTask, in: list)
        return List {
            if canAdd {
                Section {
                    SharedQuickAdd(text: $draft, now: now, onSubmit: { add(to: list) })
                        .slateRow()
                    if let error {
                        Text(error).font(HITType.footnote).foregroundStyle(HITColor.danger).slateRow()
                    }
                }
            }
            Section {
                if open.isEmpty {
                    Text(done.isEmpty ? "No tasks yet." : "All done.")
                        .font(HITType.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .slateRow()
                }
                ForEach(open) { task in row(task, list, me) }
            }
            if !done.isEmpty {
                Section {
                    ForEach(done) { task in row(task, list, me) }
                } header: {
                    Text("Completed").taskSectionHeader(color: Theme.secondaryText)
                }
            }
        }
        .sharedListStyle()
        .navigationTitle(list.title.isEmpty ? "Shared list" : list.title)
        #if os(iOS)
        // Its name once, as the system large title, as a Group's screen (round 14).
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar { toolbar(list, me: me) }
        .refreshable { await center.refresh() }
        .onAppear {
            now = Date()
            if opensPeople { showPeople = true }
        }
        .sheet(item: $editing) { task in
            SharedTaskEditor(task: task, list: list, now: now).slateSheet()
        }
        .sheet(isPresented: $showPeople) {
            SharedPeopleSheet(listID: list.id).slateSheet()
        }
        .sheet(isPresented: $renaming) {
            HITSheetChrome("Rename List", isPrimaryEnabled: !newName.trimmingCharacters(in: .whitespaces).isEmpty, onPrimary: {
                try? center.store?.renameList(list.id, to: newName)
                renaming = false
            }) {
                HITSection("Name") { HITField("Name", text: $newName, autofocus: true) }
            }
            .slateSheet()
        }
        .confirmationDialog("Delete “\(list.title)” for everyone?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete List", role: .destructive) { try? center.deleteList(list.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everyone in it loses the list and its tasks.")
        }
    }

    private func row(_ task: SharedTask, _ list: SharedList, _ me: SharedMemberID?) -> some View {
        SharedTaskRow(task: task, list: list, me: me, now: now) {
            do { try center.store?.setCompleted(!task.isCompleted, task: task.id, in: list.id) } catch { self.error = error.localizedDescription }
        }
        .slateRow()
        .contentShape(Rectangle())
        .onTapGesture { if SharedTasksPermissions.allows(.editTask, in: list) { editing = task } }
        .contextMenu {
            if SharedTasksPermissions.allows(.editTask, in: list) {
                Button("Edit…") { editing = task }
                Button("Delete", role: .destructive) { try? center.store?.deleteTask(task.id, in: list.id) }
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ list: SharedList, me: SharedMemberID?) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showPeople = true } label: { SharedListIndicator(list: list, me: me, size: 24) }
                .buttonStyle(.plain)
                .help("People")
                .accessibilityLabel("People")
                .accessibilityIdentifier("sharedListPeople")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if SharedTasksPermissions.allows(.invite, in: list) {
                    SharedInviteLink(list: list) { Label("Invite People…", systemImage: "person.badge.plus") }
                }
                Button { showPeople = true } label: { Label("People…", systemImage: "person.2") }
                if SharedTasksPermissions.allows(.renameList, in: list) {
                    Button { newName = list.title; renaming = true } label: { Label("Rename…", systemImage: "pencil") }
                }
                if SharedTasksPermissions.allows(.deleteList, in: list) {
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete List…", systemImage: "trash") }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            .accessibilityIdentifier("sharedListMenu")
        }
    }

    private func add(to list: SharedList) {
        let result = QuickAddParser(now: Date(), weekStart: Preferences.weekStartWeekday()).parse(draft)
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            try center.store?.addTask(to: list.id, title: title, priority: result.priority.rawValue,
                                      due: result.dueDate.map { SharedDue(date: $0, hasTime: result.hasDueTime) })
            draft = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The add field of a shared list: type a task in the quick-add language and Return; what was understood shows as
/// chips under it (day, time, priority).
struct SharedQuickAdd: View {
    @Binding var text: String
    var now: Date
    let onSubmit: () -> Void

    var body: some View {
        let parsed = QuickAddParser(now: now, weekStart: Preferences.weekStartWeekday()).parse(text)
        VStack(alignment: .leading, spacing: HITSpacing.s) {
            HStack(spacing: HITSpacing.s) {
                HITField("Add a task: “Milk tomorrow p2”", text: $text, systemImage: "plus")
                    .onSubmit(onSubmit)
                    .submitLabel(.done)
                    .accessibilityIdentifier("sharedQuickAdd")
                Button(action: onSubmit) { Image(systemName: "arrow.up") }
                    .buttonStyle(HITButtonStyle(.primary, size: .small, shape: .circle))
                    .disabled(parsed.title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add task")
            }
            if parsed.dueDate != nil || parsed.priority != .p4 {
                HITChipRow {
                    if let due = parsed.dueDate {
                        HITChip(DueFormatter.text(for: due, hasTime: parsed.hasDueTime, now: now), systemImage: "calendar",
                                tint: HITColor.due(due, hasTime: parsed.hasDueTime, now: now), size: .compact)
                    }
                    if parsed.priority != .p4 {
                        HITChip(parsed.priority.shortName, systemImage: "flag.fill", tint: parsed.priority.color, size: .compact)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
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

/// Invite people with the system share sheet (Messages, Mail, Copy Link, …): the list's existing CKShare, or one made
/// when the sheet asks for it. People who join can make changes; the owner chooses between invited people only and
/// anyone with the link.
struct SharedInviteLink<Label: View>: View {
    let list: SharedList
    @ViewBuilder var label: Label

    var body: some View {
        ShareLink(item: SharedListInvite(listID: list.id, title: list.title,
                                         existing: SharedTasksCenter.shared.existingShare(for: list.id)),
                  preview: SharePreview(list.title.isEmpty ? "Shared list" : list.title, image: Image(systemName: "checklist"))) {
            label
        }
    }
}

/// The item the share sheet shares: a CKShare for a list (`CKShareTransferRepresentation`).
struct SharedListInvite: Transferable, @unchecked Sendable {
    let listID: UUID
    let title: String
    let existing: CKShare?

    static let options = CKAllowedSharingOptions(allowedParticipantPermissionOptions: .readWrite,
                                                 allowedParticipantAccessOptions: .any)

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { invite in
            let container = SharedTasksCenter.container
            if let share = invite.existing {
                return .existing(share, container: container, allowedSharingOptions: options)
            }
            let listID = invite.listID
            return .prepareShare(container: container, allowedSharingOptions: options) {
                try await SharedTasksCenter.shared.prepareShare(for: listID)
            }
        }
    }
}
