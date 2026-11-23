#if DEBUG
import Foundation
import SwiftData
import HITListCore
#if os(macOS)
import AppKit
#endif

/// Debug builds on a side store only (brief 176), for the UI tests, pictures and the whole-path proof on this Mac.
///
/// - `-streamInboxDemo YES`: the inbox talks to a relay in this process (`StreamInboxFakeRelay.demo()`), with its key
///   in memory, so a UI test connects, checks and sends a test capture with no network and leaves nothing behind.
///   `-streamInboxDemoDaysLeft N` sets how long its pretend Stream connection has left (14 or fewer shows "Reconnect").
/// - `-streamInboxConnect <link>`: connects at launch as if the link had been pasted (a `wrangler dev` relay on
///   `http://127.0.0.1`).
enum StreamInboxDebug {
    static let demoKey = "streamInboxDemo"
    static let demoDaysLeftKey = "streamInboxDemoDaysLeft"
    static let connectKey = "streamInboxConnect"

    static var isSideStore: Bool { !ModelContainerFactory.isMainStoreOpen }

    @MainActor
    static func inbox(container: ModelContainer) -> StreamInbox? {
        guard isSideStore, UserDefaults.standard.bool(forKey: demoKey) else { return nil }
        // A launch argument arrives as a string: `integer(forKey:)` reads it, nil only when it isn't there.
        let daysLeft = UserDefaults.standard.object(forKey: demoDaysLeftKey) == nil ? 87 : UserDefaults.standard.integer(forKey: demoDaysLeftKey)
        let relay = StreamInboxFakeRelay.demo(daysLeft: daysLeft)
        return StreamInbox(container: container, keyStore: MemoryInboxKey(), client: relay.client, isLive: true)
    }

    /// `-openDeepLink hitlist://upcoming` (side store): the screen a capture's task lands on, opened in-process a few
    /// seconds after launch, for a picture of the whole path with nothing clicked.
    static let deepLinkKey = "openDeepLink"

    @MainActor
    static func connectIfAsked(_ inbox: StreamInbox) {
        #if os(macOS)
        openWindowIfAsked()
        #endif
        if isSideStore, let text = UserDefaults.standard.string(forKey: deepLinkKey), let url = URL(string: text),
           let link = DeepLink(url) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { link.open() }
        }
        guard isSideStore, let link = UserDefaults.standard.string(forKey: connectKey), !link.isEmpty,
              !inbox.isConnected || inbox.link?.text != InboxLink(link)?.text else { return }
        Task { _ = await inbox.connect(linkText: link) }
    }

    #if os(macOS)
    static let openWindowKey = "openMainWindow"

    /// `-openMainWindow YES` (side store): a Debug Mac app launched in the background here sometimes opens no window
    /// at all ("No windows open yet", round 19 and again in round 36), so a window capture has nothing to capture. Two
    /// seconds on, with no window shown, it asks SwiftUI for the one a Dock click would open.
    @MainActor
    static func openWindowIfAsked() {
        guard isSideStore, UserDefaults.standard.bool(forKey: openWindowKey) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard !NSApp.windows.contains(where: { $0.isVisible && $0.styleMask.contains(.titled) }) else { return }
            _ = NSApp.delegate?.applicationOpenUntitledFile?(NSApp)
        }
    }
    #endif
}

/// A relay in this process: the endpoints and answers of `relay/stream-inbox/worker.js`, in memory, reached through
/// `FakeRelayURLProtocol` on a session of its own. The hosted tests make one each (and make it fail as they need);
/// `-streamInboxDemo YES` uses `demo()`.
final class StreamInboxFakeRelay: @unchecked Sendable {
    struct Capture {
        var id: String
        var text: String
        var receivedAt: Date
        /// When it was said (Stream's own time), if not when it arrived.
        var said: Date?
        var claimedBy: String?
        var claimedAt: Date?
    }

    /// One request as it reached the relay.
    struct Received {
        var method: String
        var path: String
        var body: Data
        var authorization: String?

        var json: [String: Any] { (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:] }

        /// An ack's ids.
        var ids: [String]? { json["ids"] as? [String] }
    }

    let host: String
    let key: String
    let session: URLSession
    private let lock = NSLock()
    private var waiting: [Capture] = []
    private var done: Set<String> = []
    private var received: [Received] = []
    private var down = false
    private var acksFailing = false
    private var lastReceivedAt: Date?
    private var stream: [String: Any]?
    private var webhook: [String: Any] = ["lastReceivedAt": NSNull(), "lastResult": NSNull(), "lastFields": [String]()]
    private var rule = InboxSettings(onlyStartingWithTask: false)
    private var pushKey = false
    private var tokens: [String: String] = [:]
    /// Each device's wake-ups as the relay keeps them (round 3): when Apple last took a push for it, its trouble.
    private var wakes: [String: (okAt: Date?, error: String?, refused: Bool)] = [:]
    private var confirmsWakeUps = false

