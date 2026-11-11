import SwiftUI
import WidgetKit
import HITListCore

/// A task in a widget, as the app's `TaskRow` draws it: the priority ring in the task's colour, the title, and under it
/// the second line, here its time (or its date, for an overdue task) and its Group at the trailing end. The ring is its
/// own view (`WidgetCheckRing`), so it can become a completion button later without the row changing.
struct WidgetTaskRow: View {
    /// How much of the row a widget has room for.
    enum Style {
        /// The title over its second line (large widgets).
        case full
        /// One line: the title, and at the trailing end its time (or date) in its due colour (medium widgets).
        case titleAndTime
        /// The title alone (small widgets).
        case titleOnly
    }

    let task: WidgetSnapshot.Task
    let now: Date
    /// Under a header that names the day (Today's): the time alone, or nothing for an all-day task.
    var hidesDay = true
    var style = Style.full
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: WidgetLook.ringGap) {
            WidgetCheckRing(priority: task.priority)
            VStack(alignment: .leading, spacing: WidgetLook.lineGap) {
                HStack(spacing: HITSpacing.s) {
                    Text(task.title)
                        .font(WidgetLook.rowTitle)
                        .tracking(HITType.taskTitleTracking)
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    if style == .titleAndTime {
                        Spacer(minLength: 0)
                        WidgetWhen(task: task, now: now, hidesDay: hidesDay, short: true).fixedSize()
                    }
                }
                .frame(height: WidgetLook.rowTitleLine)
                if style == .full, Self.hasMeta(task, hidesDay: hidesDay, now: now) {
                    WidgetMetaLine(task: task, now: now, hidesDay: hidesDay)
                        .frame(height: WidgetLook.rowMetaLine)
                }
            }
            Spacer(minLength: 0)
        }
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }

    /// Whether the row has a second line: a time, a date it doesn't share with its header, a repeat, a switch, a Group.
    static func hasMeta(_ task: WidgetSnapshot.Task, hidesDay: Bool, now: Date) -> Bool {
        if isSwitch(task, now: now) || task.groupName != nil { return true }
        guard task.due != nil else { return false }
        return !hidesDay || task.hasTime || task.isRecurring
    }

    /// An opted-in switch listed as today's (brief 72): its row shows the switch glyph, never a date.
    static func isSwitch(_ task: WidgetSnapshot.Task, now: Date) -> Bool {
        FlipboardSwitch.side(of: task, now: now) == .red
    }

    func height() -> CGFloat {
        WidgetLook.rowHeight(hasMeta: style == .full && Self.hasMeta(task, hidesDay: hidesDay, now: now))
    }
}

/// The ring a row starts with: an open circle in the priority's colour, as the app's rows (`TaskRowCheckbox`). P4's
/// `Color.secondary` all but disappears on a widget's background, so it takes the palette's secondary text instead.
struct WidgetCheckRing: View {
    let priority: Int
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        let value = Priority(clamping: priority)
        Image(systemName: "circle")
            .font(.system(size: WidgetLook.ringSize, weight: WidgetLook.ringWeight))
            .foregroundStyle(value == .p4 ? palette.secondaryText : value.color)
            .widgetAccentable()
            .frame(width: WidgetLook.ringSize + 2, height: WidgetLook.rowTitleLine)
            .accessibilityHidden(true)
    }
}

/// The row's second line: the time (or date) in its due colour with the app's icons, then the Group, name and dot, at
/// the trailing end. Labels, reminders and checklists stay in the app.
struct WidgetMetaLine: View {
    let task: WidgetSnapshot.Task
    let now: Date
    var hidesDay = true

    var body: some View {
        HStack(spacing: HITSpacing.s) {
            WidgetWhen(task: task, now: now, hidesDay: hidesDay).layoutPriority(1)
            Spacer(minLength: HITSpacing.xs)
            if let name = task.groupName {
                WidgetMetaItem(text: name, systemImage: "circle.fill", tint: Color(hex: task.groupColorHex ?? "#9A9A9A"),
                               iconSize: 7, trailing: true)
            }
        }
        .lineLimit(1)
    }
}

/// When a row's task is due, as its second line starts: the switch glyph for a switch listed as today's; the date and
/// time with the calendar icon where the header doesn't name the day; the time with the clock (or repeat) icon where it
/// does; the repeat icon alone for a repeating all-day task. In its due colour (`HITColor.due`).
struct WidgetWhen: View {
    let task: WidgetSnapshot.Task
    let now: Date
    var hidesDay = true
    /// A one-line row's: an overdue task's day without its time ("Yesterday"), so the title keeps its room.
    var short = false

    var body: some View {
        if WidgetTaskRow.isSwitch(task, now: now) {
            WidgetMetaItem(text: nil, systemImage: "switch.2", tint: HITColor.dueToday)
        } else if let due = task.due {
            let tint = HITColor.due(due, hasTime: task.hasTime, now: now)
            if !hidesDay {
                WidgetMetaItem(text: DueFormatter.text(for: due, hasTime: task.hasTime && !short, now: now),
                               systemImage: task.isRecurring ? "repeat" : "calendar", tint: tint)
            } else if task.hasTime {
                WidgetMetaItem(text: DueFormatter.timeText(for: due),
                               systemImage: task.isRecurring ? "repeat" : "clock", tint: tint)
            } else if task.isRecurring {
                WidgetMetaItem(text: nil, systemImage: "repeat", tint: tint)
            }
        }
    }
}

/// One item of a second line: a small icon and its text 4 pt apart (the app's `MetaItem`).
struct WidgetMetaItem: View {
    let text: String?
    let systemImage: String
    let tint: Color
    var iconSize: CGFloat = 10
    var trailing = false

    var body: some View {
        HStack(spacing: 4) {
            if !trailing { icon }
            if let text { Text(text).font(WidgetLook.rowMeta) }
            if trailing { icon }
        }
        .foregroundStyle(tint)
    }

    private var icon: some View {
        Image(systemName: systemImage).font(.system(size: iconSize, weight: .semibold))
    }
}

/// The calm line a widget shows when there is nothing to list, never an empty box.
struct WidgetNote: View {
    let text: String
    var systemImage: String? = nil
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)).foregroundStyle(HITColor.dueToday)
                    .widgetAccentable()
            }
            Text(text).font(WidgetLook.note).foregroundStyle(palette.secondaryText)
        }
        .lineLimit(2)
    }
}
