import XCTest
@testable import HITListCore

/// The helper ↔ app channel (brief 43): names, token, the request shape, the message port, and the
/// helper's bridge turning every failure into a tool result.
final class ClaudeWireTests: XCTestCase {
    func testNamesAreScopedToTheAppGroupAndTheStore() {
        let group = "UC8N98H3RT.com.trammells.hitlist"
        XCTAssertEqual(ClaudeWire.portName(groupID: group, storeSuffix: nil), "UC8N98H3RT.com.trammells.hitlist.claude")
        XCTAssertEqual(ClaudeWire.portName(groupID: group, storeSuffix: "Development"),
                       "UC8N98H3RT.com.trammells.hitlist.claude.Development")
        XCTAssertEqual(ClaudeWire.portName(groupID: group, storeSuffix: ""), "UC8N98H3RT.com.trammells.hitlist.claude")
        XCTAssertEqual(ClaudeWire.portName(groupID: group, storeSuffix: "../x"), "UC8N98H3RT.com.trammells.hitlist.claude",
                       "a suffix the store would refuse is ignored")
        XCTAssertEqual(ClaudeWire.allowedKey(storeSuffix: nil), "claude.allowed")
        XCTAssertEqual(ClaudeWire.allowedKey(storeSuffix: "Development"), "claude.allowed.Development")
        XCTAssertEqual(ClaudeWire.tokenPath(storeSuffix: nil), "Claude/token")
        XCTAssertEqual(ClaudeWire.tokenPath(storeSuffix: "e2e-43"), "Claude/token-e2e-43")
    }

    func testTokensAreLongRandomHex() {
        let a = ClaudeWire.makeToken(), b = ClaudeWire.makeToken()
        XCTAssertEqual(a.count, 64)
        XCTAssertTrue(a.allSatisfy(\.isHexDigit))
        XCTAssertNotEqual(a, b)
    }

    func testRequestRoundTrips() throws {
        let request = ClaudeWire.Request(token: "t", tool: "list_tasks", arguments: ["filter": "today", "limit": 5])
        let decoded = try JSONDecoder().decode(ClaudeWire.Request.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.arguments["limit"]?.intValue, 5)
    }

    // MARK: The message port

    func testPortCarriesARequestAndItsReply() throws {
        let name = "com.trammells.hitlist.tests.claude.\(UUID().uuidString.prefix(8))"
        let server = try XCTUnwrap(ClaudePortServer(name: name, runLoop: CFRunLoopGetCurrent()) { data in
            Data("reply:".utf8) + data
        })
        defer { server.invalidate() }
        let replied = expectation(description: "reply")
        var result: Result<Data, ClaudePortClient.Failure>?
        DispatchQueue.global().async {
            result = ClaudePortClient.send(Data("hello".utf8), to: name)
            replied.fulfill()
        }
        wait(for: [replied], timeout: 10)
        XCTAssertEqual(try result?.get(), Data("reply:hello".utf8))
    }

    func testMissingPortIsNotFound() {
        XCTAssertEqual(ClaudePortClient.send(Data(), to: "com.trammells.hitlist.tests.nobody.\(UUID().uuidString)"),
                       .failure(.notFound))
    }

    func testSecondServerCannotTakeANameInUse() throws {
        let name = "com.trammells.hitlist.tests.claude.\(UUID().uuidString.prefix(8))"
        let first = try XCTUnwrap(ClaudePortServer(name: name) { $0 })
        defer { first.invalidate() }
        // In the same process CF hands back the existing port; the app keeps one server per name, so what
        // matters is that a closed one frees the name for the next.
        first.invalidate()
        let again = ClaudePortServer(name: name) { $0 }
        XCTAssertNotNil(again)
        again?.invalidate()
    }

    // MARK: The helper's bridge

    private func bridge(send: @escaping (Data) -> Result<Data, ClaudeHelperBridge.SendFailure>, token: String? = "tok",
                        allowed: Bool = true) -> ClaudeHelperBridge {
        ClaudeHelperBridge(send: send, readToken: { token }, isAllowed: { allowed })
    }

    func testBridgeSendsTheTokenToolAndArguments() throws {
        var sent: ClaudeWire.Request?
        let reply = try JSONEncoder().encode(MCPToolResult(text: "ok", code: "internal"))
        let result = bridge(send: { data in
            sent = try? JSONDecoder().decode(ClaudeWire.Request.self, from: data)
            return .success(reply)
        }).call("get_task", ["id": "abc"])
        XCTAssertEqual(sent, ClaudeWire.Request(token: "tok", tool: "get_task", arguments: ["id": "abc"]))
        XCTAssertEqual(result, MCPToolResult(text: "ok"), "the plumbing code never reaches the client")
    }

    func testBridgeSaysOpenHITListWhenNothingAnswers() {
        let result = bridge(send: { _ in .failure(.notFound) }).call("list_tasks", [:])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Open HITList on this Mac"))
    }

    func testBridgeSaysAccessIsOffWhenTheSwitchIsOff() {
        let result = bridge(send: { _ in .failure(.notFound) }, allowed: false).call("list_tasks", [:])
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, ClaudeWire.accessOffMessage)
        XCTAssertTrue(result.text.contains("HITList's Claude access is off"))
    }

    func testBridgeExplainsTimeoutsAndUnreadableReplies() {
        XCTAssertTrue(bridge(send: { _ in .failure(.transport("port status -2")) }).call("x", [:]).text.contains("didn't answer"))
        let junk = bridge(send: { _ in .success(Data("nope".utf8)) }).call("x", [:])
        XCTAssertTrue(junk.isError)
        XCTAssertTrue(junk.text.contains("can't read"))
    }
}
