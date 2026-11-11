#if DEBUG
import Foundation
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
