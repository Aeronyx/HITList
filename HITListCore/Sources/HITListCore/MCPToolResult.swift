import Foundation

/// What a tool call gives back: text for the model, and whether it failed. `code` is for the connector's
/// own plumbing (why the app refused), never shown to MCP clients.
public struct MCPToolResult: Codable, Equatable, Sendable {
    public var text: String
    public var isError: Bool
    public var code: String?

    public init(text: String, isError: Bool = false, code: String? = nil) {
        self.text = text; self.isError = isError; self.code = code
    }

    public static func error(_ text: String, code: String? = nil) -> MCPToolResult {
        MCPToolResult(text: text, isError: true, code: code)
    }

    /// A JSON payload as indented text, which models read well.
    public static func json(_ value: JSONValue) -> MCPToolResult { MCPToolResult(text: value.prettyString()) }

    var json: JSONValue {
        ["content": [["type": "text", "text": .string(text)]], "isError": .bool(isError)]
    }
}
