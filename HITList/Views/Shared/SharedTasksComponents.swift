import SwiftUI
import HITListCore

// Pieces the Shared screens share (brief 51): the Preview badge, the avatar stack that marks a shared list (the
// Collaboration-style indicator), and a shared task's row, drawn like `TaskRow` (which binds a `TaskItem` from the
// task store, so it can't show a shared task itself).

/// "Preview", a small capsule beside the Shared Tasks name.
struct SharedPreviewBadge: View {
    /// Smaller, for the Mac and iPad sidebar row.
    var compact = false

    var body: some View {
        Text("Preview")
            .font(HITType.caption2Semibold)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 1 : 2)
            .background(Capsule().fill(Theme.accent.opacity(0.15)))
            .accessibilityLabel("Preview")
    }
}

/// Up to three faces, overlapping, and "+2" for the rest: who is in a shared list.
struct SharedAvatarStack: View {
    let people: [SharedPerson]
    var size: CGFloat = 22
    var limit = 3
    /// The ring that separates overlapping faces: the colour of what they sit on.
    var ring: Color = Theme.background

    /// How far each face overlaps the one before it.
    static let overlap: CGFloat = 0.3

    /// The stack's width for `count` people at `size`.
    static func width(count: Int, size: CGFloat, limit: Int = 3) -> CGFloat {
        let faces = min(count, limit) + (count > limit ? 1 : 0)
        guard faces > 0 else { return 0 }
        return size + CGFloat(faces - 1) * size * (1 - overlap)
    }

    var body: some View {
        let shown = Array(people.prefix(limit))
        let lineWidth = max(1, min(1.5, size / 12))
        HStack(spacing: -size * Self.overlap) {
            ForEach(shown) { person in
                ProfileAvatarView(imageData: person.avatar, name: person.avatarName, size: size)
                    .overlay(Circle().strokeBorder(ring, lineWidth: lineWidth))
                    .opacity(person.isPending ? 0.5 : 1)
            }
            if people.count > limit {
                Text("+\(people.count - limit)")
                    .font(HITFont.inter(size * 0.45, .semibold))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Theme.elevated))
                    .overlay(Circle().strokeBorder(ring, lineWidth: lineWidth))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(people))
    }

    static func accessibilityLabel(_ people: [SharedPerson]) -> String {
        let names = people.filter { !$0.isPending }.map { $0.isMe ? "you" : $0.name }
        return names.isEmpty ? "Only you" : "Shared with " + ListFormatter.localizedString(byJoining: names)
    }
}

/// The marker on a shared list's card and title bar: faces, or a two-person symbol before anyone joined.
struct SharedListIndicator: View {
    let list: SharedList
    let me: SharedMemberID?
    var size: CGFloat = 22

    var body: some View {
        let people = SharedPeople.people(in: list, me: me)
        if list.isShared && people.count > 1 {
            SharedAvatarStack(people: people, size: size)
        } else {
            Image(systemName: list.isShared ? "person.2.fill" : "person.crop.circle.badge.plus")
                .font(.system(size: size * 0.6, weight: .semibold))
                .foregroundStyle(list.isShared ? Theme.accent : Theme.secondaryText)
                .frame(height: size)
                .accessibilityLabel(list.isShared ? "Shared" : "Not shared yet")
        }
    }
}

/// A shared task: the check circle in its priority colour, the title, and a line with the due day and who
/// completed it (or who added it, when that wasn't me).
struct SharedTaskRow: View {
    let task: SharedTask
    let list: SharedList
    let me: SharedMemberID?
    var now = Date()
    let onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Beside the Duo's upright island a step larger, as every row (brief 63).
    @Environment(\.listIslandPlacement) private var islandPlacement

    #if os(macOS)
    private let checkSize: CGFloat = 18
    private let lineHeight: CGFloat = 20
    #else
    private let checkSize: CGFloat = 22
    private let lineHeight: CGFloat = 21
    #endif

    private var canWrite: Bool { SharedTasksPermissions.allows(.completeTask, in: list) }
    private var priority: Priority { Priority(clamping: task.priority.value) }

