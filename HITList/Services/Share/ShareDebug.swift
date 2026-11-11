#if DEBUG && os(macOS)
import AppKit
import OSLog
import HITListCore

/// Debug only (brief 90): what lets a session see the real share extension on the Mac without driving Safari (the
/// window scripts act on a Debug HITList only). `-shareProbe <address>` on a side store asks the system for the share
/// service called "HITList" for that address, as Safari's Share menu does, and opens it on this app's window three
/// seconds after launch. The extension is the real one (its own process, the card, the outbox); this app, running on the
/// same side store, hears its bell and makes the task, so the sheet can say "Added". Never on the real store.
@MainActor
enum ShareDebug {
    private static let log = Logger(subsystem: "com.trammells.hitlist", category: "share")
    private static let delegate = Delegate()

    static func presentIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments,
                                   suffix: String? = ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"]) {
        guard let index = arguments.firstIndex(of: "-shareProbe"), arguments.indices.contains(index + 1),
              let address = URL(string: arguments[index + 1]), let suffix, !suffix.isEmpty,
              suffix != SyncStoreGuard.developmentSuffix else { return }
        var items: [Any] = [address]
        if let textIndex = arguments.firstIndex(of: "-shareProbeText"), arguments.indices.contains(textIndex + 1) {
            items = [arguments[textIndex + 1]]
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            let services = NSSharingService.sharingServices(forItems: items)
            log.notice("share probe: services offered: \(services.map(\.title).joined(separator: ", "), privacy: .public)")
            guard let service = services.first(where: { $0.title == "HITList" }) else {
                CloudSyncMonitor.shared.write(.note, "Share: Debug probe found no “HITList” share service (registered? enabled in System Settings → Extensions?)", level: .error)
                return
            }
            service.delegate = delegate
            service.perform(withItems: items)
            CloudSyncMonitor.shared.write(.note, "Share: Debug probe opened the share extension for \(items.first.map { "\($0)" } ?? "")")
        }
    }

    /// `-shareBellProbe "<title>"` (a side store only): three seconds after launch, writes a share of the test page into
    /// the outbox as the extension does (the same `ShareRequest`, `ShareOutbox.record`), and nothing else (no drain), so
    /// the app makes it only when something rings: `notifyutil -p <ShareOutboxBell name>` from a shell is the
    /// extension's own Darwin notification. What a session can show of the Mac's road while the Share menu doesn't offer
    /// a Debug build's extension.
    static func writeAsTheExtensionWouldIfRequested(outbox: ShareOutbox,
                                                    arguments: [String] = ProcessInfo.processInfo.arguments,
                                                    suffix: String? = ProcessInfo.processInfo.environment["HITLIST_STORE_SUFFIX"]) {
        guard let index = arguments.firstIndex(of: "-shareBellProbe"), arguments.indices.contains(index + 1),
              let suffix, !suffix.isEmpty, suffix != SyncStoreGuard.developmentSuffix else { return }
        let title = arguments[index + 1]
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            let request = ShareRequest(askedAt: Date(), title: title, address: "http://localhost:8790/article.html",
                                       pageTitle: "A page worth reading", text: nil,
                                       recordedBy: "the Debug probe in \(ShareRoad.processDescription), standing in for the extension")
            do {
                try outbox.record(request)
                CloudSyncMonitor.shared.write(.note, "Share: Debug probe wrote ‘\(title)’ into the outbox, as the extension would; it waits for the bell (\(ShareOutboxBell.name(suffix: suffix)))")
                log.notice("share probe: request \(request.id.uuidString, privacy: .public) written; ring \(ShareOutboxBell.name(suffix: suffix), privacy: .public)")
            } catch {
                CloudSyncMonitor.shared.write(.note, "Share: Debug probe couldn't write: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private final class Delegate: NSObject, NSSharingServiceDelegate {
        func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                            sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
        }
    }
}
#endif
