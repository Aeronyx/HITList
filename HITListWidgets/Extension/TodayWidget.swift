import SwiftUI
import WidgetKit
import HITListCore

/// Today on the Home Screen, the Mac's desktop and Notification Centre (brief 74).
struct TodayWidget: Widget {
    static let kind = "today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider(kind: Self.kind)) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("What's due today and what's overdue, in Today's order.")
        .supportedFamilies(Self.families)
    }

    #if os(iOS)
    /// The Lock Screen's three as well (brief 74, item 7).
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge,
                                           .accessoryCircular, .accessoryRectangular, .accessoryInline]
    #else
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    #endif
}

private struct TodayWidgetEntryView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let palette = ThemePalette.named(entry.snapshot?.themeID)
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            TodayLockScreenView(snapshot: entry.snapshot, now: entry.date, family: family, requests: entry.requests)
                .containerBackground(for: .widget) { Color.clear }
        default:
            TodayWidgetView(snapshot: entry.snapshot, now: entry.date, family: family, requests: entry.requests)
                .environment(\.widgetPalette, palette)
                .widgetBackground(palette)
        }
    }
}

/// The timeline every snapshot widget shares: the file, judged at each moment its content can change.
struct SnapshotProvider: TimelineProvider {
    let kind: String

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetSamples.snapshot(now: Date()))
    }

    /// The gallery's preview: your own tasks when the app has written them, a believable sample before.
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        WidgetFonts.register()
        let now = Date()
        completion(SnapshotEntry(date: now, snapshot: WidgetSnapshotStore.read() ?? WidgetSamples.snapshot(now: now),
                                 requests: WidgetOutboxStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(SnapshotTimeline.timeline(context: context, kind: kind))
    }
}
