import SwiftUI
import WidgetKit
import HITListCore

/// The Today widget (brief 74): "Today", its count, then the rows Today shows in its order. Small: three titles.
/// Medium: the count large on the left, four rows with their times on the right. Large: Overdue and today under their
/// headers, as the list has them. Nothing due: one calm line. A row's title opens its task; the rest of the widget opens
/// Today (a small widget's only link is Today).
///
/// Brief 81: each row's check completes it (`WidgetTaskRow`). A tap's row stays, checked, until iCloud has the
/// completion (`WidgetContent.marks`, from the snapshot and the outbox `requests`), and the widget adds a quiet line
/// when a tap waits or the snapshot is more than a day old.
struct TodayWidgetView: View {
    /// Nil until the app has written its first snapshot.
    let snapshot: WidgetSnapshot?
    let now: Date
    let family: WidgetFamily
    /// The taps in the outbox, as the extension read them with the snapshot.
    var requests: [WidgetRequest] = []
    @Environment(\.widgetPalette) private var palette
    @Environment(\.widgetOffscreen) private var offscreen

    private var marks: WidgetContent.Marks? {
        snapshot.map { WidgetContent.marks($0, requests: requests, at: now) }
    }

    var body: some View {
        let marks = marks
        let content = marks.map { WidgetContent.today($0.snapshot, at: now) }
        Group {
            switch family {
            case .systemMedium: medium(content, marks)
            case .systemLarge: large(content, marks)
            default: small(content, marks)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(DeepLink.today.url)
    }

    // MARK: Families

    private func small(_ content: WidgetContent.Today?, _ marks: WidgetContent.Marks?) -> some View {
        VStack(alignment: .leading, spacing: WidgetLook.headerGap) {
            header(content)
            if let content, !content.isEmpty {
                rows(content.rows.map { ($0, $0.isOverdue(now: now)) }, style: .titleOnly, links: false, marks: marks)
            } else {
                emptyNote
            }
        }
    }

    private func medium(_ content: WidgetContent.Today?, _ marks: WidgetContent.Marks?) -> some View {
        HStack(alignment: .top, spacing: HITSpacing.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(WidgetLook.header).foregroundStyle(palette.text)
                Text("\(content?.count ?? 0)")
                    .font(WidgetLook.bigCount.monospacedDigit())
                    .foregroundStyle(palette.accent)
                    .widgetAccentable()
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Text(now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(WidgetLook.section)
                    .foregroundStyle(HITColor.dueToday)
            }
            .frame(width: 76, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            if let content, !content.isEmpty {
                rows(content.rows.map { ($0, $0.isOverdue(now: now)) }, style: .titleAndTime, links: true, marks: marks)
            } else {
                emptyNote.frame(maxHeight: .infinity)
            }
        }
    }

    private func large(_ content: WidgetContent.Today?, _ marks: WidgetContent.Marks?) -> some View {
        VStack(alignment: .leading, spacing: WidgetLook.headerGap) {
            header(content)
            if let content, !content.isEmpty {
                sections(content, marks: marks)
            } else {
                emptyNote
            }
        }
    }

    // MARK: Parts

    private func header(_ content: WidgetContent.Today?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today").font(WidgetLook.header).foregroundStyle(palette.text)
            Spacer(minLength: HITSpacing.s)
            if let content, !content.isEmpty {
                Text("\(content.count)")
                    .font(WidgetLook.header.monospacedDigit())
                    .foregroundStyle(palette.accent)
                    .widgetAccentable()
                    .contentTransition(.numericText())
            }
        }
    }

    /// Nothing due, or nothing to read yet (no snapshot: a fresh install, or the App Group unreadable).
    private var emptyNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetNote(text: snapshot == nil ? WidgetEmpty.openOnce : "Nothing due today.",
                       systemImage: snapshot == nil ? nil : "checkmark")
            if let note = marks?.note { WidgetQuietLine(note: note, now: now) }
        }
    }

    private func row(_ task: WidgetSnapshot.Task, overdue: Bool, style: WidgetTaskRow.Style, links: Bool,
                     marks: WidgetContent.Marks?) -> WidgetTaskRow {
        WidgetTaskRow(task: task, now: now, hidesDay: !overdue, style: style, checked: marks?.isChecked(task.id) ?? false,
                      widget: offscreen ? nil : TodayWidgetView.kind,
                      link: links && !offscreen ? (task.isShared ? DeepLink.today.url : DeepLink.task(task.id).url) : nil)
    }

    static let kind = "today"

