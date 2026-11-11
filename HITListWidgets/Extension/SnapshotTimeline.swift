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
    static var fileName: String {
        #if DEBUG
        let suffix = Bundle.main.object(forInfoDictionaryKey: "HITListWidgetSuffix") as? String
        return WidgetSnapshot.fileName(suffix: suffix)
        #else
        return WidgetSnapshot.mainFileName
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
}

enum SnapshotTimeline {
    /// Entries now and at each moment the content can change (`WidgetContent.changes`: midnights, resets, due times);
    /// WidgetKit asks again after the last.
    static func entries(_ snapshot: WidgetSnapshot?, now: Date = Date()) -> [SnapshotEntry] {
        let moments = snapshot.map { WidgetContent.changes($0, after: now) } ?? []
        return ([now] + moments).map { SnapshotEntry(date: $0, snapshot: snapshot) }
    }

    static func timeline(now: Date = Date(), context: TimelineProviderContext? = nil, kind: String) -> Timeline<SnapshotEntry> {
        WidgetFonts.register()
        if let context {
            Logger(subsystem: "com.trammells.hitlist", category: "widgets")
                .notice("widget \(kind, privacy: .public) \(String(describing: context.family), privacy: .public): \(Int(context.displaySize.width))×\(Int(context.displaySize.height)) pt")
        }
        let entries = entries(WidgetSnapshotStore.read(), now: now)
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
