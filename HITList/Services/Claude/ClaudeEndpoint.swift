import Foundation
import HITListCore

/// The app's side of one connector call (brief 43): the bytes the `hitlist-mcp` helper sent through the
/// message port in, a tool result out. It checks the token the app wrote for this run of the port, then
/// "Allow Claude" (read per call, so switching it off takes effect at once), and only then runs the tool.
@MainActor
final class ClaudeEndpoint {
    let token: String
    private let isAllowed: () -> Bool
    private let run: (_ tool: String, _ arguments: [String: JSONValue]) -> MCPToolResult

    init(token: String, isAllowed: @escaping () -> Bool,
         run: @escaping (_ tool: String, _ arguments: [String: JSONValue]) -> MCPToolResult) {
        self.token = token
        self.isAllowed = isAllowed
        self.run = run
    }

    static let unauthorizedMessage = """
        HITList refused the request: the connector's key didn't match. Quit and reopen HITList, then try again.
        """

    func result(for data: Data) -> MCPToolResult {
        guard let request = try? JSONDecoder().decode(ClaudeWire.Request.self, from: data) else {
            return .error("HITList couldn't read the request.", code: ClaudeWire.Refusal.badRequest.rawValue)
        }
        guard let given = request.token, Self.matches(given, token) else {
            return .error(Self.unauthorizedMessage, code: ClaudeWire.Refusal.unauthorized.rawValue)
        }
        guard isAllowed() else { return .error(ClaudeWire.accessOffMessage, code: ClaudeWire.Refusal.accessOff.rawValue) }
        return run(request.tool, request.arguments)
    }

    /// The reply bytes for the port.
    func respond(to data: Data) -> Data {
        (try? JSONEncoder().encode(result(for: data))) ?? Data()
    }

    /// Compares every byte whatever the first difference, so timing says nothing about the token.
    nonisolated static func matches(_ given: String, _ expected: String) -> Bool {
        let a = Array(given.utf8), b = Array(expected.utf8)
        guard a.count == b.count, !b.isEmpty else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
