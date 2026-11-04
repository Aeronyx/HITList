import Foundation

/// A tool as `tools/list` describes it.
public struct MCPTool: Equatable, Sendable {
    public var name: String
    public var title: String
    public var description: String
    /// A JSON Schema object for the arguments.
    public var inputSchema: JSONValue
    /// MCP's hint that the tool changes nothing.
    public var readOnly: Bool

    public init(name: String, title: String, description: String, inputSchema: JSONValue, readOnly: Bool) {
        self.name = name; self.title = title; self.description = description
        self.inputSchema = inputSchema; self.readOnly = readOnly
    }

    var json: JSONValue {
        ["name": .string(name), "title": .string(title), "description": .string(description), "inputSchema": inputSchema,
         "annotations": ["title": .string(title), "readOnlyHint": .bool(readOnly), "destructiveHint": false,
                         "openWorldHint": false]]
    }
}

/// Splits a byte stream into MCP stdio messages: one JSON-RPC message per line (`\n`, or `\r\n`),
/// which may arrive in any number of reads. Blank lines are skipped.
public struct MCPLineBuffer: Sendable {
    private var pending = Data()
    /// A line longer than this (with no newline yet) is dropped rather than held forever.
    public static let maxLineBytes = 8 * 1024 * 1024

    public init() {}

    /// Adds bytes and returns every line they complete.
    public mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            var line = pending[pending.startIndex..<newline]
            if line.last == 0x0D { line = line.dropLast() }
            pending = Data(pending[pending.index(after: newline)...])
            if !line.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) { lines.append(Data(line)) }
        }
        if pending.count > Self.maxLineBytes { pending = Data() }
        return lines
    }

    /// What is left at end of input: a last line sent without a newline.
    public mutating func finish() -> Data? {
        defer { pending = Data() }
        let rest = pending.filter { $0 != 0x0D }
        return rest.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0A }) ? nil : Data(rest)
    }
}

/// A minimal MCP server (JSON-RPC 2.0 over stdio, protocol 2025-06-18 and its two predecessors) that
/// offers tools only: `initialize`, `ping`, `tools/list`, `tools/call`. No third-party code. The transport
/// (stdin/stdout) is the caller's: hand it each line, write back what it returns.
public final class MCPServer {
    public typealias ToolCall = (_ name: String, _ arguments: [String: JSONValue]) -> MCPToolResult

    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    public enum ErrorCode {
        public static let parse = -32700
        public static let invalidRequest = -32600
        public static let methodNotFound = -32601
        public static let invalidParams = -32602
    }

    public let name: String
    public let title: String
    public let version: String
    public let instructions: String?
    public let tools: [MCPTool]
    private let call: ToolCall
    /// The version agreed in `initialize`.
    public private(set) var negotiatedVersion: String?

    public init(name: String, title: String, version: String, instructions: String? = nil, tools: [MCPTool],
                call: @escaping ToolCall) {
        self.name = name; self.title = title; self.version = version; self.instructions = instructions
        self.tools = tools; self.call = call
    }

    /// Handles one incoming line; returns the reply line (without its newline), or nil when the message
    /// needs none (a notification, or a response from the client).
    public func handle(line: Data) -> Data? {
        guard let message = try? JSONValue.decode(line) else {
            return reply(.null, error: (ErrorCode.parse, "Parse error: not JSON"))
        }
        guard case .object(let fields) = message else {
            // MCP 2025-06-18 dropped JSON-RPC batches.
            return reply(.null, error: (ErrorCode.invalidRequest, "Invalid request: expected one JSON-RPC object"))
        }
        let id = fields["id"]
        guard let method = fields["method"]?.stringValue else {
            // A response to a request we never send, or junk: answer junk that has an id, ignore the rest.
            if fields["result"] != nil || fields["error"] != nil { return nil }
            return id.map { reply($0, error: (ErrorCode.invalidRequest, "Invalid request: no method")) } ?? nil
        }
        // Notifications (no id) never get a reply, known or not.
        guard let id, id != .null else { return nil }
        let params = fields["params"]?.objectValue ?? [:]
        switch method {
        case "initialize":
            return reply(id, result: initializeResult(params))
        case "ping":
            return reply(id, result: [:])
        case "tools/list":
            return reply(id, result: ["tools": .array(tools.map(\.json))])
        case "tools/call":
            guard let name = params["name"]?.stringValue else {
                return reply(id, error: (ErrorCode.invalidParams, "tools/call needs a tool name"))
            }
            guard tools.contains(where: { $0.name == name }) else {
                return reply(id, error: (ErrorCode.invalidParams, "Unknown tool: \(name)"))
            }
            let arguments = params["arguments"]?.objectValue ?? [:]
            return reply(id, result: call(name, arguments).json)
        default:
            return reply(id, error: (ErrorCode.methodNotFound, "Method not found: \(method)"))
        }
    }

    private func initializeResult(_ params: [String: JSONValue]) -> JSONValue {
        let asked = params["protocolVersion"]?.stringValue ?? ""
        let version = Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0]
        negotiatedVersion = version
        var result: [String: JSONValue] = [
            "protocolVersion": .string(version),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": .string(name), "title": .string(title), "version": .string(self.version)],
        ]
        if let instructions { result["instructions"] = .string(instructions) }
        return .object(result)
    }

    private func reply(_ id: JSONValue, result: JSONValue) -> Data? {
        try? JSONValue.object(["jsonrpc": "2.0", "id": id, "result": result]).compactData()
    }

    private func reply(_ id: JSONValue, error: (code: Int, message: String)) -> Data? {
        try? JSONValue.object(["jsonrpc": "2.0", "id": id,
                               "error": ["code": .int(error.code), "message": .string(error.message)]]).compactData()
    }
}