    /// As many rows as fit, then "+N more" for the rest, then the quiet line when there is one.
    private func rows(_ rows: [(task: WidgetSnapshot.Task, overdue: Bool)], style: WidgetTaskRow.Style, links: Bool,
                      marks: WidgetContent.Marks?) -> some View {
        GeometryReader { proxy in
            let made = rows.map { row($0.task, overdue: $0.overdue, style: style, links: links, marks: marks) }
            let note = marks?.note
            let room = proxy.size.height - (note == nil ? 0 : Self.noteLine)
            let gaps = made.map { $0.gap(spacing: WidgetLook.rowSpacing) }
            let shown = WidgetLook.itemsThatFit(made.map { $0.height() }, gaps: gaps, in: room,
                                                reserve: Self.moreLine(after: gaps.first))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(made.prefix(shown).enumerated()), id: \.offset) { index, row in
                    row.padding(.top, index == 0 ? 0 : gaps[index - 1])
                }
                if shown < rows.count { more(rows.count - shown).padding(.top, shown == 0 ? 0 : gaps[shown - 1]) }
                if let note {
                    Spacer(minLength: 0)
                    WidgetQuietLine(note: note, now: now).padding(.leading, WidgetLook.checkColumn)
                }
            }
            .frame(height: proxy.size.height, alignment: .top)
        }
    }

    /// Large: "Overdue" in red over its rows, then today's date in green over today's, as the list's headers.
    private func sections(_ content: WidgetContent.Today, marks: WidgetContent.Marks?) -> some View {
        GeometryReader { proxy in
            let items = sectionItems(content, marks: marks)
            let note = marks?.note
            let room = proxy.size.height - (note == nil ? 0 : Self.noteLine)
            let gaps = items.map(\.gap)
            let shown = WidgetLook.itemsThatFit(items.map(\.height), gaps: gaps, in: room,
                                                reserve: Self.moreLine(after: WidgetLook.rowSpacing))
            let hiddenRows = items.dropFirst(shown).filter { $0.row != nil }.count
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.prefix(shown).enumerated()), id: \.offset) { index, item in
                    Group {
                        if let row = item.row {
                            row
                        } else {
                            Text(item.title)
                                .font(WidgetLook.section)
                                .foregroundStyle(item.color)
                                .frame(height: Self.sectionLine, alignment: .bottom)
                        }
                    }
                    .padding(.top, index == 0 ? 0 : gaps[index - 1])
                }
                if hiddenRows > 0 { more(hiddenRows).padding(.top, shown == 0 ? 0 : gaps[shown - 1]) }
                if let note {
                    Spacer(minLength: 0)
                    WidgetQuietLine(note: note, now: now).padding(.leading, WidgetLook.checkColumn)
                }
            }
            .frame(height: proxy.size.height, alignment: .top)
        }
    }

    private struct SectionItem {
        var row: WidgetTaskRow?
        var title = ""
        var color = Color.clear
        var height: CGFloat { row?.height() ?? TodayWidgetView.sectionLine }
        var gap: CGFloat { row?.gap(spacing: WidgetLook.rowSpacing) ?? WidgetLook.rowSpacing }
    }

    private static let sectionLine: CGFloat = 14
    /// The "+N more" line and the gap above it: a row's own gap (none under a row grown to the minimum target).
    private static func moreLine(after gap: CGFloat?) -> CGFloat { 14 + (gap ?? WidgetLook.rowSpacing) }
    /// The quiet line and the space above it.
    private static let noteLine: CGFloat = WidgetQuietLine.height + 4

    private func sectionItems(_ content: WidgetContent.Today, marks: WidgetContent.Marks?) -> [SectionItem] {
        var items: [SectionItem] = []
        if !content.overdue.isEmpty {
            items.append(SectionItem(title: "Overdue", color: HITColor.dueOverdue))
            items += content.overdue.map {
                SectionItem(row: row($0, overdue: true, style: .full, links: true, marks: marks))
            }
        }
        if !content.today.isEmpty {
            items.append(SectionItem(title: DueFormatter.dayTitle(for: now, now: now), color: HITColor.dueToday))
            items += content.today.map { SectionItem(row: row($0, overdue: false, style: .full, links: true, marks: marks)) }
        }
        return items
    }

    private func more(_ count: Int) -> some View {
        Text("+\(count) more")
            .font(WidgetLook.section)
            .foregroundStyle(palette.secondaryText)
            .padding(.leading, WidgetLook.checkColumn)
            .frame(height: 14)
    }
}

extension WidgetSnapshot.Task {
    /// In Today's Overdue section: due before today, and not a switch listed as today's.
    func isOverdue(now: Date) -> Bool {
        TaskOrdering.todaySection(of: self, now: now) == .overdue
    }
}

/// The words a widget says before it has anything to show (brief 81, rule 7): what to do, never an empty box.
enum WidgetEmpty {
    /// No snapshot yet (the app never opened on this device, or this build), or the App Group couldn't be read.
    static let openOnce = "Open HITList once to fill this in."
}
