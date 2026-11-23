import Foundation

/// What HITList asks the Stream ring's inbox relay (`relay/stream-inbox`, brief 176) and what it answers. Pure: the
/// requests are built here and the answers read here; the app's `StreamInbox` sends them.
///
/// A device claims what waits (`claim`: the captures nobody holds, oldest first, at most 50, held for it ten minutes),
/// makes tasks of them, then acks the ones it handled (`ack`: the relay deletes their words and keeps their ids 30
/// days, to catch a redelivery). Every request carries the inbox key as a bearer token; every answer is JSON.
public enum InboxAPI {
    /// How long a request may take.
    public static let timeout: TimeInterval = 15
    /// The most the relay hands over at once.
    public static let claimLimit = 50
    public static let maxIDLength = 256
    /// The relay's own test captures (`POST /inbox/test`): never Stream's.
    public static let testIDPrefix = "test-"
    public static let testText = "Test capture from your Stream ring"

    public enum Endpoint: String, CaseIterable, Sendable {
        case claim = "/inbox/claim"
        case ack = "/inbox/ack"
        case status = "/inbox/status"
        case test = "/inbox/test"
        /// A one-time link that opens Stream's sign-in (the relay's poller, which needs no subscription).
        case connectLink = "/stream/connect-link"

        public var method: String { self == .status ? "GET" : "POST" }
    }

    public static func request(_ endpoint: Endpoint, link: InboxLink, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: link.url(endpoint.rawValue), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: timeout)
        request.httpMethod = endpoint.method
        request.setValue("Bearer \(link.key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    public static func claim(device: String, link: InboxLink) -> URLRequest {
        request(.claim, link: link, body: encode(["device": device]))
    }

    public static func ack(ids: [String], link: InboxLink) -> URLRequest {
        request(.ack, link: link, body: encode(["ids": ids]))
    }

    public static func status(link: InboxLink) -> URLRequest { request(.status, link: link) }

    public static func test(link: InboxLink) -> URLRequest { request(.test, link: link, body: Data("{}".utf8)) }

    public static func connectLink(link: InboxLink) -> URLRequest { request(.connectLink, link: link, body: Data("{}".utf8)) }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    /// Reads the relay's answers: dates as ISO 8601 with or without fractional seconds, or as numbers (seconds, or
    /// milliseconds when that large).
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
            }
            let text = try container.decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a date: \(text)")
        }
        return try decoder.decode(type, from: data)
    }

    static func parseDate(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }
}

/// One capture waiting in the relay.
public struct InboxItem: Decodable, Equatable, Sendable, Identifiable {
    /// Stream's `interaction_id`, or the relay's `test-…` for its own test capture.
    public let id: String
    public let text: String
    public let receivedAt: Date?

    public init(id: String, text: String, receivedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.receivedAt = receivedAt
    }

    /// The relay's test capture, which counts whatever the "starts with Task" rule says.
    public var isTest: Bool { id.hasPrefix(InboxAPI.testIDPrefix) }
}

/// `POST /inbox/claim`'s answer.
public struct InboxClaimReply: Decodable, Equatable, Sendable {
    public var items: [InboxItem]
    /// When the relay last heard a capture, from either source.
    public var lastReceivedAt: Date?

    public init(items: [InboxItem], lastReceivedAt: Date? = nil) {
        self.items = items
        self.lastReceivedAt = lastReceivedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([InboxItem].self, forKey: .items) ?? []
        lastReceivedAt = try? c.decodeIfPresent(Date.self, forKey: .lastReceivedAt)
    }

    private enum CodingKeys: String, CodingKey { case items, lastReceivedAt }
}

/// `POST /inbox/ack`'s answer.
public struct InboxAckReply: Decodable, Equatable, Sendable {
    public var acked: Int
}

/// `POST /stream/connect-link`'s answer: a one-time link to Stream's sign-in, ten minutes long.
public struct InboxConnectLink: Decodable, Equatable, Sendable {
    public var url: URL
    public var expiresAt: Date?
}

/// What the relay says when it refuses: `{"error": "…"}`.
public struct InboxErrorReply: Decodable, Equatable, Sendable {
    public var error: String
}

/// `GET /inbox/status`: what waits, when the relay last heard a capture and from where, the top-level fields of the last
/// one (how we learn what Stream really sends), and each source's state.
public struct InboxStatus: Decodable, Equatable, Sendable {
    public var pending: Int
    public var lastReceivedAt: Date?
    /// "webhook" (Stream pushed it) or "stream" (the relay asked Stream for it); "test" for the relay's own.
    public var lastSource: String?
    public var lastFields: [String]
    public var webhook: Webhook?
    public var stream: StreamConnection?

