import Foundation

/// The `hitlist-mcp` helper's half of a tool call (brief 43): wrap it with the app's token, send it to
/// the app, and turn every way that can fail into a tool result a model can act on. The transport and
/// the two readers are injected, so tests run it without an app or a port.
public struct ClaudeHelperBridge {
    public enum SendFailure: Error, Equatable {
        /// Nobody holds the port.
        case notFound
        /// The app didn't answer in time, or the port went away.
        case transport(String)
    }

    public var send: (Data) -> Result<Data, SendFailure>
    /// The token the app wrote, or nil when there is none.
    public var readToken: () -> String?
    /// The "Claude integration" setting, read only when the port is missing.
    public var isAllowed: () -> Bool

    public init(send: @escaping (Data) -> Result<Data, SendFailure>, readToken: @escaping () -> String?,
                isAllowed: @escaping () -> Bool) {
        self.send = send; self.readToken = readToken; self.isAllowed = isAllowed
    }

    public func call(_ tool: String, _ arguments: [String: JSONValue]) -> MCPToolResult {
        let request = ClaudeWire.Request(token: readToken(), tool: tool, arguments: arguments)
        guard let data = try? JSONEncoder().encode(request) else {
            return .error("The request couldn't be encoded.", code: ClaudeWire.Refusal.badRequest.rawValue)
        }
        switch send(data) {
        case .failure(.notFound):
            // The app closes the port while access is off, so a missing port is one of the two.
            return .error(isAllowed() ? ClaudeWire.notRunningMessage : ClaudeWire.accessOffMessage)
        case .failure(.transport(let why)):
            return .error("HITList didn't answer (\(why)). If it is busy or was just quit, open it and try again.")
        case .success(let reply):
            guard let result = try? JSONDecoder().decode(MCPToolResult.self, from: reply) else {
                return .error("HITList sent an answer this helper can't read. Update HITList and try again.")
            }
            // The plumbing code stays between the helper and the app.
            return MCPToolResult(text: result.text, isError: result.isError)
        }
    }
}

#if os(macOS)
extension ClaudeHelperBridge {
    /// The real bridge for the app group `groupID` and store `storeSuffix` (nil: the main store).
    public static func live(groupID: String, storeSuffix: String?) -> ClaudeHelperBridge {
        let portName = ClaudeWire.portName(groupID: groupID, storeSuffix: storeSuffix)
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        return ClaudeHelperBridge(
            send: { data in
                switch ClaudePortClient.send(data, to: portName) {
                case .success(let reply): return .success(reply)
                case .failure(.notFound): return .failure(.notFound)
                case .failure(.transport(let status)): return .failure(.transport("port status \(status)"))
                }
            },
            readToken: {
                guard let url = container?.appending(path: ClaudeWire.tokenPath(storeSuffix: storeSuffix)) else { return nil }
                return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            },
            isAllowed: {
                UserDefaults(suiteName: groupID)?.bool(forKey: ClaudeWire.allowedKey(storeSuffix: storeSuffix)) ?? false
            })
    }
}
#endif
