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

    // MARK: Review of 18e36cb8 and wake-ups

    /// Finding 1: each item says when it was said; finding 8: the relay's rule comes with every claim; wake-ups: a
    /// claim carries this device's push token and says whether the relay can wake it.
    func testAClaimCarriesThePushTokenAndBringsTheTimeAndTheRule() throws {
        let push = InboxPushRegistration(token: "ab12", environment: .production, platform: "iOS")
        let body = try XCTUnwrap(InboxAPI.claim(device: "iPhone-1A2B3C4D", push: push, link: link).httpBody)
        XCTAssertEqual(String(decoding: body, as: UTF8.self),
                       #"{"device":"iPhone-1A2B3C4D","push":{"environment":"production","platform":"iOS","token":"ab12"}}"#)
        let json = #"""
        {"items":[{"id":"t-1","text":"Call the dentist tomorrow at 9am","receivedAt":"2026-11-24T12:45:00.000Z",
                   "capturedAt":"2026-11-24T03:30:00.000Z"},{"id":"t-2","text":"Buy milk","receivedAt":"2026-11-24T12:45:00.000Z"}],
         "settings":{"onlyStartingWithTask":true},"push":{"configured":true,"registered":true}}
        """#
        let reply = try InboxAPI.decode(InboxClaimReply.self, from: Data(json.utf8))
        XCTAssertEqual(reply.items[0].capturedAt, InboxAPI.parseDate("2026-11-24T03:30:00Z"))
        XCTAssertEqual(reply.items[0].saidAt, InboxAPI.parseDate("2026-11-24T03:30:00Z"), "when it was said: Stream's time")
        XCTAssertEqual(reply.items[1].saidAt, InboxAPI.parseDate("2026-11-24T12:45:00Z"), "else when the relay got it")
        XCTAssertEqual(reply.settings, InboxSettings(onlyStartingWithTask: true))
        XCTAssertEqual(reply.push, InboxPushState(configured: true, registered: true))
        let old = try InboxAPI.decode(InboxClaimReply.self, from: Data(#"{"items":[]}"#.utf8))
        XCTAssertNil(old.settings, "a relay from before the review says nothing of the rule")
        XCTAssertNil(old.push)
    }

    func testTheRuleIsSetOnTheRelay() throws {
        let request = InboxAPI.settings(InboxSettingsChange(onlyStartingWithTask: true), link: link)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/inbox/settings")
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self), #"{"onlyStartingWithTask":true}"#,
                       "only what changes: the words another device chose are never written back")
        let reply = try InboxAPI.decode(InboxSettingsReply.self, from: Data(#"{"settings":{"onlyStartingWithTask":false}}"#.utf8))
        XCTAssertEqual(reply.settings.onlyStartingWithTask, false)
        XCTAssertEqual(reply.settings.wakeWords, [.task], "a relay from before the wake words: Task, as it was")
    }

    /// George, 2026-11-23: "Jarvis and Tars as selectable wake words instead of only Task".
    func testWakeWordsAreChosenOnTheRelay() throws {
        let request = InboxAPI.settings(InboxSettingsChange(wakeWords: [.jarvis, .tars]), link: link)
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self), #"{"wakeWords":["jarvis","tars"]}"#)
        let reply = try InboxAPI.decode(InboxSettingsReply.self, from: Data(
            #"{"settings":{"onlyStartingWithTask":true,"wakeWords":["tars","siri","jarvis","tars"]}}"#.utf8))
        XCTAssertEqual(reply.settings, InboxSettings(onlyStartingWithTask: true, wakeWords: [.jarvis, .tars]),
                       "in their own order, once each, an unknown word left out")
        let none = try InboxAPI.decode(InboxSettingsReply.self, from: Data(#"{"settings":{"onlyStartingWithTask":true,"wakeWords":[]}}"#.utf8))
        XCTAssertEqual(none.settings.wakeWords, [.task], "never none")
        XCTAssertEqual(InboxSettings(onlyStartingWithTask: false, wakeWords: []).wakeWords, [.task])
        XCTAssertEqual(WakeWord.quoted([.task]), "“Task”")
        XCTAssertEqual(WakeWord.quoted([.task, .jarvis]), "“Task” or “Jarvis”")
        XCTAssertEqual(WakeWord.quoted(WakeWord.allCases), "“Task”, “Jarvis” or “TARS”")
    }

    /// Finding 3: the poller's trouble and the shape of an answer it couldn't read; finding 11: a sign-in that can't be
    /// renewed; wake-ups: whether the relay can push, to how many devices, and its last trouble.
    func testTheStatusSaysTroubleRenewalAndWakeUps() throws {
        let json = #"""
        {"pending":0,"lastFields":[],"idsMatch":true,"settings":{"onlyStartingWithTask":true},
         "webhook":{"lastReceivedAt":"2026-11-24T12:00:00Z","lastResult":"invalid","lastFields":["note"]},
         "stream":{"connected":true,"approvedAt":"2026-11-24T10:00:00Z","expiresAt":"2027-02-22T10:00:00Z",
                   "lastError":"Stream's answer couldn't be read: the relay found no list of interactions in it.",
                   "refreshable":false,"answerShape":{"contentTypes":["text"],"json":[false],"structured":false,"keys":[]}},
         "push":{"configured":true,"devices":2,"lastSentAt":"2026-11-24T12:01:00Z","lastError":null}}
        """#
        let status = try InboxAPI.decode(InboxStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.settings?.onlyStartingWithTask, true)
        XCTAssertTrue(status.idsMatch)
        XCTAssertEqual(status.stream?.refreshable, false)
        XCTAssertEqual(status.stream?.answerShape?.contentTypes, ["text"])
        XCTAssertEqual(status.stream?.answerShape?.json, [false])
        XCTAssertEqual(status.push?.devices, 2)
        XCTAssertEqual(status.push?.configured, true)
        XCTAssertEqual(status.webhook?.lastResult, "invalid")
        let quiet = try InboxAPI.decode(InboxStatus.self, from: Data(#"{"pending":0}"#.utf8))
        XCTAssertNil(quiet.push)
        XCTAssertFalse(quiet.idsMatch)
    }

    // MARK: Round 3

    /// Finding 6: a capture's own time more than a day before it reached the relay can't be when it was said (an older
    /// relay may still hand one over): the words are read as of its arrival.
    func testASaidTimeMoreThanADayBeforeTheArrivalIsIgnored() throws {
        let arrived = try XCTUnwrap(InboxAPI.parseDate("2026-11-24T12:45:00Z"))
        let lastNight = arrived.addingTimeInterval(-11 * 3600)
        XCTAssertEqual(InboxItem(id: "a", text: "x", receivedAt: arrived, capturedAt: lastNight).saidAt, lastNight,
                       "eleven hours before: kept")
        let dayBefore = arrived.addingTimeInterval(-86_400)
        XCTAssertEqual(InboxItem(id: "b", text: "x", receivedAt: arrived, capturedAt: dayBefore).saidAt, dayBefore,
                       "a day exactly: kept")
        let epoch = Date(timeIntervalSince1970: 12)
        XCTAssertEqual(InboxItem(id: "c", text: "x", receivedAt: arrived, capturedAt: epoch).saidAt, arrived,
                       "1970 is no time")
        XCTAssertEqual(InboxItem(id: "d", text: "x", receivedAt: arrived, capturedAt: arrived.addingTimeInterval(-86_401)).saidAt,
                       arrived, "over a day before: the arrival")
        XCTAssertNil(InboxItem(id: "e", text: "x", capturedAt: epoch).saidAt, "1970 and no arrival: no time, read as of now")
        let earlier = arrived.addingTimeInterval(-600)
        XCTAssertEqual(InboxItem(id: "f", text: "x", capturedAt: earlier).saidAt, earlier, "no arrival, a plausible time: kept")
    }

    /// Finding 3: a claim says when Apple last took a wake-up push for this device, or why it can't be woken; the status
    /// says each device's own wake-ups.
    func testAClaimAndTheStatusSayEachDevicesWakeUps() throws {
        let claim = #"""
        {"items":[],"push":{"configured":true,"registered":false,"lastOkAt":null,
         "lastError":"Apple refused its push token at both of its push services (BadDeviceToken); it isn't woken until HITList on it gives a new one."}}
        """#
        let reply = try InboxAPI.decode(InboxClaimReply.self, from: Data(claim.utf8))
        XCTAssertEqual(reply.push?.registered, false)
        XCTAssertNil(reply.push?.lastOkAt)
        XCTAssertTrue(reply.push?.lastError?.contains("BadDeviceToken") == true)
        let woken = try InboxAPI.decode(InboxClaimReply.self, from: Data(
            #"{"items":[],"push":{"configured":true,"registered":true,"lastOkAt":"2026-11-24T12:01:00.000Z","lastError":null}}"#.utf8))
        XCTAssertEqual(woken.push, InboxPushState(configured: true, registered: true,
                                                  lastOkAt: InboxAPI.parseDate("2026-11-24T12:01:00Z")))
        let status = #"""
        {"pending":0,"push":{"configured":true,"devices":1,"lastSentAt":"2026-11-24T12:01:00Z",
         "lastError":"Mac-1A2B3C4D: Apple refused a wake-up push (500).",
         "byDevice":[{"device":"iPhone-9F8E7D6C","platform":"iOS","service":"production","lastClaimAt":"2026-11-24T12:01:05Z",
                      "lastPushAt":"2026-11-24T12:01:00Z","lastOkAt":"2026-11-24T12:01:00Z","lastError":null,"refused":false},
                     {"device":"Mac-1A2B3C4D","platform":"macOS","service":"sandbox","refused":true,"lastError":"x"}]}}
        """#
        let push = try XCTUnwrap(try InboxAPI.decode(InboxStatus.self, from: Data(status.utf8)).push)
        XCTAssertEqual(push.byDevice?.map(\.device), ["iPhone-9F8E7D6C", "Mac-1A2B3C4D"])
        XCTAssertEqual(push.byDevice?.first?.lastOkAt, InboxAPI.parseDate("2026-11-24T12:01:00Z"))
        XCTAssertEqual(push.byDevice?.last?.refused, true)
        XCTAssertEqual(push.byDevice?.last?.service, "sandbox")
    }
}
