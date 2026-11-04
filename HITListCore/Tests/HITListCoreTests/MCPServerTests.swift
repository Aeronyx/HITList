import XCTest
@testable import HITListCore

/// The connector's MCP server (brief 43): stdio framing and the JSON-RPC methods Claude Desktop and
/// Claude Code use.
final class MCPServerTests: XCTestCase {
    private var calls: [(String, [String: JSONValue])] = []

    private func server() -> MCPServer {
        MCPServer(name: ClaudeTools.serverName, title: ClaudeTools.serverTitle, version: "0.6.0 (16)",
                  instructions: ClaudeTools.instructions, tools: ClaudeTools.all) { [unowned self] name, arguments in
            calls.append((name, arguments))
            return name == ClaudeTools.completeTask ? .error("No task with that id.") : MCPToolResult(text: "[]")
        }
    }

    /// Sends one line, returns the decoded reply (nil when there is none).
    private func send(_ server: MCPServer, _ line: String) throws -> JSONValue? {
        guard let reply = server.handle(line: Data(line.utf8)) else { return nil }
        XCTAssertFalse(reply.contains(0x0A), "a reply is one line")
        return try JSONValue.decode(reply)
    }

    // MARK: Framing

    func testLinesAreSplitAcrossReadsAndCRLF() {
        var buffer = MCPLineBuffer()
        XCTAssertEqual(buffer.append(Data("{\"a\":".utf8)), [])
        XCTAssertEqual(buffer.append(Data("1}\r\n\n  \n{\"b\":2}\n{\"c\"".utf8)).map { String(decoding: $0, as: UTF8.self) },
                       ["{\"a\":1}", "{\"b\":2}"], "CR dropped, blank lines skipped")
        XCTAssertEqual(buffer.append(Data(":3}".utf8)), [])
        XCTAssertEqual(buffer.finish().map { String(decoding: $0, as: UTF8.self) }, "{\"c\":3}", "a last line without newline")
        XCTAssertNil(buffer.finish())
    }

    func testMultibyteTextSurvivesASplitRead() throws {
        var buffer = MCPLineBuffer()
        let bytes = Array("{\"t\":\"Café ☕\"}\n".utf8)
        var lines: [Data] = []
        for byte in bytes { lines += buffer.append(Data([byte])) }
        XCTAssertEqual(try JSONValue.decode(XCTUnwrap(lines.first))["t"], "Café ☕")
    }

    // MARK: Lifecycle

