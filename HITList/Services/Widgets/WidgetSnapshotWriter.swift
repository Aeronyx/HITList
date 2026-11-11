import Foundation
import Observation
import OSLog
import SwiftData
import WidgetKit
import HITListCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Keeps the widgets' snapshot current (brief 74). Started once from `HITListApp`; from then on it writes the snapshot
/// into the App Group container (`HITList.widgets.json`, or a side store's own: `HITList-<suffix>.widgets.json`) a
/// moment after every save to the task store, every finished CloudKit import, a change to the shared tasks, the theme
/// or the week start, and each time the app comes forward, then asks WidgetKit to reload the widgets. A write that
/// would change nothing is skipped, so the widgets' reload budget goes on real changes.
///
/// It never writes while the store couldn't be opened (the in-memory fallback is empty, and the widgets would say
/// nothing is due).
@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    static func start(container: ModelContainer) { shared.start(container) }

    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "widgets")

    private let fileURL: () -> URL?
    private let reload: () -> Void
    /// Whether the store has heard from iCloud since a moment (brief 81): an unchanged snapshot is written again, to say
    /// it is still current, only then.
    private let confirmedSince: @MainActor (Date) -> Bool
    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private let debounce = Debouncer(delay: .milliseconds(800))
    /// The last snapshot written or found on disk.
    private(set) var last: WidgetSnapshot?

    /// The file this process writes: the store's own (`WidgetSnapshot.fileName(suffix:)`).
    nonisolated static var defaultFileURL: URL? {
        AppGroup.containerURL?.appending(path: WidgetSnapshot.fileName(suffix: ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"]))
    }

    init(fileURL: @escaping () -> URL? = { WidgetSnapshotWriter.defaultFileURL },
         reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
         confirmedSince: @escaping @MainActor (Date) -> Bool = { WidgetSnapshotWriter.storeConfirmed(since: $0) }) {
        self.fileURL = fileURL
        self.reload = reload
        self.confirmedSince = confirmedSince
    }

    /// An unchanged snapshot is written again after this long (brief 81), so a widget says "As of yesterday" only when
    /// its tasks may really be a day out of date (`WidgetContent.staleAfter`), not because nothing changed.
    static let refreshAfter: TimeInterval = 6 * 3600

    /// The store has heard from iCloud since `date` (an import), or it has nothing to hear (local only, signed out).
    static func storeConfirmed(since date: Date) -> Bool {
        let monitor = CloudSyncMonitor.shared
        if monitor.finishLine == .save { return true }
        return monitor.lastImportAt.map { $0 > date } ?? false
    }

    private func start(_ container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
                // TipKit's datastore saves post this too; only the task store's count.
                let saved = (note.object as? ModelContext)?.container
                MainActor.assumeIsolated { if saved === self?.container { self?.schedule() } }
            },
            center.addObserver(forName: .cloudKitImportSucceeded, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            },
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.settingsMayHaveChanged() }
            },
            center.addObserver(forName: Self.becameActive, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            },
        ]
        watchSharedRows()
        writeNow()
    }

    #if os(macOS)
    private static let becameActive = NSApplication.didBecomeActiveNotification
    #else
    private static let becameActive = UIApplication.didBecomeActiveNotification
    #endif

    /// Defaults change for many reasons (window frames, the last screen); only the theme and the week start matter.
    private func settingsMayHaveChanged() {
        guard let last else { return schedule() }
        if last.themeID != ThemeStore.shared.palette.id || last.weekStart != Preferences.weekStartWeekday() { schedule() }
    }

    /// Shared Tasks (brief 62) live in their own store; a sync or a completion there changes Today too.
    private func watchSharedRows() {
        withObservationTracking {
            _ = SharedRows.shared.open
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.watchSharedRows()
                self?.schedule()
            }
        }
    }

    func schedule() {
        debounce.schedule { [weak self] in self?.writeNow() }
    }

    /// Builds the snapshot and writes it if anything changed.
    func writeNow(now: Date = Date()) {
        guard let container, !ModelContainerFactory.isRunningInMemory else { return }
        do {
            // Brief 81: the widgets' taps the app is finishing, and the sync state they wait on.
            let snapshot = try WidgetSnapshotBuilder.build(from: container.mainContext, shared: SharedRows.shared.open,
                                                           themeID: ThemeStore.shared.palette.id,
                                                           weekStart: Preferences.weekStartWeekday(), now: now,
                                                           pending: WidgetCompletionCenter.shared?.pending ?? [],
                                                           sync: CloudSyncMonitor.shared.widgetSync)
            try write(snapshot)
        } catch {
            Self.log.error("widget snapshot not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether an unchanged `snapshot` is worth writing over `last` to say it is still current: `refreshAfter` has passed
    /// and the store has heard from iCloud since `last` was written.
    private func confirmsAgain(_ last: WidgetSnapshot, with snapshot: WidgetSnapshot) -> Bool {
        snapshot.writtenAt.timeIntervalSince(last.writtenAt) >= Self.refreshAfter && confirmedSince(last.writtenAt)
    }

    /// Writes `snapshot` unless the file already says the same; true when it wrote (and asked for a reload).
    @discardableResult
    func write(_ snapshot: WidgetSnapshot) throws -> Bool {
        guard let url = fileURL() else { return false }
        if last == nil, let data = try? Data(contentsOf: url) { last = try? WidgetSnapshot.decode(data) }
        if let last, last.isSameContent(as: snapshot), !confirmsAgain(last, with: snapshot) { return false }
        #if os(iOS)
        // Lock Screen widgets draw while the phone is locked: readable after the first unlock, as the store is.
        let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        let options: Data.WritingOptions = [.atomic]
        #endif
        try snapshot.encoded().write(to: url, options: options)
        last = snapshot
        reload()
        Self.log.notice("widget snapshot written: \(snapshot.tasks.count) tasks, \(snapshot.switchboards.count) boards, \(url.lastPathComponent, privacy: .public)")
        return true
    }
}
