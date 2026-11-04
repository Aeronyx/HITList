import SwiftUI
import SwiftData
import HITListCore

struct TaskRow: View {
    @Bindable var task: TaskItem
    var now: Date
    var showProject: Bool = true
    /// Under a header that already names the day (Today's "Oct 31, Saturday"): the row shows only the
    /// time, or nothing for an all-day task (a recurring one keeps its repeat icon).
    var hidesDay: Bool = false
    /// Set while the list animates this row's completion (see `CompletionAnimator`).
    var completionPhase: CompletionPhase? = nil
    /// Completes or un-completes the task; the list owns this so it can animate the row out.
    var onToggleCompletion: () -> Void
    @Environment(\.modelContext) private var context
    /// Optional: a row rendered outside the app shell (tests, previews) deletes at once.
    @Environment(PopoutController.self) private var popouts: PopoutController?
    /// Settings → Appearance → Compact rows: less air above and below each row (`ListMetrics`).
    @AppStorage(Preferences.compactRows, store: AppGroup.defaults) private var compactRows = Preferences.compactRowsDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @HITEffectsSetting private var effects
    @State private var pops = 0

    /// A recurring task never becomes completed (its date advances), so the row also counts as checked
    /// while its completion animates.
    private var isChecked: Bool { task.isCompleted || completionPhase != nil }

    private var checkColor: Color {
        if completionPhase != nil { return task.priorityValue == .p4 ? Theme.accent : task.priorityValue.color }
        return task.isCompleted ? Theme.secondaryText : task.priorityValue.color
    }

    /// The row slides toward the trailing edge while the list fades it out (see `CompletionMotion`).
    private var slideOffset: CGFloat {
        completionPhase == .animating && !effects.calmMotion ? CompletionMotion.slideDistance : 0
    }