    func testInitializeAgreesOnTheClientsVersionWhenSupported() throws {
        let s = server()
        let reply = try XCTUnwrap(send(s, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"claude-ai","version":"0.1.0"}}}"#))
        XCTAssertEqual(reply["id"], 1)
        XCTAssertEqual(reply["result"]?["protocolVersion"], "2025-03-26")
        XCTAssertEqual(reply["result"]?["serverInfo"]?["name"], "hitlist")
        XCTAssertEqual(reply["result"]?["serverInfo"]?["version"], "0.6.0 (16)")
        XCTAssertEqual(reply["result"]?["capabilities"]?["tools"]?["listChanged"], false)
        XCTAssertNotNil(reply["result"]?["instructions"]?.stringValue)
        XCTAssertEqual(s.negotiatedVersion, "2025-03-26")
    }

    func testInitializeOffersTheLatestForAnUnknownVersion() throws {
        let reply = try XCTUnwrap(send(server(), #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#))
        XCTAssertEqual(reply["id"], "a", "string ids come back as strings")
        XCTAssertEqual(reply["result"]?["protocolVersion"], "2025-06-18")
    }

    func testNotificationsAndResponsesGetNoReply() throws {
        let s = server()
        XCTAssertNil(try send(s, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertNil(try send(s, #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":3}}"#))
        XCTAssertNil(try send(s, #"{"jsonrpc":"2.0","id":9,"result":{}}"#))
    }

    func testPing() throws {
        XCTAssertEqual(try send(server(), #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#)?["result"], [:])
    }

    // MARK: Tools

    func testToolsListOffersTheSevenTools() throws {
        let reply = try XCTUnwrap(send(server(), #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#))
        let tools = try XCTUnwrap(reply["result"]?["tools"]?.arrayValue)
        XCTAssertEqual(tools.compactMap { $0["name"]?.stringValue },
                       ["list_tasks", "get_task", "add_task", "complete_task", "update_task", "list_groups", "list_labels"])
        for tool in tools {
            XCTAssertEqual(tool["inputSchema"]?["type"], "object")
            XCTAssertFalse(tool["description"]?.stringValue?.isEmpty ?? true)
        }
        let readOnly = tools.filter { $0["annotations"]?["readOnlyHint"] == true }.compactMap { $0["name"]?.stringValue }
        XCTAssertEqual(readOnly, ["list_tasks", "get_task", "list_groups", "list_labels"])
        XCTAssertEqual(tools[2]["inputSchema"]?["required"], ["text"])
    }

    func testToolsCallPassesArgumentsAndWrapsTheResult() throws {
        let s = server()
        let reply = try XCTUnwrap(send(s, #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_tasks","arguments":{"filter":"today","limit":5}}}"#))
        XCTAssertEqual(calls.first?.0, "list_tasks")
        XCTAssertEqual(calls.first?.1, ["filter": "today", "limit": 5])
        XCTAssertEqual(reply["result"]?["content"], [["type": "text", "text": "[]"]])
        XCTAssertEqual(reply["result"]?["isError"], false)
    }

    func testAToolFailureIsAResultNotAProtocolError() throws {
        let reply = try XCTUnwrap(send(server(), #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"complete_task","arguments":{"id":"x"}}}"#))
        XCTAssertNil(reply["error"])
        XCTAssertEqual(reply["result"]?["isError"], true)
        XCTAssertEqual(reply["result"]?["content"]?.arrayValue?.first?["text"], "No task with that id.")
    }

    func testCallWithoutArgumentsGetsAnEmptyObject() throws {
        _ = try send(server(), #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"list_groups"}}"#)
        XCTAssertEqual(calls.first?.1, [:])
    }

    // MARK: Errors

    func testProtocolErrors() throws {
        let s = server()
        let unknownTool = try XCTUnwrap(send(s, #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"delete_everything"}}"#))
        XCTAssertEqual(unknownTool["error"]?["code"], .int(MCPServer.ErrorCode.invalidParams))
        let noName = try XCTUnwrap(send(s, #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{}}"#))
        XCTAssertEqual(noName["error"]?["code"], .int(MCPServer.ErrorCode.invalidParams))
        let unknownMethod = try XCTUnwrap(send(s, #"{"jsonrpc":"2.0","id":10,"method":"resources/list"}"#))
        XCTAssertEqual(unknownMethod["error"]?["code"], .int(MCPServer.ErrorCode.methodNotFound))
        let junk = try XCTUnwrap(send(s, "{not json"))
        XCTAssertEqual(junk["error"]?["code"], .int(MCPServer.ErrorCode.parse))
        XCTAssertEqual(junk["id"], .null)
        let batch = try XCTUnwrap(send(s, #"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#))
        XCTAssertEqual(batch["error"]?["code"], .int(MCPServer.ErrorCode.invalidRequest))
        XCTAssertTrue(calls.isEmpty, "no tool ran")
    }

    // MARK: JSON values

    func testJSONValueKeepsIntegersAndReadsLooseNumbers() throws {
        let value = try JSONValue.decode(Data(#"{"a":7,"b":2.5,"c":"12","d":3.0,"e":true,"f":null}"#.utf8))
        XCTAssertEqual(value["a"], .int(7))
        XCTAssertEqual(value["b"], .double(2.5))
        XCTAssertEqual(value["c"]?.intValue, 12)
        XCTAssertEqual(value["d"]?.intValue, 3)
        XCTAssertNil(value["b"]?.intValue)
        XCTAssertEqual(value["e"]?.boolValue, true)
        XCTAssertEqual(value["f"]?.isNull, true)
        XCTAssertEqual(String(decoding: try JSONValue.object(["z": "a/b\nc", "a": 1]).compactData(), as: UTF8.self),
                       #"{"a":1,"z":"a/b\nc"}"#, "sorted keys, slashes kept, newline escaped")
    }
}
