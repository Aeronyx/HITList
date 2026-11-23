import XCTest
@testable import HITListCore

/// The inbox link Settings → Stream Ring reads (brief 176): an `https` origin and the key from the fragment; `http` only
/// for this Mac's own relay.
final class InboxLinkTests: XCTestCase {
    private let key = String(repeating: "ab12", count: 16) // 64 characters, as `openssl rand -hex 32` makes

    func testReadsTheLinkSetupPrints() throws {
        let link = try XCTUnwrap(InboxLink("https://stream-inbox.example.workers.dev/#\(key)"))
        XCTAssertEqual(link.origin.absoluteString, "https://stream-inbox.example.workers.dev")
        XCTAssertEqual(link.key, key)
        XCTAssertEqual(link.text, "https://stream-inbox.example.workers.dev/#\(key)")
        XCTAssertEqual(link.url("/inbox/claim").absoluteString, "https://stream-inbox.example.workers.dev/inbox/claim")
        XCTAssertEqual(link.url("inbox/ack").absoluteString, "https://stream-inbox.example.workers.dev/inbox/ack")
    }

    func testAPastedLinkIsForgivenItsWrapping() {
        for text in ["  https://relay.example/#\(key)\n", "<https://relay.example/#\(key)>", "\"https://relay.example/#\(key)\"",
                     "“https://relay.example/#\(key)”", "https://relay.example#\(key)", "HTTPS://Relay.Example/#\(key)"] {
            let link = InboxLink(text)
            XCTAssertEqual(link?.origin.absoluteString, "https://relay.example", text)
            XCTAssertEqual(link?.key, key, text)
        }
    }

    func testPlainHTTPOnlyForThisMac() {
        XCTAssertEqual(InboxLink("http://127.0.0.1:8799/#\(key)")?.origin.absoluteString, "http://127.0.0.1:8799")
        XCTAssertEqual(InboxLink("http://localhost:8799/#\(key)")?.origin.absoluteString, "http://localhost:8799")
        XCTAssertNil(InboxLink("http://relay.example/#\(key)"), "plain http elsewhere")
        XCTAssertNil(InboxLink("http://192.168.1.4:8799/#\(key)"), "plain http on the network")
    }

    func testAnythingElseIsNotALink() {
        let refused = [
            "", "hello", "relay.example/#\(key)", "https://relay.example/", "https://relay.example/#",
            "https://relay.example/#short", "https://relay.example/stream#\(key)", "https://relay.example/?k=1#\(key)",
            "https://user:pass@relay.example/#\(key)", "ftp://relay.example/#\(key)", "https://relay.example/#\(key) extra",
            "https://relay.example/#\(String(repeating: "a", count: 257))", "https:///#\(key)",
        ]
        for text in refused {
            XCTAssertNil(InboxLink(text), "“\(text)”")
        }
        XCTAssertEqual(InboxLink.notALink, "That isn't an inbox link")
    }

    func testTheLinkComesBackFromWhatADeviceKeeps() throws {
        let link = try XCTUnwrap(InboxLink("https://relay.example/#\(key)"))
        XCTAssertEqual(InboxLink(origin: link.origin.absoluteString, key: link.key), link)
        XCTAssertNil(InboxLink(origin: "http://relay.example", key: key))
        XCTAssertNil(InboxLink(origin: "https://relay.example", key: "bad key"))
    }
}
