import XCTest
@testable import HITListCore

/// The relay's requests and answers (brief 176): what HITList sends, and how tolerantly it reads what comes back.
final class InboxProtocolTests: XCTestCase {
    private let link = InboxLink("https://relay.example/#\(String(repeating: "k", count: 64))")!

    func testEveryRequestCarriesTheKeyAndAShortTimeout() throws {
        let requests: [(URLRequest, String, String)] = [
            (InboxAPI.claim(device: "Mac-1A2B3C4D", link: link), "POST", "/inbox/claim"),
            (InboxAPI.ack(ids: ["a", "b"], link: link), "POST", "/inbox/ack"),
            (InboxAPI.status(link: link), "GET", "/inbox/status"),
            (InboxAPI.test(link: link), "POST", "/inbox/test"),
            (InboxAPI.connectLink(link: link), "POST", "/stream/connect-link"),
        ]
        for (request, method, path) in requests {
            XCTAssertEqual(request.httpMethod, method, path)
            XCTAssertEqual(request.url?.absoluteString, "https://relay.example" + path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + link.key, path)
            XCTAssertEqual(request.timeoutInterval, 15, path)
            XCTAssertNil(request.url?.fragment, "the key never rides in a URL")
            XCTAssertFalse(request.url!.absoluteString.contains(link.key), "the key never rides in a URL")
        }
        let claim = try XCTUnwrap(InboxAPI.claim(device: "Mac-1A2B3C4D", link: link).httpBody)
        XCTAssertEqual(String(decoding: claim, as: UTF8.self), #"{"device":"Mac-1A2B3C4D"}"#)
        let ack = try XCTUnwrap(InboxAPI.ack(ids: ["a", "b"], link: link).httpBody)
        XCTAssertEqual(String(decoding: ack, as: UTF8.self), #"{"ids":["a","b"]}"#)
        XCTAssertNil(InboxAPI.status(link: link).httpBody)
    }

    func testAClaimIsRead() throws {
        let json = #"""
        {"items":[{"id":"int-1","text":"Call the dentist tomorrow at 9am p2.","receivedAt":"2026-11-23T17:45:00.123Z"},
                  {"id":"test-9f","text":"Test capture from your Stream ring","receivedAt":"2026-11-23T17:46:00Z"}],
         "lastReceivedAt":"2026-11-23T17:46:00Z","somethingNew":true}
        """#
        let reply = try InboxAPI.decode(InboxClaimReply.self, from: Data(json.utf8))
        XCTAssertEqual(reply.items.map(\.id), ["int-1", "test-9f"])
        XCTAssertEqual(reply.items[0].receivedAt!.timeIntervalSince1970, 1_795_455_900.123, accuracy: 0.001)
        XCTAssertEqual(reply.items[1].receivedAt, Date(timeIntervalSince1970: 1_795_455_960))
        XCTAssertFalse(reply.items[0].isTest)
        XCTAssertTrue(reply.items[1].isTest)
        XCTAssertEqual(reply.lastReceivedAt, Date(timeIntervalSince1970: 1_795_455_960))
        XCTAssertEqual(try InboxAPI.decode(InboxClaimReply.self, from: Data("{}".utf8)).items, [], "nothing waiting")
    }

    func testDatesAsNumbersToo() throws {
        let seconds = try InboxAPI.decode(InboxClaimReply.self, from: Data(#"{"items":[],"lastReceivedAt":1763919900}"#.utf8))
        XCTAssertEqual(seconds.lastReceivedAt, Date(timeIntervalSince1970: 1_763_919_900))
        let millis = try InboxAPI.decode(InboxClaimReply.self, from: Data(#"{"items":[],"lastReceivedAt":1763919900123}"#.utf8))
        XCTAssertEqual(millis.lastReceivedAt!.timeIntervalSince1970, 1_763_919_900.123, accuracy: 0.001)
    }

    func testTheStatusAndWhereCapturesComeFrom() throws {
        let json = #"""
        {"pending":2,"lastReceivedAt":"2026-11-23T17:45:00.000Z","lastSource":"stream","lastFields":["id","text","created_at"],
         "webhook":{"lastReceivedAt":null,"lastResult":null,"lastFields":[]},
         "stream":{"connected":true,"approvedAt":"2026-11-01T12:00:00.000Z","expiresAt":"2027-01-30T12:00:00.000Z",
                   "lastPollAt":"2026-11-23T17:45:30.000Z","lastError":null,"toolArguments":["limit"],"interactionFields":["id","text"]}}
        """#
        let status = try InboxAPI.decode(InboxStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.pending, 2)
        XCTAssertEqual(status.lastFields, ["id", "text", "created_at"])
        XCTAssertEqual(status.stream?.toolArguments, ["limit"])
        let now = try XCTUnwrap(InboxAPI.parseDate("2026-11-23T18:00:00Z"))
        XCTAssertEqual(status.source(now: now), .everyMinute)
        XCTAssertEqual(status.stream?.daysLeft(now: now), 67, "67 days and 18 hours")
        XCTAssertEqual(status.streamAction(now: now), .none)

        var pushed = status
        pushed.stream = nil
        pushed.webhook = .init(lastReceivedAt: now.addingTimeInterval(-3600))
        XCTAssertEqual(pushed.source(now: now), .pushed)
        XCTAssertEqual(pushed.streamAction(now: now), .none, "the webhook brings captures: nothing to connect")
        pushed.webhook = .init(lastReceivedAt: now.addingTimeInterval(-31 * 86_400))
        XCTAssertEqual(pushed.source(now: now), .none, "a webhook quiet for a month no longer counts")
        XCTAssertEqual(pushed.streamAction(now: now), .connect)

        var both = status
        both.webhook = .init(lastReceivedAt: now)
        XCTAssertEqual(both.source(now: now), .both)
        XCTAssertEqual(try InboxAPI.decode(InboxStatus.self, from: Data(#"{"pending":0}"#.utf8)).streamAction(now: now), .connect)
    }

    func testReconnectingIsOfferedTwoWeeksBeforeTheEndAndAfterIt() throws {
        let approved = Date(timeIntervalSince1970: 1_760_000_000)
        let ends = approved.addingTimeInterval(90 * 86_400)
        var stream = InboxStatus.StreamConnection(connected: true, approvedAt: approved, expiresAt: ends)
        XCTAssertFalse(stream.needsReconnect(now: ends.addingTimeInterval(-15 * 86_400)))
        XCTAssertTrue(stream.needsReconnect(now: ends.addingTimeInterval(-13 * 86_400)))
        XCTAssertEqual(stream.daysLeft(now: ends.addingTimeInterval(-13.5 * 86_400)), 13)
        stream.connected = false
        XCTAssertTrue(stream.needsReconnect(now: approved), "ended")
        XCTAssertFalse(InboxStatus.StreamConnection(connected: false).needsReconnect(now: approved), "never connected")
        let status = InboxStatus(stream: stream)
        XCTAssertEqual(status.streamAction(now: approved), .reconnect)
    }

    func testAnswersTheRelayRefusesWith() throws {
        XCTAssertEqual(try InboxAPI.decode(InboxErrorReply.self, from: Data(#"{"error":"unauthorized"}"#.utf8)).error, "unauthorized")
        let link = try InboxAPI.decode(InboxConnectLink.self, from: Data(#"{"url":"https://relay.example/stream/connect?c=abc","expiresAt":"2026-11-23T18:10:00.000Z"}"#.utf8))
        XCTAssertEqual(link.url.absoluteString, "https://relay.example/stream/connect?c=abc")
        XCTAssertEqual(try InboxAPI.decode(InboxAckReply.self, from: Data(#"{"acked":3}"#.utf8)).acked, 3)
    }
}
