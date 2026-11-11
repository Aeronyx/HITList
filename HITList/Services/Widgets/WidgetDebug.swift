#if DEBUG
import Foundation
import SwiftData
import HITListCore

/// Debug only (brief 81): what lets a session see a widget's tap go all the way through on its own simulator or Mac
/// without touching George's store or iCloud.
enum WidgetDebug {
    /// A Debug build made with `HITLIST_WIDGET_SUFFIX=<name>` (project.yml) reads that side store's snapshot in its
    /// widgets. When the system launches the app for a widget's tap (iPhone: in the background, without the
    /// environment and arguments a session's own launch gave it), the app opens that side store with sync off, exactly
    /// as `HITLIST_STORE_SUFFIX=<name> … -disableCloudKit YES` would, never the real store. Called first in
    /// `HITListApp.init`. A launch that names a store of its own keeps it.
    static func adoptBakedSideStore(environment: [String: String] = ProcessInfo.processInfo.environment,
                                    info: Bundle = .main) {
        guard environment["HITLIST_STORE_SUFFIX"]?.isEmpty ?? true,
              let suffix = info.object(forInfoDictionaryKey: "HITListWidgetSuffix") as? String, !suffix.isEmpty
        else { return }
        setenv("HITLIST_STORE_SUFFIX", suffix, 1)
        // The arguments' domain, in memory: this process only, as `-disableCloudKit YES` on the command line.
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["disableCloudKit"] = true
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    /// `-widgetExportDelay <seconds>` on a side store: with sync off, the widgets' taps wait that long for a pretend
    /// export instead of finishing at the save, so the checked row can be seen before it leaves. Kept in the side store's
    /// own settings (`AppGroup.defaults` is that store's suite), so the app the system launches later for a tap, which
    /// gets no arguments, keeps it too. Never on the real store.
    static let exportDelayKey = "debug.widgetExportDelay"

    static func exportDelay(arguments: [String] = ProcessInfo.processInfo.arguments,
                            suffix: String? = ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"],
                            defaults: UserDefaults = AppGroup.defaults) -> TimeInterval? {
        guard let suffix, !suffix.isEmpty, suffix != SyncStoreGuard.developmentSuffix else { return nil }
        if let index = arguments.firstIndex(of: "-widgetExportDelay"), arguments.indices.contains(index + 1),
           let seconds = TimeInterval(arguments[index + 1]) {
            defaults.set(seconds, forKey: exportDelayKey)
        }
        let seconds = defaults.double(forKey: exportDelayKey)
        return seconds > 0 ? seconds : nil
    }
}

extension WidgetDebug {
    /// `-widgetTapProbe` (a side store only): three seconds after launch, writes a tap on Today's first row into the
    /// outbox as the widget extension would, and nothing else (no drain), so the app picks it up only when something
    /// rings: on the Mac, `notifyutil -p <WidgetOutboxBell name>` from a shell, the extension's own Darwin notification.
    /// What a session can show of the Mac's road without a widget on the desktop.
    @MainActor
    static func probeTapIfRequested(outbox: WidgetOutbox, container: ModelContainer,
                                    arguments: [String] = ProcessInfo.processInfo.arguments,
                                    suffix: String? = ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"]) {
        guard arguments.contains("-widgetTapProbe"), let suffix, !suffix.isEmpty,
              suffix != SyncStoreGuard.developmentSuffix else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            let now = Date()
            let open = (try? container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted })))?
                .filter { !$0.isSubtask } ?? []
            let today = TaskOrdering.today(open, now: now)
            guard let task = (today.overdue + today.today).first(where: { !Flipboard.isMember($0) }),
                  var request = WidgetCompletionIntent(task: WidgetSnapshotBuilder.task(task, weekStart: Preferences.weekStartWeekday()),
                                                       action: .complete, widget: "today").request(at: now)
            else { return }
            request.recordedBy = "the Debug probe in \(WidgetIntentRoad.processDescription), standing in for the extension"
            do {
                try outbox.record(request)
                CloudSyncMonitor.shared.write(.note, "Widget: Debug probe wrote a tap on ‘\(task.title)’ into the outbox, as the extension would; it waits for the bell (\(WidgetOutboxBell.name(suffix: suffix)))")
            } catch {
                CloudSyncMonitor.shared.write(.note, "Widget: Debug probe couldn't write its tap: \(error.localizedDescription)", level: .error)
            }
        }
    }
}

/// `-widgetExportDelay`'s pretend sync: every export finishes `delay` seconds after it starts, with nothing wrong.
@MainActor
final class DelayedExports: WidgetSyncFacts {
    let delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    var finishLine: WidgetCompletion.FinishLine { .export }
    /// An export that started `delay` ago has just finished: a tap applied before then has reached "iCloud".
    var lastExportStart: Date? { Date().addingTimeInterval(-delay) }
    var canTellGone: Bool { true }
    var widgetSync: WidgetSnapshot.Sync { .fine }
}
#endif
