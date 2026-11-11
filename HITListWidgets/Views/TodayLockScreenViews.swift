import SwiftUI
import WidgetKit
import HITListCore

/// Today on the iPhone's Lock Screen (brief 74): circular, today's count; rectangular, the next two tasks; inline,
/// "3 tasks today". The Lock Screen draws them in one tint (vibrant), so they lean on weight and size, not colour.
/// Titles are `privacySensitive`: hidden while the phone is locked if Settings asks for it.
struct TodayLockScreenView: View {
    let snapshot: WidgetSnapshot?
    let now: Date
    let family: WidgetFamily

    private var content: WidgetContent.Today? { snapshot.map { WidgetContent.today($0, at: now) } }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .widgetURL(DeepLink.today.url)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -1) {
                Text("\(content?.count ?? 0)")
                    .font(HITFont.inter(content.map { $0.count > 99 } == true ? 18 : 24, .bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text("Today")
                    .font(HITFont.inter(9, .semibold))
                    .textCase(.uppercase)
                    .opacity(0.8)
            }
            .padding(6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.inlineText(content?.count ?? 0))
    }

    /// "Today 3", then the first two of Today's rows: the title and, at its end, its time.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("Today").font(HITFont.inter(13, .bold))
                if let content, !content.isEmpty {
                    Text("\(content.count)").font(HITFont.inter(13, .bold).monospacedDigit()).opacity(0.7)
                }
                Spacer(minLength: 0)
            }
            .widgetAccentable()
            if let content, !content.isEmpty {
                ForEach(content.rows.prefix(2)) { task in
                    HStack(spacing: 5) {
                        Image(systemName: "circle").font(.system(size: 10, weight: .semibold))
                        Text(task.title).font(HITFont.inter(13, .regular)).lineLimit(1)
                        Spacer(minLength: 0)
                        if let due = task.due, task.hasTime, !task.isOverdue(now: now) {
                            Text(DueFormatter.timeText(for: due)).font(HITFont.inter(11, .medium)).opacity(0.7).fixedSize()
                        }
                    }
                    .privacySensitive()
                }
            } else {
                Text(snapshot == nil ? "Open HITList" : "Nothing due today.")
                    .font(HITFont.inter(13, .regular)).opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var inline: some View {
        // Inline widgets draw in the system font; only the words and the symbol are ours.
        Label(Self.inlineText(content?.count ?? 0), systemImage: "checklist")
    }

    /// "3 tasks today", "1 task today", "Nothing due today".
    static func inlineText(_ count: Int) -> String {
        switch count {
        case 0: "Nothing due today"
        case 1: "1 task today"
        default: "\(count) tasks today"
        }
    }
}
