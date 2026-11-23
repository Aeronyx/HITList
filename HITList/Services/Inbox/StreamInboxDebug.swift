#if DEBUG
import Foundation
import SwiftData
import HITListCore

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
        let daysLeft = UserDefaults.standard.object(forKey: demoDaysLeftKey) as? Int ?? 87
        let relay = StreamInboxFakeRelay.demo(daysLeft: daysLeft)
        return StreamInbox(container: container, keyStore: MemoryInboxKey(), client: relay.client, isLive: true)
    }

    @MainActor
    static func connectIfAsked(_ inbox: StreamInbox) {
        guard isSideStore, let link = UserDefaults.standard.string(forKey: connectKey), !link.isEmpty,
              !inbox.isConnected || inbox.link?.text != InboxLink(link)?.text else { return }
        Task { _ = await inbox.connect(linkText: link) }
    }
}

/// A relay in this process: the endpoints and answers of `relay/stream-inbox/worker.js`, in memory, reached through
/// `FakeRelayURLProtocol` on a session of its own. The hosted tests make one each (and make it fail as they need);
/// `-streamInboxDemo YES` uses `demo()`.
final class StreamInboxFakeRelay: @unchecked Sendable {
    struct Capture {
        var id: String
        var text: String
        var receivedAt: Date
        var claimedBy: String?
        var claimedAt: Date?
    }

    /// One request as it reached the relay.
    struct Received {
        var method: String
        var path: String
        var body: Data
        var authorization: String?

        /// An ack's ids.
        var ids: [String]? {
            (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["ids"] as? [String]
        }
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
        return relay
    }

    var link: String { "https://\(host)/#\(key)" }
    var client: StreamInboxClient { StreamInboxClient(session: session) }

    func add(_ id: String, _ text: String, at date: Date = Date()) {
        locked {
            waiting.append(Capture(id: id, text: text, receivedAt: date))
            lastReceivedAt = date
        }
    }

    func setStream(connected: Bool, approvedAt: Date, lastPollAt: Date?) {
        locked {
            stream = ["connected": connected, "approvedAt": Self.iso(approvedAt),
                      "expiresAt": Self.iso(approvedAt.addingTimeInterval(90 * 86_400)),
                      "lastPollAt": Self.json(lastPollAt.map(Self.iso)), "lastError": NSNull(),
                      "toolArguments": ["limit", "days"], "interactionFields": ["id", "text", "created_at"]]
        }
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
                var items: [[String: Any]] = []
                for index in waiting.indices.sorted(by: { waiting[$0].receivedAt < waiting[$1].receivedAt }) {
                    let capture = waiting[index]
                    let free = capture.claimedAt.map { now.timeIntervalSince($0) > 600 } ?? true
                    guard free || capture.claimedBy == device, items.count < InboxAPI.claimLimit else { continue }
                    waiting[index].claimedBy = device
                    waiting[index].claimedAt = now
                    items.append(["id": capture.id, "text": capture.text, "receivedAt": Self.iso(capture.receivedAt)])
                }
                return reply(200, ["items": items, "lastReceivedAt": Self.json(lastReceivedAt.map(Self.iso))])
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
                                   "webhook": ["lastReceivedAt": NSNull(), "lastResult": NSNull(), "lastFields": [String]()],
                                   "stream": Self.json(stream)])
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
