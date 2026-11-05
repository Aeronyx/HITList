import Foundation
import SwiftData
import HITListCore
#if os(macOS)
import AppKit
#endif

/// The running app's end of the Claude connector (brief 43), on the Mac only: while Claude integration is on it
/// holds the message port the `hitlist-mcp` helper calls (`ClaudeWire`) and a fresh token beside it in the
/// app group container; while it is off, neither exists. Every call runs on the main context, through
/// `TaskActions`, exactly as a tap in the app would; the helper never opens the store.
///
/// Why a message port and not a loopback HTTP listener: the sandbox lets only processes holding the app
/// group register or look up a name in it, so nothing else on the Mac (a web page, another app) can even
/// find the door; the app needs no new entitlement (`network.server` would be one App Review asks about);
/// and a port can't be left listening on the network by mistake.
@MainActor
final class ClaudeConnector {
    static let shared = ClaudeConnector()

    enum Status: Equatable {
        case off
        case listening(port: String)
        /// Claude integration is on but the port couldn't be opened (another copy of HITList holds it).
        case failed(String)
    }

    private(set) var status: Status = .off
    private var server: AnyObject?
    private var endpoint: ClaudeEndpoint?
    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    let settings: ClaudeSettings

    init(settings: ClaudeSettings = ClaudeSettings()) {
        self.settings = settings
    }

    /// Called once at launch (`HITListApp.init`). Opens the port if Claude integration is on. Nothing on iOS,
    /// where Claude's apps can't start a local helper.
    static func start(container: ModelContainer) {
        #if os(macOS)
        shared.attach(container: container)
        shared.refresh()
        let quit = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                         queue: .main) { _ in
            MainActor.assumeIsolated { shared.close(reason: "quit") }
        }
        shared.observers.append(quit)
        #endif
    }

    /// The store the tools run on; the port opens only once there is one.
    func attach(container: ModelContainer) {
        self.container = container
    }

    /// Opens or closes the port to match the Claude integration switch. Settings → Claude calls it after the switch moves.
    func refresh() {
        #if os(macOS)
        if settings.isAllowed, container != nil {
            if case .listening = status { return }
            open()
        } else if status != .off {
            close(reason: "switched off")
        }
        #endif
    }

    // MARK: Paths

    static var groupID: String { AppGroup.id }

    var portName: String { ClaudeWire.portName(groupID: Self.groupID, storeSuffix: settings.storeSuffix) }

    var tokenURL: URL? {
        AppGroup.containerURL?.appending(path: ClaudeWire.tokenPath(storeSuffix: settings.storeSuffix))
    }

    /// Writes `token` where the helper reads it: owner-only, replaced atomically.
    static func writeToken(_ token: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(token.utf8).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: Opening and closing

    #if os(macOS)
    private func open() {
        guard let container, let tokenURL else {
            status = .failed("The app group container is missing, so the helper couldn't find HITList.")
            return
        }
        let token = ClaudeWire.makeToken()
        do {
            try Self.writeToken(token, to: tokenURL)
        } catch {
            status = .failed("The connector's key couldn't be saved: \(error.localizedDescription)")
            CloudSyncMonitor.shared.write(.note, "Claude connector failed to save its key", level: .error,
                                          fields: ["via": "claude"])
            return
        }
        let endpoint = makeEndpoint(token: token, context: container.mainContext)
        let server = ClaudePortServer(name: portName) { data in
            MainActor.assumeIsolated { endpoint.respond(to: data) }
        }
        guard let server else {
            try? FileManager.default.removeItem(at: tokenURL)
            status = .failed("Another copy of HITList is already answering Claude on this Mac. Quit it, then turn Claude integration off and on.")
            CloudSyncMonitor.shared.write(.note, "Claude connector port busy", level: .error, fields: ["via": "claude"])
            return
        }
        self.endpoint = endpoint
        self.server = server
        status = .listening(port: portName)
        CloudSyncMonitor.shared.write(.note, "Claude connector on", fields: ["via": "claude"])
    }

    private func close(reason: String) {
        (server as? ClaudePortServer)?.invalidate()
        server = nil
        endpoint = nil
        if let tokenURL { try? FileManager.default.removeItem(at: tokenURL) }
        if status != .off {
            CloudSyncMonitor.shared.write(.note, "Claude connector off", fields: ["via": "claude", "reason": reason])
        }
        status = .off
    }
    #endif

    /// The endpoint for this run of the port: the token, the live switch, the tools on `context`.
    func makeEndpoint(token: String, context: ModelContext) -> ClaudeEndpoint {
        let settings = settings
        return ClaudeEndpoint(token: token, isAllowed: { settings.isAllowed }) { tool, arguments in
            // The rule is read per call, so a change in Settings → Claude applies to the next one.
            ClaudeToolHandler(
                context: context, rule: settings.rule,
                log: { message, fields in
                    _ = CloudSyncMonitor.shared.write(.note, message, fields: fields.merging(["via": "claude"]) { mine, _ in mine })
                },
                didWrite: { Task { await NotificationScheduler.reschedule(context: context) } },
                didComplete: { completed in
                    NotificationCenter.default.post(name: .claudeDidCompleteTask, object: nil,
                                                    userInfo: [ClaudeConnector.completedTaskKey: completed])
                }
            ).call(tool, arguments)
        }
    }

    /// The `CompletedTask` in a `.claudeDidCompleteTask` notification.
    static let completedTaskKey = "completedTask"
}

extension Notification.Name {
    /// Claude completed a task through the connector (main queue). `userInfo[ClaudeConnector.completedTaskKey]`
    /// is the `CompletedTask` the Undo toast takes; whoever owns the toast (`PopoutController`) observes it.
    static let claudeDidCompleteTask = Notification.Name("HITList.claudeDidCompleteTask")
}
