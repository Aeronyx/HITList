import SwiftUI
import WidgetKit

struct TodayWidget: Widget {
    static let kind = "today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
            Text("Today")
                .containerBackground(for: .widget) { ThemePalette.slate.background }
        }
        .configurationDisplayName("Today")
        .description("What's due today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) { completion(TodayEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        completion(Timeline(entries: [TodayEntry(date: Date())], policy: .never))
    }
}