    public init(pending: Int = 0, lastReceivedAt: Date? = nil, lastSource: String? = nil, lastFields: [String] = [],
                webhook: Webhook? = nil, stream: StreamConnection? = nil) {
        self.pending = pending
        self.lastReceivedAt = lastReceivedAt
        self.lastSource = lastSource
        self.lastFields = lastFields
        self.webhook = webhook
        self.stream = stream
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pending = try c.decodeIfPresent(Int.self, forKey: .pending) ?? 0
        lastReceivedAt = try? c.decodeIfPresent(Date.self, forKey: .lastReceivedAt)
        lastSource = try? c.decodeIfPresent(String.self, forKey: .lastSource)
        lastFields = (try? c.decodeIfPresent([String].self, forKey: .lastFields)) ?? []
        webhook = try? c.decodeIfPresent(Webhook.self, forKey: .webhook)
        stream = try? c.decodeIfPresent(StreamConnection.self, forKey: .stream)
    }

    private enum CodingKeys: String, CodingKey { case pending, lastReceivedAt, lastSource, lastFields, webhook, stream }

    /// Stream's webhook (needs Stream's paid plan): it pushes each capture as it is saved.
    public struct Webhook: Decodable, Equatable, Sendable {
        public var lastReceivedAt: Date?
        public var lastResult: String?
        public var lastFields: [String]?

        public init(lastReceivedAt: Date? = nil, lastResult: String? = nil, lastFields: [String]? = nil) {
            self.lastReceivedAt = lastReceivedAt
            self.lastResult = lastResult
            self.lastFields = lastFields
        }
    }

    /// The relay's own connection to Stream (free): it asks Stream every minute. Stream ends it 90 days after it was
    /// approved, and after 30 days unused.
    public struct StreamConnection: Decodable, Equatable, Sendable {
        public var connected: Bool
        public var approvedAt: Date?
        public var expiresAt: Date?
        public var lastPollAt: Date?
        public var lastError: String?
        /// The argument names Stream's tool takes, as its `tools/list` says (what the first real connection tells us).
        public var toolArguments: [String]?
        /// The fields of the newest interaction the last poll saw.
        public var interactionFields: [String]?

        public init(connected: Bool, approvedAt: Date? = nil, expiresAt: Date? = nil, lastPollAt: Date? = nil,
                    lastError: String? = nil, toolArguments: [String]? = nil, interactionFields: [String]? = nil) {
            self.connected = connected
            self.approvedAt = approvedAt
            self.expiresAt = expiresAt
            self.lastPollAt = lastPollAt
            self.lastError = lastError
            self.toolArguments = toolArguments
            self.interactionFields = interactionFields
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            connected = (try? c.decodeIfPresent(Bool.self, forKey: .connected)) ?? false
            approvedAt = try? c.decodeIfPresent(Date.self, forKey: .approvedAt)
            expiresAt = try? c.decodeIfPresent(Date.self, forKey: .expiresAt)
            lastPollAt = try? c.decodeIfPresent(Date.self, forKey: .lastPollAt)
            lastError = try? c.decodeIfPresent(String.self, forKey: .lastError)
            toolArguments = try? c.decodeIfPresent([String].self, forKey: .toolArguments)
            interactionFields = try? c.decodeIfPresent([String].self, forKey: .interactionFields)
        }

        private enum CodingKeys: String, CodingKey {
            case connected, approvedAt, expiresAt, lastPollAt, lastError, toolArguments, interactionFields
        }

        /// How long before the end Settings offers to reconnect.
        public static let reconnectWithin: TimeInterval = 14 * 86_400

        /// Whole days left, rounded down; nil without an end.
        public func daysLeft(now: Date) -> Int? {
            expiresAt.map { max(0, Int($0.timeIntervalSince(now) / 86_400)) }
        }

        /// Once approved: ended, or ending within `reconnectWithin`.
        public func needsReconnect(now: Date) -> Bool {
            guard approvedAt != nil else { return false }
            guard connected, let expiresAt else { return true }
            return expiresAt.timeIntervalSince(now) < Self.reconnectWithin
        }
    }

    /// Where captures come from now.
    public enum Source: Equatable, Sendable {
        /// The relay asks Stream every minute.
        case everyMinute
        /// Stream pushes them (its webhook has delivered in the last 30 days).
        case pushed
        case both
        case none
    }

    /// How long a webhook that has gone quiet still counts as a source.
    public static let webhookCountsFor: TimeInterval = 30 * 86_400

    public func source(now: Date) -> Source {
        let polled = stream?.connected == true
        let pushed = webhook?.lastReceivedAt.map { now.timeIntervalSince($0) < Self.webhookCountsFor } ?? false
        switch (polled, pushed) {
        case (true, true): return .both
        case (true, false): return .everyMinute
        case (false, true): return .pushed
        case (false, false): return .none
        }
    }

    /// What Settings offers for the relay's connection to Stream.
    public enum StreamAction: Equatable, Sendable {
        case none
        /// Never connected and no webhook either: nothing brings captures yet.
        case connect
        /// Ended, or ending within two weeks.
        case reconnect
    }

    public func streamAction(now: Date) -> StreamAction {
        if let stream, stream.needsReconnect(now: now) { return .reconnect }
        if stream?.approvedAt == nil, source(now: now) == .none { return .connect }
        return .none
    }
}
