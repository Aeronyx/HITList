import CoreText
import Foundation
import OSLog
import WidgetKit
import HITListCore

/// The snapshot the app writes (brief 74), read from the App Group container: the only thing the extension reads.
enum WidgetSnapshotStore {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "widgets")

    /// The real store's file; in a Debug build made with `HITLIST_WIDGET_SUFFIX=<name>` (project.yml), that side store's,
    /// so a session's demo week shows in real widgets without touching George's.
    static var fileName: String { WidgetSnapshot.fileName(suffix: suffix) }

    /// The side store this Debug build reads (`HITLIST_WIDGET_SUFFIX`); nil, the real store's, in Release. The outbox
    /// beside the snapshot follows it (`WidgetIntentRoad`).
    static var suffix: String? {
        #if DEBUG
        return Bundle.main.object(forInfoDictionaryKey: "HITListWidgetSuffix") as? String
        #else
        return nil
        #endif
    }

    /// Nil until the app has written one (a fresh install), or if it can't be read.
    static func read() -> WidgetSnapshot? {
        guard let url = AppGroup.containerURL?.appending(path: fileName) else {
            log.error("widget: no App Group container \(AppGroup.id, privacy: .public)")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try WidgetSnapshot.decode(data)
        } catch {
            log.error("widget: snapshot unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// One moment of a widget's timeline.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// The taps in the outbox when it was read (brief 81): their rows are drawn checked.
    var requests: [WidgetRequest] = []
}

/// The widget's taps on their way (brief 81), read from the outbox beside the snapshot.
enum WidgetOutboxStore {
    static func read() -> [WidgetRequest] { WidgetIntentRoad.outbox?.read().requests ?? [] }
}

enum SnapshotTimeline {
    /// Entries now and at each moment the content can change (`WidgetContent.changes`: midnights, resets, due times),
    /// or its quiet line can (`WidgetContent.noteChanges`: a tap's patience running out, the snapshot a day old);
    /// WidgetKit asks again after the last.
    static func entries(_ snapshot: WidgetSnapshot?, requests: [WidgetRequest] = [], now: Date = Date()) -> [SnapshotEntry] {
        var moments: [Date] = []
        if let snapshot {
            let drawn: WidgetSnapshot = WidgetContent.marks(snapshot, requests: requests, at: now).snapshot
            let content: [Date] = WidgetContent.changes(drawn, after: now)
            let notes: [Date] = WidgetContent.noteChanges(snapshot, requests: requests, after: now)
            moments = Set(content + notes).sorted()
        }
        return ([now] + moments).map { SnapshotEntry(date: $0, snapshot: snapshot, requests: requests) }
    }

    static func timeline(now: Date = Date(), context: TimelineProviderContext? = nil, kind: String) -> Timeline<SnapshotEntry> {
        WidgetFonts.register()
        if let context {
            Logger(subsystem: "com.trammells.hitlist", category: "widgets")
                .notice("widget \(kind, privacy: .public) \(String(describing: context.family), privacy: .public): \(Int(context.displaySize.width))×\(Int(context.displaySize.height)) pt")
        }
        let entries = entries(WidgetSnapshotStore.read(), requests: WidgetOutboxStore.read(), now: now)
        // Without a snapshot there is nothing to change at; look again in an hour (the app's first write reloads sooner).
        let policy: TimelineReloadPolicy = entries.count > 1 ? .atEnd : .after(now.addingTimeInterval(3600))
        return Timeline(entries: entries, policy: policy)
    }
}

/// Inter, registered for the extension's process. Its Info.plist lists the cuts too (`UIAppFonts`,
/// `ATSApplicationFontsPath`); registering by URL is the belt to those braces, and a cut already there is left alone.
enum WidgetFonts {
    private static let names = ["Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]

    static func register() {
        for name in names {
            let postScript = "Inter18pt-\(name)"
            let font = CTFontCreateWithName(postScript as CFString, 12, nil)
            guard CTFontCopyPostScriptName(font) as String != postScript,
                  let url = Bundle.main.url(forResource: "Inter_18pt-\(name)", withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