    static let demoHost = "demo-relay.example"
    static let demoKey = "demo0000demo1111demo2222demo3333demo4444demo5555demo6666demo7777"

    init(host: String = "relay-\(UUID().uuidString.prefix(8).lowercased()).example", key: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()) {
        self.host = host
        self.key = key
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeRelayURLProtocol.self]
        configuration.timeoutIntervalForRequest = InboxAPI.timeout
        session = URLSession(configuration: configuration)
        FakeRelayURLProtocol.register(self)
    }

    /// The demo's relay: one capture waiting and a Stream connection approved `90 - daysLeft` days ago.
    static func demo(daysLeft: Int) -> StreamInboxFakeRelay {
        let relay = StreamInboxFakeRelay(host: demoHost, key: demoKey)
        let now = Date()
        relay.add("demo-1", "Call the dentist tomorrow at 9am p2.", at: now.addingTimeInterval(-300))
        let approved = now.addingTimeInterval(-Double(90 - daysLeft) * 86_400)
        relay.setStream(connected: daysLeft > 0, approvedAt: approved, lastPollAt: now.addingTimeInterval(-40))
        relay.pushConfigured = true
        // The demo's device has been woken: Apple took a push for it a minute before it registered.
        relay.locked { relay.confirmsWakeUps = true }
        return relay
    }

    /// A device's wake-ups as the relay would say them in its claim (round 3, finding 3).
    func setWake(device: String, okAt: Date? = nil, error: String? = nil, refused: Bool = false) {
        locked { wakes[device] = (okAt, error, refused) }
    }

    var link: String { "https://\(host)/#\(key)" }
    var client: StreamInboxClient { StreamInboxClient(session: session) }

    /// A capture waiting, as the relay keeps it (an older relay's: the rule isn't applied here, so a device's own guard
    /// is what is tested).
    func add(_ id: String, _ text: String, at date: Date = Date(), said: Date? = nil) {
        locked {
            waiting.append(Capture(id: id, text: text, receivedAt: date, said: said))
            lastReceivedAt = date
        }
    }

    func setStream(connected: Bool, approvedAt: Date, lastPollAt: Date?, lastError: String? = nil, refreshable: Bool? = true) {
        locked {
            stream = ["connected": connected, "approvedAt": Self.iso(approvedAt),
                      "expiresAt": Self.iso(approvedAt.addingTimeInterval(90 * 86_400)),
                      "lastPollAt": Self.json(lastPollAt.map(Self.iso)), "lastError": Self.json(lastError),
                      "refreshable": Self.json(refreshable),
                      "toolArguments": ["limit", "days"], "interactionFields": ["id", "text", "created_at"]]
        }
    }

    func setWebhook(result: String?, at date: Date = Date()) {
        locked { webhook = ["lastReceivedAt": Self.iso(date), "lastResult": Self.json(result), "lastFields": ["text", "interaction_id"]] }
    }

    /// The relay's rule, as a device set it.
    var settings: InboxSettings { locked { rule } }

    /// Whether this relay has an Apple push key (its wake-ups).
    var pushConfigured: Bool {
        get { locked { pushKey } }
        set { locked { pushKey = newValue } }
    }

    var isDown: Bool {
        get { locked { down } }
        set { locked { down = newValue } }
    }

    var acksFail: Bool {
        get { locked { acksFailing } }
        set { locked { acksFailing = newValue } }
    }

    var requests: [Received] { locked { received } }
    var waitingIDs: [String] { locked { waiting.map(\.id) } }
    var handedOver: Set<String> { locked { done } }

    /// The ids each ack carried, in order.
    var acks: [[String]] { requests.filter { $0.path == InboxAPI.Endpoint.ack.rawValue }.compactMap(\.ids) }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// nil as JSON's null.
    private static func json(_ value: Any?) -> Any { value ?? NSNull() }

    // MARK: Answering

    func answer(_ request: URLRequest, body: Data) throws -> (HTTPURLResponse, Data) {
        try locked {
            let path = request.url?.path ?? "/"
            let method = request.httpMethod ?? "GET"
            received.append(Received(method: method, path: path, body: body,
                                     authorization: request.value(forHTTPHeaderField: "Authorization")))
            if down { throw URLError(.cannotConnectToHost) }
            if method == "GET", path == "/" { return reply(200, ["ok": true]) }
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)" else {
                return reply(401, ["error": "Unauthorized."])
            }
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            let now = Date()
            switch (method, path) {
            case ("POST", InboxAPI.Endpoint.claim.rawValue):
                guard let device = json["device"] as? String, !device.isEmpty else { return reply(400, ["error": "device"]) }
                if let token = (json["push"] as? [String: Any])?["token"] as? String {
                    tokens[device] = token
                    if confirmsWakeUps, wakes[device] == nil { wakes[device] = (now.addingTimeInterval(-60), nil, false) }
                }
                let wake = wakes[device]
                var items: [[String: Any]] = []
                for index in waiting.indices.sorted(by: { waiting[$0].receivedAt < waiting[$1].receivedAt }) {
                    let capture = waiting[index]
                    let free = capture.claimedAt.map { now.timeIntervalSince($0) > 30 * 60 } ?? true
                    guard free || capture.claimedBy == device, items.count < InboxAPI.claimLimit else { continue }
                    waiting[index].claimedBy = device
                    waiting[index].claimedAt = now
                    items.append(["id": capture.id, "text": capture.text, "receivedAt": Self.iso(capture.receivedAt),
                                  "capturedAt": Self.iso(capture.said ?? capture.receivedAt)])
                }
                return reply(200, ["items": items, "lastReceivedAt": Self.json(lastReceivedAt.map(Self.iso)),
                                   "settings": ["onlyStartingWithTask": rule.onlyStartingWithTask],
                                   "push": ["configured": pushKey, "registered": tokens[device] != nil && wake?.refused != true,
                                            "lastOkAt": Self.json(wake?.okAt.map(Self.iso)),
                                            "lastError": Self.json(wake?.error)]])
            case ("POST", InboxAPI.Endpoint.settings.rawValue):
                guard let on = json["onlyStartingWithTask"] as? Bool else { return reply(400, ["error": "onlyStartingWithTask"]) }
                rule = InboxSettings(onlyStartingWithTask: on)
                return reply(200, ["settings": ["onlyStartingWithTask": on]])
            case ("POST", InboxAPI.Endpoint.ack.rawValue):
                if acksFailing { return reply(500, ["error": "The relay had a problem."]) }
                let ids = Set(json["ids"] as? [String] ?? [])
                let before = waiting.count
                waiting.removeAll { ids.contains($0.id) }
                done.formUnion(ids)
                return reply(200, ["acked": before - waiting.count])
            case ("GET", InboxAPI.Endpoint.status.rawValue):
                return reply(200, ["pending": waiting.count, "lastReceivedAt": Self.json(lastReceivedAt.map(Self.iso)),
                                   "lastSource": "stream", "lastFields": ["id", "text", "created_at"],
                                   "webhook": webhook, "stream": Self.json(stream),
                                   "settings": ["onlyStartingWithTask": rule.onlyStartingWithTask],
                                   "push": ["configured": pushKey, "devices": tokens.count, "lastSentAt": NSNull(),
                                            "lastError": NSNull()]])
            case ("POST", InboxAPI.Endpoint.test.rawValue):
                let id = "test-\(UUID().uuidString.prefix(8).lowercased())"
                waiting.append(Capture(id: id, text: InboxAPI.testText, receivedAt: now))
                return reply(202, ["status": "accepted", "id": id])
            case ("POST", InboxAPI.Endpoint.connectLink.rawValue):
                return reply(200, ["url": "https://\(host)/stream/connect?c=demo", "expiresAt": Self.iso(now.addingTimeInterval(600))])
            default:
                return reply(404, ["error": "Not found."])
            }
        }
    }

    private func reply(_ status: Int, _ object: [String: Any]) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(url: URL(string: "https://\(host)")!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return (response, data)
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

/// Routes a session's requests to the fake relay registered for their host.
final class FakeRelayURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var relays: [String: StreamInboxFakeRelay] = [:]

    static func register(_ relay: StreamInboxFakeRelay) {
        lock.lock()
        relays[relay.host] = relay
        lock.unlock()
    }

    static func relay(for host: String?) -> StreamInboxFakeRelay? {
        guard let host else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return relays[host]
    }

    override class func canInit(with request: URLRequest) -> Bool { relay(for: request.url?.host) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let relay = Self.relay(for: request.url?.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        do {
            let (response, data) = try relay.answer(request, body: Self.body(of: request))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// A request's body: a session hands a protocol its body as a stream.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
#endif
