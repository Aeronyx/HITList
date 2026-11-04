import Foundation

/// The channel between the `hitlist-mcp` helper and the running Mac app (brief 43).
///
/// A Mach message port (`CFMessagePort`) named inside the app group: `<group>.claude`, or
/// `<group>.claude.<suffix>` for an app on a side store (`HITLIST_STORE_SUFFIX`, e.g. a Debug build's
/// "Development"), so two builds never answer for each other. The App Sandbox lets a process register and
/// look up only port names that start with an app group it holds, so only HITList's own signed processes
/// can reach it: no network listener, no extra entitlement for the app, nothing a web page can call.
/// The app writes a fresh random token to the group container each time it opens the port, and refuses a
/// request without it, so a stale or foreign caller gets nothing even if it found the name.
///
/// The helper never opens the store. Every request is one tool call; the app runs it on its main
/// context and answers with an `MCPToolResult`.
public enum ClaudeWire {
    /// The only message id in use: one tool call.
    public static let callMessageID: Int32 = 1

    /// The setting "Allow Claude" for the store with this suffix, in the app group's defaults. The helper
    /// reads it only to tell "access is off" from "HITList isn't running" when the port is missing.
    public static func allowedKey(storeSuffix: String?) -> String { "claude.allowed" + suffixPart(storeSuffix) }

    public static func portName(groupID: String, storeSuffix: String?) -> String {
        "\(groupID).claude" + suffixPart(storeSuffix)
    }

    /// The token file, relative to the app group container.
    public static func tokenPath(storeSuffix: String?) -> String { "Claude/token" + suffixPart(storeSuffix, separator: "-") }

    /// A side store's suffix as `ModelContainerFactory` accepts it (letters, digits, "-"), or nil.
    public static func cleanSuffix(_ suffix: String?) -> String? {
        guard let suffix, !suffix.isEmpty, suffix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return suffix
    }

    private static func suffixPart(_ suffix: String?, separator: String = ".") -> String {
        cleanSuffix(suffix).map { separator + $0 } ?? ""
    }

    /// A random 256-bit token as 64 hex characters.
    public static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
    }

    /// Why the app refused a call (`MCPToolResult.code`).
    public enum Refusal: String, Sendable {
        case unauthorized
        case accessOff
        case badRequest
    }

    public struct Request: Codable, Equatable, Sendable {
        public var token: String?
        public var tool: String
        public var arguments: [String: JSONValue]

        public init(token: String?, tool: String, arguments: [String: JSONValue] = [:]) {
            self.token = token; self.tool = tool; self.arguments = arguments
        }
    }

    // The words both sides use for the two ways a call can't reach the tasks.
    public static let notRunningMessage = "HITList isn't running on this Mac. Open HITList on this Mac, then try again."
    public static let accessOffMessage = "HITList's Claude access is off. Turn on Allow Claude in HITList → Settings → Claude."
}

#if os(macOS)
/// The app's end: a local message port that hands each request to `handler` on the run loop it was
/// opened on (the main one in the app) and sends back what it returns.
public final class ClaudePortServer {
    public typealias Handler = (Data) -> Data

    public let name: String
    private let handler: Handler
    private var port: CFMessagePort?
    private var source: CFRunLoopSource?

    /// Nil when the name can't be registered: another process holds it (a second copy of the app), or
    /// the sandbox refuses it (a name outside the app group).
    public init?(name: String, runLoop: CFRunLoop = CFRunLoopGetMain(), handler: @escaping Handler) {
        self.name = name
        self.handler = handler
        var context = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = Unmanaged.passUnretained(self).toOpaque()
        var shouldFree: DarwinBoolean = false
        let callback: CFMessagePortCallBack = { _, _, data, info in
            guard let info else { return nil }
            let server = Unmanaged<ClaudePortServer>.fromOpaque(info).takeUnretainedValue()
            let reply = server.handler((data as Data?) ?? Data())
            // The port releases the data it is handed back.
            return Unmanaged.passRetained(reply as CFData)
        }
        guard let port = CFMessagePortCreateLocal(nil, name as CFString, callback, &context, &shouldFree) else { return nil }
        self.port = port
        let source = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        self.source = source
    }

    public var isValid: Bool { port.map(CFMessagePortIsValid) ?? false }

    public func invalidate() {
        if let source { CFRunLoopSourceInvalidate(source) }
        if let port { CFMessagePortInvalidate(port) }
        source = nil
        port = nil
    }

    deinit { invalidate() }
}

/// The helper's end: one synchronous request to the app's port.
public enum ClaudePortClient {
    public enum Failure: Error, Equatable {
        /// No port by that name: the app isn't running (or its Claude access is off).
        case notFound
        /// The app took too long or the port went away mid-call.
        case transport(Int32)
    }

    /// Sends `data` and waits for the reply. Don't call it on the run loop that serves the port.
    public static func send(_ data: Data, to name: String, sendTimeout: TimeInterval = 5,
                            replyTimeout: TimeInterval = 30) -> Result<Data, Failure> {
        guard let port = CFMessagePortCreateRemote(nil, name as CFString) else { return .failure(.notFound) }
        defer { CFMessagePortInvalidate(port) }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(port, ClaudeWire.callMessageID, data as CFData, sendTimeout, replyTimeout,
                                              CFRunLoopMode.defaultMode.rawValue, &reply)
        guard status == kCFMessagePortSuccess else { return .failure(.transport(status)) }
        guard let reply else { return .failure(.transport(kCFMessagePortTransportError)) }
        return .success(reply.takeRetainedValue() as Data)
    }
}
#endif
