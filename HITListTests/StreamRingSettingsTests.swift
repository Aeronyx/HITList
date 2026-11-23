import XCTest
import SwiftUI
import SwiftData
import HITListCore
@testable import HITList

/// Settings → Stream Ring (brief 176): its place after Claude on both platforms, its words, its status line, and the
/// page in each state.
@MainActor
final class StreamRingSettingsTests: XCTestCase {
    private var container: ModelContainer!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        suite = "StreamRingSettingsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        container = nil
    }

    func testThePageComesAfterClaudeOnBothPlatforms() {
        XCTAssertEqual(SettingsPage.list.suffix(3), [.claude, .streamRing, .about])
        XCTAssertEqual(SettingsPage.streamRing.title, "Stream Ring")
        XCTAssertEqual(SettingsPage.streamRing.summary, "Tasks you say to the ring")
        let mac = MacSettingsSection.allCases
        XCTAssertEqual(mac.firstIndex(of: .streamRing), mac.firstIndex(of: .claude)! + 1)
        XCTAssertEqual(MacSettingsSection.streamRing.title, "Stream Ring")
        XCTAssertEqual(MacSettingsSection.streamRing.caption, "Tasks you say to the ring")
        XCTAssertEqual(SettingsPage.streamRing.systemImage, MacSettingsSection.streamRing.systemImage)
        XCTAssertEqual(SettingsRouter.launchSection(arguments: ["HITList", "-openSettingsSection", "streamRing"]), .streamRing)
        XCTAssertNil(SettingsRouter.launchSection(arguments: ["HITList", "-openSettingsSection", "nowhere"]))
    }

    /// Round 36: a friend's first screen has no Stream Ring row (no ring, no relay, and About stays where it was); a
    /// connected device, George's revealed ones and a Debug side store list it after Claude.
    func testStreamRingIsListedOnlyWhereItIsInUse() {
        XCTAssertFalse(StreamRingListing.isListed(connected: false, troubleshootingShown: false))
        XCTAssertTrue(StreamRingListing.isListed(connected: true, troubleshootingShown: false))
        XCTAssertTrue(StreamRingListing.isListed(connected: false, troubleshootingShown: true))
        XCTAssertTrue(StreamRingListing.isListed(connected: false, troubleshootingShown: false, demo: true))

        XCTAssertEqual(SettingsPage.shown(streamRingListed: false),
                       [.general, .calendar, .reminders, .extras, .iCloud, .claude, .about], "a friend's first screen, as in 0.9.17")
        XCTAssertEqual(SettingsPage.shown(streamRingListed: true), SettingsPage.list)
        XCTAssertFalse(MacSettingsSection.shown(streamRingListed: false).contains(.streamRing))
        XCTAssertEqual(MacSettingsSection.shown(streamRingListed: true), MacSettingsSection.allCases)
        // ↑ and ↓ in the Mac's sidebar step over a section that isn't listed.
        let friend = MacSettingsSection.shown(streamRingListed: false)
        XCTAssertEqual(MacSettingsSectionList.moved(.claude, by: 1, in: friend), .about)
        XCTAssertEqual(MacSettingsSectionList.moved(.claude, by: 1), .streamRing)
    }

    func testTheStatusLine() {
        let now = Date(timeIntervalSinceReferenceDate: 815_000_000)
        XCTAssertEqual(StreamRingWords.status(problem: nil, source: .everyMinute, lastCapture: now.addingTimeInterval(-300),
                                              addedToday: 3, now: now),
                       "from Stream every minute · last capture 5 min ago · 3 added today")
        XCTAssertEqual(StreamRingWords.status(problem: nil, source: .pushed, lastCapture: now, addedToday: 0, now: now),
                       "pushed by Stream · last capture just now")
        XCTAssertEqual(StreamRingWords.status(problem: nil, source: nil, lastCapture: nil, addedToday: 0, now: now),
                       "no captures yet")
        XCTAssertEqual(StreamRingWords.status(problem: .offline, source: .everyMinute, lastCapture: now, addedToday: 2, now: now),
                       "This device is offline. Captures wait in your relay.")
        XCTAssertEqual(StreamRingWords.status(problem: nil, source: .pushed, lastCapture: now, addedToday: 1,
                                              wake: StreamRingWords.wakeOn("iPhone"), now: now),
                       "pushed by Stream · last capture just now · 1 added today · wakes this iPhone when you speak")
        XCTAssertEqual(StreamRingWords.status(problem: nil, relayTrouble: StreamRingWords.webhookUnreadable, source: .pushed,
                                              lastCapture: now, addedToday: 1, now: now),
                       StreamRingWords.webhookUnreadable, "the relay's trouble before the usual line")
        // Drawn with each short part kept whole, so a line never ends in "· 3".
        XCTAssertEqual(StreamRingWords.keepingPartsWhole("pushed by Stream, and checked every minute · last capture 5 min ago · 3 added today"),
                       "pushed by Stream, and checked every minute\u{00A0}· last\u{00A0}capture\u{00A0}5\u{00A0}min\u{00A0}ago\u{00A0}· 3\u{00A0}added\u{00A0}today")
        XCTAssertEqual(StreamRingWords.keepingPartsWhole(StreamInboxProblem.unreachable.words), StreamInboxProblem.unreachable.words)
    }

    /// Round 3, finding 3: "wakes this iPhone when you speak" only after Apple took a push for this device in the last 30
    /// days and nothing failed since; "wake-ups not confirmed yet" before; the device's own trouble in words.
    func testWakeUpsAreSaidOnlyOnceAppleTookOne() {
        let now = Date()
        func words(_ state: InboxPushState?, configured: Bool = true, hasToken: Bool = true) -> String? {
            StreamRingWords.wake(device: "iPhone", configured: configured, hasToken: hasToken, state: state, now: now)
        }
        let registered = InboxPushState(configured: true, registered: true)
        XCTAssertEqual(words(registered), StreamRingWords.wakeUnconfirmed, "a token the relay holds isn't a wake-up")
        XCTAssertEqual(words(nil), StreamRingWords.wakeUnconfirmed, "no claim answered yet")
        var woken = registered
        woken.lastOkAt = now.addingTimeInterval(-3600)
        XCTAssertEqual(words(woken), StreamRingWords.wakeOn("iPhone"))
        var longAgo = registered
        longAgo.lastOkAt = now.addingTimeInterval(-31 * 86_400)
        XCTAssertEqual(words(longAgo), StreamRingWords.wakeUnconfirmed, "proof older than 30 days doesn't count")
        var failing = woken
        failing.lastError = "Apple's push service couldn't be reached (no connection)."
        XCTAssertEqual(words(failing), StreamRingWords.wakeTrouble("iPhone", "Apple's push service couldn't be reached (no connection)."),
                       "a failure since the last success")
        let refused = InboxPushState(configured: true, registered: false, lastError: "Apple says its push token is no longer in use (Unregistered); it isn't woken until HITList on it gives a new one.")
        XCTAssertEqual(words(refused), StreamRingWords.wakeTrouble("iPhone", refused.lastError!))
        XCTAssertEqual(words(registered, hasToken: false), StreamRingWords.wakeNoToken("iPhone"))
        XCTAssertNil(words(registered, configured: false), "no push key on the relay: wake-ups are off, not wrong")
    }

    func testHowLongAgo() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 18))!
        XCTAssertEqual(StreamRingWords.ago(now.addingTimeInterval(-20), now: now, calendar: calendar), "just now")
        XCTAssertEqual(StreamRingWords.ago(now.addingTimeInterval(-59 * 60), now: now, calendar: calendar), "59 min ago")
        XCTAssertEqual(StreamRingWords.ago(now.addingTimeInterval(-3 * 3600), now: now, calendar: calendar), "3 hr ago")
        XCTAssertEqual(StreamRingWords.ago(now.addingTimeInterval(-20 * 3600), now: now, calendar: calendar), "yesterday")
        XCTAssertEqual(StreamRingWords.ago(now.addingTimeInterval(-4 * 86_400), now: now, calendar: calendar), "4 days ago")
    }

    func testReconnectingStreamSaysHowLongIsLeft() {
        let now = Date()
        let ending = InboxStatus.StreamConnection(connected: true, approvedAt: now.addingTimeInterval(-80 * 86_400),
                                                  expiresAt: now.addingTimeInterval(10.5 * 86_400))
        XCTAssertEqual(StreamRingWords.streamActionTitle(.reconnect), "Reconnect Stream…")
        XCTAssertEqual(StreamRingWords.streamActionSubtitle(.reconnect, stream: ending, now: now),
                       "Stream's connection to your relay ends in 10 days")
        var ended = ending
        ended.connected = false
        XCTAssertEqual(StreamRingWords.streamActionSubtitle(.reconnect, stream: ended, now: now),
                       "Stream's connection to your relay has ended")
        XCTAssertEqual(StreamRingWords.streamActionTitle(.connect), "Connect Stream…")
    }

    /// Everything a person reads on the page without the gesture: none says a developer's word.
    func testNothingAFriendReadsSaysADevelopersWord() {
        let now = Date()
        let problems: [StreamInboxProblem] = [.notALink, .offline, .unreachable, .timedOut, .keyRefused, .notARelay,
                                              .relayTrouble(500), .unreadable, .keychain, .keyUnavailable, .relayTooOld,
                                              .storeUnavailable, .notSaved(1), .notSaved(3)]
        var words = [
            StreamRingWords.title, StreamRingWords.subtitle, StreamRingWords.intro, StreamRingWords.linkPlaceholder,
            StreamRingWords.connect, StreamRingWords.connecting, StreamRingWords.connected, StreamRingWords.checkNow,
            StreamRingWords.checking, StreamRingWords.sendTest, StreamRingWords.sendTestSubtitle, StreamRingWords.sending,
            StreamRingWords.onlyTask, StreamRingWords.onlyTaskFooter, StreamRingWords.chatTip, StreamRingWords.disconnect,
            StreamRingWords.disconnectSubtitle, StreamRingWords.disconnectQuestion, StreamRingWords.disconnectMessage,
            StreamRingWords.streamActionTitle(.connect), StreamRingWords.streamActionTitle(.reconnect),
            StreamRingWords.streamActionSubtitle(.connect, stream: nil, now: now),
            StreamRingWords.streamActionSubtitle(.reconnect, stream: nil, now: now),
            SettingsPage.streamRing.summary, MacSettingsSection.streamRing.caption,
            StreamRingWords.notRenewable, StreamRingWords.webhookUnreadable, StreamRingWords.wakeOn("iPhone"),
            StreamRingWords.wakeNoToken("iPhone"), StreamRingWords.wakeTrouble("iPhone", "Apple refused a wake-up push (403)."),
            StreamRingWords.wakeUnconfirmed,
            StreamRingWords.wakeTrouble("iPhone", "Apple refused its push token at both of its push services (BadDeviceToken); it isn't woken until HITList on it gives a new one."),
            StreamRingWords.wakeTrouble("iPhone", "The relay's Apple push key couldn't be used (The string did not match the expected pattern.). Run setup.sh again with the .p8 file Apple gave you."),
        ]
        words += problems.map(\.words)
        for source in [InboxStatus.Source.everyMinute, .pushed, .both, .none] {
            words.append(StreamRingWords.status(problem: nil, source: source, lastCapture: now, addedToday: 2, now: now))
        }
        for text in words {
            let lower = text.lowercased()
            for word in TroubleshootingTests.forbidden {
                XCTAssertFalse(lower.contains(word), "“\(text)” says \(word)")
            }
        }
    }

    func testBehindTheGestureWhatTheRelayLastHeard() {
        XCTAssertEqual(StreamRingWords.troubleshootingRows(deviceID: "Mac-1A2B3C4D", origin: nil, status: nil),
                       [.init(title: "This device", value: "Mac-1A2B3C4D")])
        let status = InboxStatus(pending: 2, lastSource: "stream", lastFields: ["id", "text", "created_at"],
                                 stream: .init(connected: true, approvedAt: Date(), expiresAt: Date(), lastPollAt: Date(),
                                               toolArguments: ["limit"], interactionFields: ["id", "text"]))
        let rows = StreamRingWords.troubleshootingRows(deviceID: "Mac-1A2B3C4D", origin: "https://relay.example", status: status)
        XCTAssertEqual(rows.first { $0.title.hasPrefix("Last capture's fields") }?.value, "id, text, created_at")
        XCTAssertEqual(rows.first { $0.title == "Stream tool's arguments" }?.value, "limit")
        XCTAssertEqual(rows.first { $0.title == "Waiting in the relay" }?.value, "2")
    }

    func testThePageRendersInEachState() async throws {
        render(StreamRingSettingsSection(inbox: nil), "not started")
        let relay = StreamInboxFakeRelay()
        relay.setStream(connected: true, approvedAt: Date().addingTimeInterval(-80 * 86_400), lastPollAt: Date())
        let inbox = StreamInbox(container: container, defaults: defaults, keyStore: MemoryInboxKey(), client: relay.client,
                                log: { _, _ in })
        render(StreamRingSettingsSection(inbox: inbox), "not connected")
        _ = await inbox.connect(linkText: relay.link, checkAfter: false)
        render(StreamRingSettingsSection(inbox: inbox), "connected, Stream ending")
    }

    private func render<V: View>(_ view: V, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let content = VStack { view }.padding(HITSpacing.l).frame(width: 402).modelContainer(container)
            .background(Theme.background).preferredColorScheme(.dark)
        XCTAssertNotNil(ImageRenderer(content: content).cgImage, "\(name) didn't render", file: file, line: line)
    }
}
