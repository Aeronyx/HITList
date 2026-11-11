import SwiftUI
import WidgetKit
import HITListCore

/// Upcoming: a little calendar and the next tasks (brief 74).
struct UpcomingWidget: Widget {
    static let kind = "upcoming"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider(kind: Self.kind)) { entry in
            UpcomingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Upcoming")
        .description("This week or this month, with a dot on each day that has tasks, and what's next.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct UpcomingWidgetEntryView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let palette = ThemePalette.named(entry.snapshot?.themeID)
        UpcomingWidgetView(snapshot: entry.snapshot, now: entry.date, family: family, requests: entry.requests)
            .environment(\.widgetPalette, palette)
            .widgetBackground(palette)
    }
}
