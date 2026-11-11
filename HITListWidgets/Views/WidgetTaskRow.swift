import SwiftUI
import WidgetKit
import HITListCore

/// A task in a widget, as the app's `TaskRow` draws it: the priority ring in the task's colour, the title, and under it
/// the second line, here its time (or its date, for an overdue task) and its Group at the trailing end.
///
/// Brief 81: the ring is a toggle (`WidgetCompletionIntent`) that checks the task off; the title still opens it. A
/// widget's toggle is drawn in its new state the moment it is tapped, before the intent has run (on iPhone the system
/// may first have to launch the app), so the check turns at once; the reload that follows draws the row as a tap on its
/// way: the app's completed look (filled check, struck title) dimmed, its check no longer a toggle, until iCloud has the
/// completion. A short row is grown to the minimum tap target (`WidgetLook.rowFrame`).
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
    /// A tap on this row is on its way (`WidgetContent.Marks`).
    var checked = false
    /// The widget whose row this is ("today", "upcoming"): its check is a button. Nil draws the check only (the hosted
    /// tests' renders, which can't draw a button).
    var widget: String? = nil
    /// Where a tap on the title goes; nil: the widget's own link.
    var link: URL? = nil
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        let content = contentHeight
        let frame = WidgetLook.rowFrame(content)
        let inset = (frame - content) / 2
        HStack(alignment: .top, spacing: 0) {
            check(frame: frame, inset: inset)
            linked(details.padding(.top, inset).frame(maxWidth: .infinity, minHeight: frame, alignment: .topLeading))
        }
        .frame(height: frame, alignment: .top)
        .opacity(checked ? WidgetLook.pendingOpacity : 1)
        .privacySensitive()
    }

    /// The ring (or the check), its column the toggle: as tall as the row, as wide as the ring and its gap.
    @ViewBuilder
    private func check(frame: CGFloat, inset: CGFloat) -> some View {
        // A shared task completes in the shared store (brief 62), which the widget's road doesn't reach: it opens Today.
        if let widget, !checked, !task.isShared {
            Toggle(isOn: false, intent: WidgetCompletionIntent(task: task, action: .complete, widget: widget)) {
                Text("Complete \(task.title)")
            }
            .toggleStyle(WidgetCheckToggleStyle(priority: task.priority, height: frame, inset: inset))
            .accessibilityLabel("Complete \(task.title)")
        } else {
            WidgetCheckToggleStyle.mark(priority: task.priority, checked: checked, height: frame, inset: inset)
                .accessibilityLabel(checked ? "\(task.title), checked" : task.title)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: WidgetLook.lineGap) {
            HStack(spacing: HITSpacing.s) {
                Text(task.title)
                    .font(WidgetLook.rowTitle)
                    .tracking(HITType.taskTitleTracking)
                    .foregroundStyle(checked ? palette.secondaryText : palette.text)
                    .lineLimit(1)
                    // Drawn, not `strikethrough`: the Home Screen drops a Text's strike that an offscreen render keeps.
                    .overlay { if checked { Rectangle().fill(palette.secondaryText).frame(height: 1) } }
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
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func linked(_ view: some View) -> some View {
        if let link { Link(destination: link) { view } } else { view }
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

    /// The content's own height: the title line, and the second line when it has one.
    var contentHeight: CGFloat {
        WidgetLook.rowHeight(hasMeta: style == .full && Self.hasMeta(task, hidesDay: hidesDay, now: now))
    }

    /// The row's height in a list: its content, grown to the minimum target.
    func height() -> CGFloat { WidgetLook.rowFrame(contentHeight) }

    /// The gap under it in a list spaced `spacing` (`WidgetLook.gap`).
    func gap(spacing: CGFloat) -> CGFloat { WidgetLook.gap(after: contentHeight, spacing: spacing) }
}

/// A row's check as a toggle (brief 81): off, the ring; on (the moment it is tapped, and while its tap is on its way),
/// the app's filled check. Its frame is the toggle's target: the check's column, as tall as the row.
struct WidgetCheckToggleStyle: ToggleStyle {
    let priority: Int
    let height: CGFloat
    let inset: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Self.mark(priority: priority, checked: configuration.isOn, height: height, inset: inset)
    }

    static func mark(priority: Int, checked: Bool, height: CGFloat, inset: CGFloat) -> some View {
        WidgetCheckRing(priority: priority, checked: checked)
            .padding(.top, inset)
            .frame(width: WidgetLook.checkColumn, height: height, alignment: .topLeading)
            .contentShape(Rectangle())
    }
}

/// The ring a row starts with: an open circle in the priority's colour, as the app's rows (`TaskRowCheckbox`); checked,
/// the app's filled check. P4's `Color.secondary` all but disappears on a widget's background, so it takes the palette's
/// secondary text instead.
struct WidgetCheckRing: View {
    let priority: Int
    var checked = false
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        let value = Priority(clamping: priority)
        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
            .font(.system(size: WidgetLook.ringSize, weight: WidgetLook.ringWeight))
            .foregroundStyle(value == .p4 ? palette.secondaryText : value.color)
            .widgetAccentable()
            .frame(width: WidgetLook.ringSize + 2, height: WidgetLook.rowTitleLine)
            .accessibilityHidden(true)
    }
}

/// The widget's quiet line (brief 81): a tap waiting for the app or for iCloud, or a snapshot more than a day old. Never
/// an alarm: secondary text, the size of a section's header.
struct WidgetQuietLine: View {
    let note: WidgetContent.Note
    let now: Date
    @Environment(\.widgetPalette) private var palette

    static let height: CGFloat = 14

    var body: some View {
        Text(Self.text(note, now: now))
            .font(WidgetLook.section)
            .foregroundStyle(palette.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(height: Self.height)
    }

    static func text(_ note: WidgetContent.Note, now: Date) -> String {
        switch note {
        case .openApp: "Open HITList to finish"
        case .waitingForICloud: "Waiting for iCloud"
        case .asOf(let written): WidgetContent.asOfText(written, now: now)
        }
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
