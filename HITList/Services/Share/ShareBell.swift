import Foundation
import HITListCore

/// Brief 90: where the share sheet's requests go, and the nudge that tells a running app one is there. Compiled into the
/// app and the share extension (project.yml), so both name the same folder and the same bell.
enum ShareRoad {
    /// The store's own outbox in the App Group: a side store's for a run on one (`HITLIST_STORE_SUFFIX` in the app, the
    /// baked suffix in a Debug extension), so a session's shares never reach George's app.
    static func outbox(suffix: String?) -> ShareOutbox? {
        ShareOutbox(container: AppGroup.containerURL, suffix: suffix)
    }

    static func ledgerURL(suffix: String?) -> URL? {
        AppGroup.containerURL?.appending(path: ShareLedger.fileName(suffix: suffix))
    }

    static func contextURL(suffix: String?) -> URL? {
        AppGroup.containerURL?.appending(path: ShareContext.fileName(suffix: suffix))
    }

    /// "HITListShare 812 com.trammells.hitlist.share": the process that did a thing, for the logs.
    static var processDescription: String {
        let info = ProcessInfo.processInfo
        return "\(info.processName) \(info.processIdentifier) \(Bundle.main.bundleIdentifier ?? "?")"
    }
}

/// A Darwin notification from the share extension to a running app: "a share is in the outbox". It carries nothing (the
/// outbox is the message), may be missed (a suspended iPhone app doesn't hear it) and is only a nudge: the app also
/// reads the outbox at launch, on activation and in the background refresh.
enum ShareOutboxBell {
    /// Prefixed with the App Group, the namespace a sandboxed app and its extension share; a side store has its own.
    static func name(suffix: String?) -> String {
        "\(AppGroup.id).share-outbox" + (suffix.map { $0.isEmpty ? "" : ".\($0)" } ?? "")
    }

    static func ring(suffix: String?) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name(suffix: suffix) as CFString), nil, nil, true)
    }
}
