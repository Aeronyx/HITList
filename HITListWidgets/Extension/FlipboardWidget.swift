import AppIntents
import SwiftUI
import WidgetKit
import HITListCore

/// The Flipboard as a status check (brief 74): the loose switches, or one Switchboard chosen in the widget's settings.
struct FlipboardWidget: Widget {
    static let kind = "flipboard"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: FlipboardWidgetIntent.self, provider: FlipboardProvider()) { entry in
            FlipboardWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Flipboard")
        .description("Your switches, green or red as the board has them: the loose ones, or one Switchboard.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The widget's one setting: which switches it shows.
struct FlipboardWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Flipboard"
    static let description = IntentDescription("Shows the loose switches, or one Switchboard.")

    @Parameter(title: "Switches")
    var board: SwitchboardChoice?

    init() {}

    init(board: SwitchboardChoice?) {
        self.board = board
    }
}

/// A choice in the widget's settings: the loose switches, or a Switchboard from the snapshot.
struct SwitchboardChoice: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Switchboard"
    static let defaultQuery = SwitchboardChoiceQuery()
    static let looseID = "loose"
    static let loose = SwitchboardChoice(id: looseID, name: "Loose switches")

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    /// The board it names; nil for the loose switches.
    var boardID: UUID? { id == Self.looseID ? nil : UUID(uuidString: id) }
}

struct SwitchboardChoiceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SwitchboardChoice] {
        choices().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SwitchboardChoice] { choices() }

    func defaultResult() async -> SwitchboardChoice? { .loose }

    /// The loose switches, then the Switchboards in the Flipboard's order.
    private func choices() -> [SwitchboardChoice] {
        let boards = WidgetSnapshotStore.read()?.switchboards ?? []
        return [.loose] + boards.map { SwitchboardChoice(id: $0.id.uuidString, name: $0.name) }
    }
}

struct FlipboardEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let boardID: UUID?
}

struct FlipboardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FlipboardEntry {
        FlipboardEntry(date: Date(), snapshot: WidgetSamples.snapshot(now: Date()), boardID: nil)
    }

    func snapshot(for configuration: FlipboardWidgetIntent, in context: Context) async -> FlipboardEntry {
        WidgetFonts.register()
        let now = Date()
        return FlipboardEntry(date: now, snapshot: WidgetSnapshotStore.read() ?? WidgetSamples.snapshot(now: now),
                              boardID: configuration.board?.boardID)
    }

    func timeline(for configuration: FlipboardWidgetIntent, in context: Context) async -> Timeline<FlipboardEntry> {
        let timeline = SnapshotTimeline.timeline(context: context, kind: FlipboardWidget.kind)
        return Timeline(entries: timeline.entries.map {
            FlipboardEntry(date: $0.date, snapshot: $0.snapshot, boardID: configuration.board?.boardID)
        }, policy: timeline.policy)
    }
}

private struct FlipboardWidgetEntryView: View {
    let entry: FlipboardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let palette = ThemePalette.named(entry.snapshot?.themeID)
        FlipboardWidgetView(snapshot: entry.snapshot, boardID: entry.boardID, now: entry.date, family: family)
            .environment(\.widgetPalette, palette)
            .widgetBackground(palette)
    }
}