    /// The height of one title line: the checkbox centres on it, so a one-line title reads as one aligned
    /// row and a two-line title keeps the checkbox on its first line. It is the checkbox's size, so the
    /// title has no spare air above or below it (the row's insets are `ListMetrics`').
    #if os(macOS)
    private let lineHeight: CGFloat = 20
    private let checkSize: CGFloat = 18
    #else
    private let lineHeight: CGFloat = 21
    private let checkSize: CGFloat = 22
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: HITSpacing.m) {
            Button {
                if !isChecked && !effects.calmMotion { pops += 1 }
                onToggleCompletion()
            } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: checkSize, weight: .regular))
                    .foregroundStyle(checkColor)
                    // The symbol swap only on completing; un-completing (and Reduce Motion) just cross-fades.
                    // No .symbolEffect(.bounce): the celebrate pop already scales this glyph, and a bounce
                    // on top of it overshoots twice.
                    .contentTransition(isChecked && !reduceMotion ? .symbolEffect(.replace) : .opacity)
                    .hitCelebratePop(trigger: pops)
                    .animation(HITMotion.standard, value: isChecked)
                    .frame(width: checkSize + 2, height: lineHeight)
                    .completionDelight(completing: completionPhase == .pending)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isChecked ? "Mark incomplete" : "Complete task")

            VStack(alignment: .leading, spacing: ListMetrics.rowLineGap) {
                // A long title wraps in full (titles are capped at `TaskLimits.titleCharacters`); the
                // checkbox stays on its first line.
                Text(task.title)
                    .font(HITType.taskTitle)
                    .tracking(HITType.taskTitleTracking)
                    .foregroundStyle(isChecked ? Theme.secondaryText : HITColor.text)
                    .overlay { strikeLine }
                    .animation(CompletionMotion.strike, value: isChecked)
                    .frame(minHeight: lineHeight, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                // The description's first line, Todoist style; the popout shows the rest.
                if !task.notes.isEmpty {
                    Text(TaskLimits.firstLine(of: task.notes))
                        .font(HITType.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityLabel("Description: \(TaskLimits.firstLine(of: task.notes))")
                }
                // The second line is always laid out, so rows with and without dates are the same height
                // and line up; the Group sits at its trailing end, Todoist style.
                HStack(spacing: HITSpacing.s + 2) {
                    // The date, labels and note icon keep their full width; a long Group name truncates.
                    HStack(spacing: HITSpacing.s + 2) {
                        if Self.hasMeta(task, hidesDay: hidesDay, showProject: showProject) {
                            if let due = task.dueDate {
                                let tint = task.isCompleted ? Theme.secondaryText : HITColor.due(due, hasTime: task.hasDueTime, now: now)
                                if !hidesDay {
                                    MetaItem(DueFormatter.text(for: due, hasTime: task.hasDueTime, now: now),
                                             systemImage: task.recurrence == nil ? "calendar" : "repeat", tint: tint)
                                } else if task.hasDueTime {
                                    MetaItem(DueFormatter.timeText(for: due), systemImage: task.recurrence == nil ? "clock" : "repeat", tint: tint)
                                } else if task.recurrence != nil {
                                    MetaItem(nil, systemImage: "repeat", tint: tint)
                                        .accessibilityLabel("Repeats")
                                }
                            }
                            // Its checklist (brief 32): "2/5" by a checklist glyph, nothing without one.
                            if let checklist = Self.checklistText(for: task) {
                                MetaItem(checklist, systemImage: "checklist", tint: Theme.secondaryText)
                                    .accessibilityLabel("\(checklist.replacingOccurrences(of: "/", with: " of ")) sub-tasks done")
                            }
                            ForEach(task.labelList) { label in
                                MetaItem("@" + label.name, systemImage: nil, tint: Color(hex: label.colorHex))
                            }
                        }
                    }
                    .layoutPriority(1)
                    Spacer(minLength: HITSpacing.s)
                    if showProject, let project = task.project {
                        MetaItem(project.name, systemImage: "circle.fill", tint: Color(hex: project.colorHex),
                                 iconSize: 8, iconTrailing: true)
                    } else {
                        // Keeps the line's height when there is nothing to show.
                        Text(" ").font(HITType.caption).hidden()
                    }
                }
                .lineLimit(1)
            }
            // Priority shows as the checkbox's colour alone; no "P1" badge.
            Spacer(minLength: 0)
        }
        // The row owns its insets (the same above and below, and the same on every list) so rows are
        // equal heights and sit the same distance under every header.
        .listRowInsets(ListMetrics.rowInsets(compact: compactRows))
        .listRowSeparatorTint(Theme.separator)
        .contentShape(Rectangle())
        // The slide-away: a render offset only, so the row's layout doesn't move.
        .offset(x: slideOffset)
        .animation(CompletionMotion.slideAway(calmMotion: effects.calmMotion), value: slideOffset)
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
                    let p = DateExpressionParser(now: now, weekStart: Preferences.weekStartWeekday())
                    TaskActions.reschedule(task, to: p.day(7, from: p.startOfWeek(containing: now)), in: context)
                }
                Button("Remove Date") { TaskActions.reschedule(task, to: nil, in: context) }
            }
            Divider()
            Button(role: .destructive) {
                let delete = { TaskActions.delete(task, in: context) }
                if let popouts { popouts.requestDelete(task, perform: delete) } else { delete() }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// Whether the second line has anything to show (an all-day task under Today's header may not).
    static func hasMeta(_ task: TaskItem, hidesDay: Bool, showProject: Bool) -> Bool {
        if let _ = task.dueDate, !hidesDay || task.hasDueTime || task.recurrence != nil { return true }
        if showProject, task.project != nil { return true }
        return !task.labelList.isEmpty || task.subtaskProgress != nil
    }

    /// "2/5" for a task with sub-tasks; nil without.
    static func checklistText(for task: TaskItem) -> String? {
        task.subtaskProgress?.compactText
    }

    /// The title's strike-through, drawn on its own so it can sweep left to right when the task is
    /// completed (a mask over a copy of the title with clear glyphs). It fades out when un-completed,
    /// and only cross-fades with Reduce Motion on.
    private var strikeLine: some View {
        Text(task.title)
            .foregroundStyle(.clear)
            .strikethrough(color: Theme.secondaryText)
            .mask(alignment: .leading) {
                Rectangle().scaleEffect(x: isChecked || reduceMotion ? 1 : 0, y: 1, anchor: .leading)
            }
            // Sweep in; on un-complete, reset only after the fade below has hidden the line.
            .animation(reduceMotion ? nil : isChecked ? CompletionMotion.strike
                       : .linear(duration: 0).delay(CompletionMotion.strikeDuration), value: isChecked)
            .opacity(isChecked ? 1 : 0)
            .animation(isChecked && !reduceMotion ? nil : CompletionMotion.strike, value: isChecked)
            .accessibilityHidden(true)
    }
}

/// One item on a row's second line: a small icon and its text 4 pt apart, in the caption size. Replaces
/// `Label`, whose List style reserves a wide icon column and pushed "Today" away from its calendar.
struct MetaItem: View {
    let text: String?
    let systemImage: String?
    let tint: Color
    var iconSize: CGFloat = 11
    /// The icon after the text (the Group at the trailing end of the line).
    var iconTrailing = false

    init(_ text: String?, systemImage: String?, tint: Color, iconSize: CGFloat = 11, iconTrailing: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.iconSize = iconSize
        self.iconTrailing = iconTrailing
    }

    var body: some View {
        HStack(spacing: 4) {
            if !iconTrailing { icon }
            if let text {
                Text(text).font(HITType.caption)
            }
            if iconTrailing { icon }
        }
        .foregroundStyle(tint)
    }

    @ViewBuilder
    private var icon: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: 12)
        }
    }
}