    var body: some View {
        HStack(alignment: .top, spacing: HITSpacing.m) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: checkSize, weight: .regular))
                    .foregroundStyle(task.isCompleted ? Theme.secondaryText : priority.color)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .frame(width: checkSize + 2, height: lineHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canWrite)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Complete task")

            VStack(alignment: .leading, spacing: ListMetrics.rowLineGap) {
                Text(task.title.value)
                    .font(HITType.taskTitle(for: islandPlacement))
                    .tracking(HITType.taskTitleTracking)
                    .foregroundStyle(task.isCompleted ? Theme.secondaryText : HITColor.text)
                    .strikethrough(task.isCompleted, color: Theme.secondaryText)
                    .frame(minHeight: lineHeight, alignment: .leading)
                if !metaIsEmpty {
                    HStack(spacing: HITSpacing.m) {
                        if let due = task.due.value, !task.isCompleted {
                            MetaItem(DueFormatter.text(for: due.date, hasTime: due.hasTime, now: now), systemImage: "calendar",
                                     tint: HITColor.due(due.date, hasTime: due.hasTime, now: now))
                        }
                        if let done = SharedPeople.completedBy(task, in: list, me: me) {
                            MetaItem(done, systemImage: "checkmark", tint: Theme.secondaryText)
                        } else if let added = addedBy {
                            MetaItem(added, systemImage: "person", tint: Theme.secondaryText)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if let completer {
                ProfileAvatarView(imageData: completer.avatar, name: completer.avatarName, size: 20)
                    .frame(height: lineHeight)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var metaIsEmpty: Bool { (task.due.value == nil || task.isCompleted) && !task.isCompleted && addedBy == nil }

    /// "Added by Sam", for an open task someone else added.
    private var addedBy: String? {
        guard !task.isCompleted, let by = task.createdBy, by != me else { return nil }
        return "Added by " + SharedPeople.name(of: by, in: list, me: me, fallback: task.createdByName)
    }

    /// Whoever completed it, when that was someone else: their face at the row's end.
    private var completer: SharedPerson? {
        guard let by = task.completion.value?.by, by != me else { return nil }
        return SharedPeople.people(in: list, me: me).first { $0.memberID == by }
    }
}

/// Who a shared task is shared with, where a task of yours has its labels (brief 64): their faces overlapped, in the
/// meta line's own height, so a shared row is exactly as tall as one of yours. The height is the line's, read from a
/// space set in the meta font, so the faces follow the type wherever it changes (the Duo's side island, Dynamic Type).
struct SharedRowPeople: View {
    let people: [SharedPerson]
    /// The ring between faces: the row's ground (a list's background, a board card's surface).
    var ring: Color = Theme.background
    @Environment(\.listIslandPlacement) private var islandPlacement
    @State private var line: CGFloat = 12

    var body: some View {
        if !people.isEmpty {
            Text(" ")
                .font(HITType.taskMeta(for: islandPlacement))
                .hidden()
                .frame(width: SharedAvatarStack.width(count: people.count, size: line))
                .overlay(alignment: .leading) { SharedAvatarStack(people: people, size: line, ring: ring) }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { line = max(1, $0) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(SharedAvatarStack.accessibilityLabel(people))
        }
    }
}

/// A shared task as a row of your lists (briefs 62, 64): a task of yours to look at, drawn from `TaskRow`'s own parts
/// (the check circle in its priority's colour, the title, the description's first line, the date), with the people it
/// is shared with where your labels go and "Shared Tasks" with its dot where your Group sits. No people glyph and no
/// list name. Completing, Undo and opening it are the list's (`onToggleCompletion`, the list's selection); its menu
/// changes it in the shared store.
struct SharedTaskListRow: View {
    let row: SharedRow
    var now: Date
    /// "Shared Tasks" at the end of the second line; off in the Group's own screen and under its section header.
    var showGroup = true
    /// Under a header that names the day: the row shows only the time (or nothing for an all-day task).
    var hidesDay = false
    var completionPhase: CompletionPhase? = nil
    var onToggleCompletion: () -> Void
    /// Optional: a row drawn outside the app shell (tests) deletes at once.
    @Environment(PopoutController.self) private var popouts: PopoutController?
    @AppStorage(Preferences.compactRows, store: AppGroup.defaults) private var compactRows = Preferences.compactRowsDefault
    /// The board's cards let the meta line wrap (brief 56).
    @Environment(\.taskMetaWraps) private var metaWraps
    @Environment(\.listIslandPlacement) private var islandPlacement
    @HITEffectsSetting private var effects

    private var task: SharedTask { row.task }
    private var priority: Priority { Priority(clamping: task.priority.value) }
    /// Checked while its completion animates too, as `TaskRow`.
    private var isChecked: Bool { task.isCompleted || completionPhase != nil }

    private var checkColor: Color {
        if completionPhase != nil { return priority == .p4 ? Theme.accent : priority.color }
        return task.isCompleted ? Theme.secondaryText : priority.color
    }

    var body: some View {
        HStack(alignment: .top, spacing: HITSpacing.m) {
            TaskRowCheckbox(isChecked: isChecked, color: checkColor, completing: completionPhase == .pending,
                            accessibilityLabel: isChecked ? "Mark incomplete" : "Complete task", action: onToggleCompletion)
                .disabled(!row.canWrite)
            VStack(alignment: .leading, spacing: ListMetrics.rowLineGap) {
                TaskRowTitle(title: task.title.value, isChecked: isChecked)
                TaskRowNotes(notes: task.notes.value)
                metaLine
            }
            Spacer(minLength: 0)
        }
        .taskRowChrome(compact: compactRows, completionPhase: completionPhase, calmMotion: effects.calmMotion)
        .contextMenu { menu }
    }

    // MARK: The meta line

    /// As `TaskRow`'s: one line in a list, laid out even when empty so every row is the same height; on the board's
    /// cards it flows onto a second line, the Group at the trailing end of whichever line it lands on.
    @ViewBuilder
    private var metaLine: some View {
        if metaWraps {
            MetaFlowLayout(spacing: HITSpacing.s + 2, lineSpacing: ListMetrics.rowLineGap) {
                dueItem
                SharedRowPeople(people: row.people, ring: Theme.surface)
                if showGroup {
                    groupItem.layoutValue(key: MetaTrailingKey.self, value: true)
                } else if !showsDue && row.people.isEmpty {
                    emptyLine
                }
            }
            .lineLimit(1)
        } else {
            HStack(spacing: HITSpacing.s + 2) {
                // The date and the people keep their full width, as yours keep the date and labels.
                HStack(spacing: HITSpacing.s + 2) {
                    dueItem
                    SharedRowPeople(people: row.people)
                }
                .layoutPriority(1)
                Spacer(minLength: HITSpacing.s)
                if showGroup { groupItem } else { emptyLine }
            }
            .lineLimit(1)
        }
    }

    private var showsDue: Bool {
        guard let due = task.due.value else { return false }
        return !hidesDay || due.hasTime
    }

    @ViewBuilder
    private var dueItem: some View {
        if let due = task.due.value {
            let tint = task.isCompleted ? Theme.secondaryText : HITColor.due(due.date, hasTime: due.hasTime, now: now)
            if !hidesDay {
                MetaItem(DueFormatter.text(for: due.date, hasTime: due.hasTime, now: now), systemImage: "calendar", tint: tint)
            } else if due.hasTime {
                MetaItem(DueFormatter.timeText(for: due.date), systemImage: "clock", tint: tint)
            }
        }
    }

    /// "Shared Tasks" and its dot, where a Group of yours sits.
    private var groupItem: some View {
        TaskRowGroupItem(name: SharedTasksGroup.name, colorHex: SharedTasksGroup.colorHex)
    }

    /// The hidden space that keeps an empty line's height.
    private var emptyLine: some View {
        Text(" ").font(HITType.taskMeta(for: islandPlacement)).hidden()
    }

    // MARK: The menu

    /// Priority, Reschedule and Delete, as on a row of yours, through the shared store; nothing for a member who can
    /// only look.
    @ViewBuilder
    private var menu: some View {
        if row.canWrite {
            Menu("Priority") {
                ForEach(Priority.allCases, id: \.self) { p in
                    Button { try? SharedRows.shared.setPriority(p.rawValue, row) } label: { Label(p.displayName, systemImage: p.symbol) }
                }
            }
            Menu("Reschedule") {
                Button("Today") { move(to: Calendar.current.startOfDay(for: now)) }
                Button("Tomorrow") { move(to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))) }
                Button("Next Week") {
                    let p = DateExpressionParser(now: now, weekStart: Preferences.weekStartWeekday())
                    move(to: p.day(7, from: p.startOfWeek(containing: now)))
                }
                Button("Remove Date") { move(to: nil) }
            }
            Divider()
            Button(role: .destructive) {
                let delete = { try? SharedRows.shared.delete(row) }
                if let popouts { popouts.requestDelete(title: task.title.value) { _ = delete() } } else { _ = delete() }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func move(to day: Date?) {
        try? SharedRows.shared.reschedule(row, to: day)
    }
}

extension View {
    /// The Shared screens' list look: inset groups on the iPhone and iPad, the Mac's inset list.
    @ViewBuilder
    func sharedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped).slateList()
        #else
        self.listStyle(.inset).slateList()
        #endif
    }
}
