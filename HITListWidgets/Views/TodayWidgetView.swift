import SwiftUI
import WidgetKit
import HITListCore

/// The Today widget (brief 74): "Today", its count, then the rows Today shows in its order. Small: three titles.
/// Medium: the count large on the left, four or five rows with their second lines on the right. Large: Overdue and
/// today under their headers, as the list has them. Nothing due: one calm line. A row opens its task; the rest of the
/// widget opens Today (a small widget is one tap: Today).
struct TodayWidgetView: View {
    /// Nil until the app has written its first snapshot.
    let snapshot: WidgetSnapshot?
    let now: Date
    let family: WidgetFamily
    @Environment(\.widgetPalette) private var palette
    @Environment(\.widgetOffscreen) private var offscreen

    private var content: WidgetContent.Today? { snapshot.map { WidgetContent.today($0, at: now) } }

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            case .systemLarge: large
            default: small
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(DeepLink.today.url)
    }

    // MARK: Families

    private var small: some View {
        VStack(alignment: .leading, spacing: WidgetLook.headerGap) {
            header
            if let content, !content.isEmpty {
                rows(content.rows.map { ($0, $0.isOverdue(now: now)) }, style: .titleOnly, links: false)
            } else {
                emptyNote
            }
        }
    }

    private var medium: some View {
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
                rows(content.rows.map { ($0, $0.isOverdue(now: now)) }, style: .titleAndTime, links: true)
            } else {
                emptyNote.frame(maxHeight: .infinity)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: WidgetLook.headerGap) {
            header
            if let content, !content.isEmpty {
                sections(content)
            } else {
                emptyNote
            }
        }
    }

    // MARK: Parts

    private var header: some View {
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

    private var emptyNote: some View {
        WidgetNote(text: snapshot == nil ? "Open HITList to fill this in." : "Nothing due today.",
                   systemImage: snapshot == nil ? nil : "checkmark")
    }

    /// As many rows as fit, then "+N more" for the rest.
    private func rows(_ rows: [(task: WidgetSnapshot.Task, overdue: Bool)], style: WidgetTaskRow.Style, links: Bool) -> some View {
        GeometryReader { proxy in
            let made = rows.map { WidgetTaskRow(task: $0.task, now: now, hidesDay: !$0.overdue, style: style) }
            let shown = WidgetLook.rowsThatFit(made.map { $0.height() }, in: proxy.size.height, reserve: Self.moreLine)
            VStack(alignment: .leading, spacing: WidgetLook.rowSpacing) {
                ForEach(Array(made.prefix(shown).enumerated()), id: \.offset) { _, row in
                    linked(row, links: links)
                }
                if shown < rows.count { more(rows.count - shown) }
            }
        }
    }

    /// Large: "Overdue" in red over its rows, then today's date in green over today's, as the list's headers.
    private func sections(_ content: WidgetContent.Today) -> some View {
        GeometryReader { proxy in
            let items = Self.sectionItems(content, now: now)
            let shown = WidgetLook.rowsThatFit(items.map(\.height), in: proxy.size.height, reserve: Self.moreLine)
            let hiddenRows = items.dropFirst(shown).filter { $0.row != nil }.count
            VStack(alignment: .leading, spacing: WidgetLook.rowSpacing) {
                ForEach(Array(items.prefix(shown).enumerated()), id: \.offset) { _, item in
                    if let row = item.row {
                        linked(row, links: true)
                    } else {
                        Text(item.title)
                            .font(WidgetLook.section)
                            .foregroundStyle(item.color)
                            .frame(height: Self.sectionLine, alignment: .bottom)
                    }
                }
                if hiddenRows > 0 { more(hiddenRows) }
            }
        }
    }

    private struct SectionItem {
        var row: WidgetTaskRow?
        var title = ""
        var color = Color.clear
        var height: CGFloat { row?.height() ?? TodayWidgetView.sectionLine }
    }

    private static let sectionLine: CGFloat = 14
    private static let moreLine: CGFloat = 14 + WidgetLook.rowSpacing

    private static func sectionItems(_ content: WidgetContent.Today, now: Date) -> [SectionItem] {
        var items: [SectionItem] = []
        if !content.overdue.isEmpty {
            items.append(SectionItem(title: "Overdue", color: HITColor.dueOverdue))
            items += content.overdue.map { SectionItem(row: WidgetTaskRow(task: $0, now: now, hidesDay: false)) }
        }
        if !content.today.isEmpty {
            items.append(SectionItem(title: DueFormatter.dayTitle(for: now, now: now), color: HITColor.dueToday))
            items += content.today.map { SectionItem(row: WidgetTaskRow(task: $0, now: now)) }
        }
        return items
    }

    @ViewBuilder
    private func linked(_ row: WidgetTaskRow, links: Bool) -> some View {
        if links, !offscreen {
            Link(destination: row.task.isShared ? DeepLink.today.url : DeepLink.task(row.task.id).url) { row }
        } else {
            row
        }
    }

    private func more(_ count: Int) -> some View {
        Text("+\(count) more")
            .font(WidgetLook.section)
            .foregroundStyle(palette.secondaryText)
            .padding(.leading, WidgetLook.ringSize + 2 + WidgetLook.ringGap)
            .frame(height: 14)
    }
}

extension WidgetSnapshot.Task {
    /// In Today's Overdue section: due before today, and not a switch listed as today's.
    func isOverdue(now: Date) -> Bool {
        TaskOrdering.todaySection(of: self, now: now) == .overdue
    }
}
