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
    /// The board's cards let the meta line wrap (brief 56); every list keeps it to one line.
    @Environment(\.taskMetaWraps) private var metaWraps
    /// Beside the upright island (the Duo's outer display) the title and meta line are a step larger.
    @Environment(\.listIslandPlacement) private var islandPlacement
    @HITEffectsSetting private var effects

    /// A recurring task never becomes completed (its date advances), so the row also counts as checked
    /// while its completion animates.
    private var isChecked: Bool { task.isCompleted || completionPhase != nil }

    /// A red Flipboard switch (brief 59): Today's every day until it is flipped, so its row shows the
    /// switch glyph and no date. While its flip animates out it is already green; it keeps the glyph.
    private var isSwitch: Bool { Self.showsSwitch(task, now: now, completing: completionPhase != nil) }

    static func showsSwitch(_ task: TaskItem, now: Date, completing: Bool) -> Bool {
        guard Flipboard.isMember(task) else { return false }
        return completing || Flipboard.side(of: task, now: now) == .red
    }

    private var checkColor: Color {
        if completionPhase != nil { return task.priorityValue == .p4 ? Theme.accent : task.priorityValue.color }
        return task.isCompleted ? Theme.secondaryText : task.priorityValue.color
    }

    var body: some View {
        HStack(alignment: .top, spacing: HITSpacing.m) {
            TaskRowCheckbox(isChecked: isChecked, color: checkColor, completing: completionPhase == .pending,
                            accessibilityLabel: isChecked ? "Mark incomplete" : isSwitch ? "Flip switch" : "Complete task",
                            action: onToggleCompletion)

            VStack(alignment: .leading, spacing: ListMetrics.rowLineGap) {
                TaskRowTitle(title: task.title, isChecked: isChecked)
                // The description's first line, Todoist style; the popout shows the rest.
                TaskRowNotes(notes: task.notes)
                metaLine
            }
            // Priority shows as the checkbox's colour alone; no "P1" badge.
            Spacer(minLength: 0)
        }
        .taskRowChrome(compact: compactRows, completionPhase: completionPhase, calmMotion: effects.calmMotion)
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

    // MARK: The meta line

    /// The second line. In a list it is always one line, laid out even when empty, so rows with and
    /// without dates are the same height and line up; the Group sits at its trailing end, Todoist style.
    /// On the board (`taskMetaWraps`, brief 56) its items flow onto a second line instead, so a crowded
    /// 270 pt card keeps its time, bell and Group readable.
    @ViewBuilder
    private var metaLine: some View {
        if metaWraps {
            MetaFlowLayout(spacing: HITSpacing.s + 2, lineSpacing: ListMetrics.rowLineGap) {
                metaItems
                if showProject, task.project != nil {
                    groupItem.layoutValue(key: MetaTrailingKey.self, value: true)
                } else if !Self.hasMeta(task, hidesDay: hidesDay, showProject: showProject, now: now) {
                    groupItem // the hidden space: an empty line keeps its height
                }
            }
            .lineLimit(1)
        } else {
            HStack(spacing: HITSpacing.s + 2) {
                // The date, labels and note icon keep their full width; a long Group name truncates.
                HStack(spacing: HITSpacing.s + 2) { metaItems }
                    .layoutPriority(1)
                Spacer(minLength: HITSpacing.s)
                groupItem
            }
            .lineLimit(1)
        }
    }

    /// The date (or time), the reminder bell, the checklist count and the labels, in that order.
    @ViewBuilder
    private var metaItems: some View {
        if Self.hasMeta(task, hidesDay: hidesDay, showProject: showProject, now: now) {
            if isSwitch {
                // Due today, every day: the glyph says so; the Flipboard keeps the days overdue.
                MetaItem(nil, systemImage: "switch.2", tint: isChecked ? Theme.secondaryText : HITColor.dueToday)
                    .accessibilityLabel("Flipboard switch")
            } else if let due = task.dueDate {
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
            // Its own reminder still to come (brief 48, "!15m"): a small bell and the time.
            if let reminder = Self.reminderText(for: task, now: now) {
                MetaItem(reminder, systemImage: "bell", tint: Theme.secondaryText)
                    .accessibilityLabel("Reminder \(reminder)")
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

    /// The Group with its dot at the line's trailing end; a hidden space keeps the line's height without one.
    @ViewBuilder
    private var groupItem: some View {
        if showProject, let project = task.project {
            MetaItem(project.name, systemImage: "circle.fill", tint: Color(hex: project.colorHex),
                     iconSize: 8, iconTrailing: true)
        } else {
            Text(" ").font(HITType.taskMeta(for: islandPlacement)).hidden()
        }
    }

    /// Whether the second line has anything to show (an all-day task under Today's header may not).
    static func hasMeta(_ task: TaskItem, hidesDay: Bool, showProject: Bool, now: Date = Date()) -> Bool {
        if showsSwitch(task, now: now, completing: false) { return true }
        if let _ = task.dueDate, !hidesDay || task.hasDueTime || task.recurrence != nil { return true }
        if showProject, task.project != nil { return true }
        if reminderText(for: task, now: now) != nil { return true }
        return !task.labelList.isEmpty || task.subtaskProgress != nil
    }

    /// The bell's text for an open task's own reminder still to come ("!15m", brief 48): "3:47 PM" today,
    /// "Tomorrow 9:00 AM" on another day; nil when there is none, it has gone off, or the task is done.
    static func reminderText(for task: TaskItem, now: Date, calendar: Calendar = .current) -> String? {
        guard !task.isCompleted, let at = task.reminderDate, at > now else { return nil }
        return ReminderChipText.when(at, now: now, calendar: calendar)
    }

    /// "2/5" for a task with sub-tasks; nil without.
    static func checklistText(for task: TaskItem) -> String? {
        task.subtaskProgress?.compactText
    }

}

// MARK: - The parts every row shares

/// A task row's measurements. The height of one title line: the checkbox centres on it, so a one-line title reads
/// as one aligned row and a two-line title keeps the checkbox on its first line. It is the checkbox's size, so the
/// title has no spare air above or below it (the row's insets are `ListMetrics`'). Round 15's titles still fit one
/// line: Inter 14's line is 16.9 pt (Mac, 20) and Inter 17's 20.6 (iPhone, 21), and George's target row has the Mac's
/// 18 pt circle.
enum TaskRowMetrics {
    #if os(macOS)
    static let lineHeight: CGFloat = 20
    static let checkSize: CGFloat = 18
    #else
    static let lineHeight: CGFloat = 21
    static let checkSize: CGFloat = 22
    #endif
}

/// The check circle a task row starts with, yours and a shared task's alike (brief 62): the priority's colour, the
/// celebrate pop and the delight on completing.
struct TaskRowCheckbox: View {
    let isChecked: Bool
    let color: Color
    /// The completion's first moment (`CompletionPhase.pending`).
    var completing = false
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @HITEffectsSetting private var effects
    @State private var pops = 0

    var body: some View {
        Button {
            if !isChecked && !effects.calmMotion { pops += 1 }
            action()
        } label: {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: TaskRowMetrics.checkSize, weight: .regular))
                .foregroundStyle(color)
                // The symbol swap only on completing; un-completing (and Reduce Motion) just cross-fades.
                // No .symbolEffect(.bounce): the celebrate pop already scales this glyph, and a bounce
                // on top of it overshoots twice.
                .contentTransition(isChecked && !reduceMotion ? .symbolEffect(.replace) : .opacity)
                .hitCelebratePop(trigger: pops)
                .animation(HITMotion.standard, value: isChecked)
                .frame(width: TaskRowMetrics.checkSize + 2, height: TaskRowMetrics.lineHeight)
                .completionDelight(completing: completing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A task row's title: wraps in full (titles are capped at `TaskLimits.titleCharacters`), struck through when
/// checked.
struct TaskRowTitle: View {
    let title: String
    let isChecked: Bool
    /// Beside the upright island (the Duo's outer display) a step larger.
    @Environment(\.listIslandPlacement) private var islandPlacement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(title)
            .font(HITType.taskTitle(for: islandPlacement))
            .tracking(HITType.taskTitleTracking)
            .foregroundStyle(isChecked ? Theme.secondaryText : HITColor.text)
            .overlay { strikeLine }
            .animation(CompletionMotion.strike, value: isChecked)
            .frame(minHeight: TaskRowMetrics.lineHeight, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The title's strike-through, drawn on its own so it can sweep left to right when the task is
    /// completed (a mask over a copy of the title with clear glyphs). It fades out when un-completed,
    /// and only cross-fades with Reduce Motion on.
    private var strikeLine: some View {
        Text(title)
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

/// The description's first line under the title, Todoist style; nothing without one.
struct TaskRowNotes: View {
    let notes: String

    var body: some View {
        if !notes.isEmpty {
            Text(TaskLimits.firstLine(of: notes))
                .font(HITType.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel("Description: \(TaskLimits.firstLine(of: notes))")
        }
    }
}

extension View {
    /// A task row's place in its list: its own insets (the same above and below, and the same on every list, so rows
    /// are equal heights and sit the same distance under every header), the hairline, and the slide toward the
    /// trailing edge while the list fades it out (`CompletionMotion`), a render offset only so the layout doesn't move.
    func taskRowChrome(compact: Bool, completionPhase: CompletionPhase?, calmMotion: Bool) -> some View {
        let slide = completionPhase == .animating && !calmMotion ? CompletionMotion.slideDistance : 0
        return self
            .listRowInsets(ListMetrics.rowInsets(compact: compact))
            .listRowSeparatorTint(Theme.separator)
            .contentShape(Rectangle())
            .offset(x: slide)
            .animation(CompletionMotion.slideAway(calmMotion: calmMotion), value: slide)
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
    /// A step larger beside the upright island (`HITType.taskMeta(for:)`).
    @Environment(\.listIslandPlacement) private var islandPlacement

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
                Text(text).font(HITType.taskMeta(for: islandPlacement))
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

extension EnvironmentValues {
    /// Where the island stands beside the lists, for their rows' type (brief 63): the iPhone shell hands its lists
    /// its own `\.islandPlacement`; everywhere else it stays `.bottom`, so the sidebar layout (iPad, Mac, the Duo's
    /// inner display, which has no island even where the system's bars stand in a column) keeps the usual sizes.
    @Entry var listIslandPlacement: IslandPlacement = .bottom

    /// The board's cards (brief 56): a row's meta line flows onto a second line instead of truncating.
    /// Off everywhere else: list rows keep one line and equal heights.
    @Entry var taskMetaWraps: Bool = false
}

/// The meta item that sits at the trailing end of its line (the Group).
struct MetaTrailingKey: LayoutValueKey {
    static let defaultValue = false
}

/// The board's meta line (brief 56): items left to right, breaking onto a new line between items, never
/// inside one; the Group (`MetaTrailingKey`) at the trailing end of whichever line it lands on. An item
/// wider than the whole line gets a line of its own and truncates there.
struct MetaFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    /// The items' indices per line, in order, for items of these widths.
    static func lines(widths: [CGFloat], spacing: CGFloat, maxWidth: CGFloat) -> [[Int]] {
        var lines: [[Int]] = []
        var current: [Int] = []
        var x: CGFloat = 0
        for (i, width) in widths.enumerated() {
            let end = current.isEmpty ? width : x + spacing + width
            if !current.isEmpty, end > maxWidth {
                lines.append(current)
                current = [i]
                x = width
            } else {
                current.append(i)
                x = end
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private struct Arrangement {
        var lines: [[Int]]
        var sizes: [CGSize]
        var lineHeights: [CGFloat]
        var height: CGFloat
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> Arrangement {
        let sizes = subviews.map { view -> CGSize in
            let ideal = view.sizeThatFits(.unspecified)
            guard ideal.width > maxWidth else { return ideal }
            return view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        }
        let lines = Self.lines(widths: sizes.map(\.width), spacing: spacing, maxWidth: maxWidth)
        let heights: [CGFloat] = lines.map { line in line.reduce(0) { max($0, sizes[$1].height) } }
        let gaps: CGFloat = lineSpacing * CGFloat(max(0, lines.count - 1))
        let height: CGFloat = heights.reduce(0, +) + gaps
        return Arrangement(lines: lines, sizes: sizes, lineHeights: heights, height: height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let arrangement = arrange(subviews, maxWidth: maxWidth)
        var widest: CGFloat = 0
        for line in arrangement.lines {
            let items: CGFloat = line.reduce(0) { $0 + arrangement.sizes[$1].width }
            let gaps: CGFloat = spacing * CGFloat(max(0, line.count - 1))
            widest = max(widest, items + gaps)
        }
        return CGSize(width: proposal.width ?? widest, height: arrangement.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for (lineIndex, line) in arrangement.lines.enumerated() {
            let lineHeight = arrangement.lineHeights[lineIndex]
            var x = bounds.minX
            for index in line {
                let size = arrangement.sizes[index]
                let trailing = subviews[index][MetaTrailingKey.self]
                let origin = CGPoint(x: trailing ? max(x, bounds.maxX - size.width) : x,
                                     y: y + (lineHeight - size.height) / 2)
                subviews[index].place(at: origin, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += lineHeight + lineSpacing
        }
    }
}
