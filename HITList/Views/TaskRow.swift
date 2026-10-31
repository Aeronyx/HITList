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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pops = 0

    /// A recurring task never becomes completed (its date advances), so the row also counts as checked
    /// while its completion animates.
    private var isChecked: Bool { task.isCompleted || completionPhase != nil }

    private var checkColor: Color {
        if completionPhase != nil { return task.priorityValue == .p4 ? Theme.accent : task.priorityValue.color }
        return task.isCompleted ? Color.secondary : task.priorityValue.color
    }

    /// The height of one title line. The checkbox and the priority badge centre on it, so a one-line
    /// title reads as one aligned row and a two-line title keeps them on its first line.
    #if os(macOS)
    private let lineHeight: CGFloat = 20
    private let checkSize: CGFloat = 18
    #else
    private let lineHeight: CGFloat = 24
    private let checkSize: CGFloat = 22
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: HITSpacing.m) {
            Button {
                if !isChecked && !reduceMotion { pops += 1 }
                onToggleCompletion()
            } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: checkSize, weight: .regular))
                    .foregroundStyle(checkColor)
                    // The symbol swap only on completing; un-completing (and Reduce Motion) just cross-fades.
                    .contentTransition(isChecked && !reduceMotion ? .symbolEffect(.replace) : .opacity)
                    .keyframeAnimator(initialValue: 1.0, trigger: pops) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.15, duration: 0.1, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.15, spring: .smooth)
                    }
                    .animation(.easeOut(duration: 0.15), value: isChecked)
                    .frame(width: checkSize + 2, height: lineHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isChecked ? "Mark incomplete" : "Complete task")

            VStack(alignment: .leading, spacing: HITSpacing.xs) {
                Text(task.title)
                    .font(HITType.body)
                    .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                    .lineLimit(2)
                    .overlay { strikeLine }
                    .animation(.easeOut(duration: 0.2), value: isChecked)
                    .frame(minHeight: lineHeight, alignment: .leading)
                if hasMeta {
                    HStack(spacing: HITSpacing.s + 2) {
                        if let due = task.dueDate {
                            let tint = task.isCompleted ? Color.secondary : HITColor.due(due, hasTime: task.hasDueTime, now: now)
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
                        if showProject, let project = task.project {
                            MetaItem(project.name, systemImage: "circle.fill", tint: Color(hex: project.colorHex), iconSize: 8)
                        }
                        ForEach(task.labelList) { label in
                            MetaItem("@" + label.name, systemImage: nil, tint: Color(hex: label.colorHex))
                        }
                        if !task.notes.isEmpty {
                            MetaItem(nil, systemImage: "text.alignleft", tint: Theme.secondaryText)
                                .accessibilityLabel("Has a description")
                        }
                    }
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if task.priorityValue != .p4 {
                Text(task.priorityValue.shortName)
                    .font(HITType.caption2Semibold)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(task.priorityValue.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(task.priorityValue.color)
                    .frame(height: lineHeight)
            }
        }
        .padding(.vertical, HITSpacing.xs)
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

    /// Whether the second line has anything to show (an all-day task under Today's header may not).
    private var hasMeta: Bool {
        if let _ = task.dueDate, !hidesDay || task.hasDueTime || task.recurrence != nil { return true }
        if showProject, task.project != nil { return true }
        return !task.labelList.isEmpty || !task.notes.isEmpty
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

/// One item on a row's second line: a small icon and its text 4 pt apart, in the caption size. Replaces
/// `Label`, whose List style reserves a wide icon column and pushed "Today" away from its calendar.
struct MetaItem: View {
    let text: String?
    let systemImage: String?
    let tint: Color
    var iconSize: CGFloat = 11

    init(_ text: String?, systemImage: String?, tint: Color, iconSize: CGFloat = 11) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.iconSize = iconSize
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: 12)
            }
            if let text {
                Text(text).font(HITType.caption)
            }
        }
        .foregroundStyle(tint)
    }
}
