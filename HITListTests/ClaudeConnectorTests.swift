import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// The Claude connector (brief 43): settings, the endpoint's gate (token, switch), the message port in the
/// app's sandbox.
@MainActor
final class ClaudeConnectorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "ClaudeConnectorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: Settings

    func testSettingsDefaultToOffAndEverythingExceptPrivate() {
        let settings = ClaudeSettings(defaults: defaults, storeSuffix: nil)
        XCTAssertFalse(settings.isAllowed, "off until George turns it on")
        XCTAssertEqual(settings.rule, ClaudeAccessRule(mode: .allExceptHidden, hiddenLabel: "private", sharedLabel: "claude"))
    }

    func testSettingsAreKeptPerStore() {
        let main = ClaudeSettings(defaults: defaults, storeSuffix: nil)
        let debug = ClaudeSettings(defaults: defaults, storeSuffix: "Development")
        XCTAssertEqual(main.allowedKey, "claude.allowed", "the helper reads this name")
        XCTAssertEqual(debug.allowedKey, "claude.allowed.Development")
        debug.isAllowed = true
        debug.rule = ClaudeAccessRule(mode: .onlyShared, sharedLabel: "@ai")
        XCTAssertFalse(main.isAllowed, "a Debug build's switch never opens the TestFlight app's tasks")
        XCTAssertEqual(main.rule.mode, .allExceptHidden)
        XCTAssertEqual(debug.rule, ClaudeAccessRule(mode: .onlyShared, sharedLabel: "ai"))
    }

    // MARK: The endpoint's gate

    private func request(token: String?, tool: String = "list_tasks") throws -> Data {
        try JSONEncoder().encode(ClaudeWire.Request(token: token, tool: tool, arguments: ["filter": "today"]))
    }

    private func endpoint(allowed: Bool = true, ran: @escaping (String) -> Void = { _ in }) -> ClaudeEndpoint {
        ClaudeEndpoint(token: "right-token", isAllowed: { allowed }) { tool, arguments in
            ran(tool)
            return MCPToolResult(text: "ran \(tool) \(arguments["filter"]?.stringValue ?? "")")
        }
    }

    func testNoTokenIsRefused() throws {
        var ran = false
        let result = endpoint(ran: { _ in ran = true }).result(for: try request(token: nil))
        XCTAssertEqual(result.code, ClaudeWire.Refusal.unauthorized.rawValue)
        XCTAssertTrue(result.isError)
        XCTAssertFalse(ran)
    }

    func testWrongTokenIsRefused() throws {
        var ran = false
        let gate = endpoint(ran: { _ in ran = true })
        for token in ["wrong-token", "right-toke", "right-token!", "", "RIGHT-TOKEN"] {
            XCTAssertEqual(gate.result(for: try request(token: token)).code, ClaudeWire.Refusal.unauthorized.rawValue, token)
        }
        XCTAssertFalse(ran)
    }

    func testAccessOffIsRefusedEvenWithTheToken() throws {
        var ran = false
        let result = endpoint(allowed: false, ran: { _ in ran = true }).result(for: try request(token: "right-token"))
        XCTAssertEqual(result.code, ClaudeWire.Refusal.accessOff.rawValue)
        XCTAssertEqual(result.text, ClaudeWire.accessOffMessage)
        XCTAssertFalse(ran)
    }

    func testTheRightTokenRunsTheTool() throws {
        var ran: String?
        let result = endpoint(ran: { ran = $0 }).result(for: try request(token: "right-token"))
        XCTAssertEqual(ran, "list_tasks")
        XCTAssertEqual(result, MCPToolResult(text: "ran list_tasks today"))
    }

    func testJunkIsABadRequest() {
        XCTAssertEqual(endpoint().result(for: Data("{".utf8)).code, ClaudeWire.Refusal.badRequest.rawValue)
    }

    func testTokenComparison() {
        XCTAssertTrue(ClaudeEndpoint.matches("abc", "abc"))
        XCTAssertFalse(ClaudeEndpoint.matches("abd", "abc"))
        XCTAssertFalse(ClaudeEndpoint.matches("", ""), "an empty token never matches")
    }

    func testTokenFileIsOwnerOnly() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "claude-\(UUID().uuidString)/token")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try ClaudeConnector.writeToken("abc", to: url)
        try ClaudeConnector.writeToken("def", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "def")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    // MARK: The port, in the app's own sandbox

    #if os(macOS)
    /// Sends through the real port from a background thread while the main run loop serves it.
    private func sendThroughPort(_ data: Data, to name: String) -> Result<Data, ClaudePortClient.Failure>? {
        let done = expectation(description: "reply")
        var result: Result<Data, ClaudePortClient.Failure>?
        DispatchQueue.global().async {
            result = ClaudePortClient.send(data, to: name, replyTimeout: 10)
            done.fulfill()
        }
        wait(for: [done], timeout: 15)
        return result
    }

    func testThePortInTheAppGroupCarriesCallsThroughTheGate() throws {
        let name = ClaudeWire.portName(groupID: AppGroup.id, storeSuffix: "tests\(UInt32.random(in: 0 ... .max))")
        let gate = endpoint()
        let server = try XCTUnwrap(ClaudePortServer(name: name) { data in MainActor.assumeIsolated { gate.respond(to: data) } },
                                   "the sandbox lets the app register names inside its app group")
        defer { server.invalidate() }

        let refused = try JSONDecoder().decode(MCPToolResult.self, from: XCTUnwrap(sendThroughPort(try request(token: "nope"), to: name)?.get()))
        XCTAssertEqual(refused.code, ClaudeWire.Refusal.unauthorized.rawValue)
        let answered = try JSONDecoder().decode(MCPToolResult.self, from: XCTUnwrap(sendThroughPort(try request(token: "right-token"), to: name)?.get()))
        XCTAssertEqual(answered.text, "ran list_tasks today")

        server.invalidate()
        XCTAssertEqual(sendThroughPort(Data(), to: name), .failure(.notFound), "closed means gone, not refusing")
    }

    func testThePortCannotBeOpenedOutsideTheAppGroup() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["HITLIST_UNSIGNED"] != nil, "unsigned builds run without the sandbox")
        XCTAssertNil(ClaudePortServer(name: "com.example.claude.\(UUID().uuidString.prefix(8))") { $0 },
                     "the sandbox refuses names outside the app group, so nothing but HITList's group can listen or call")
    }
    #endif
}
