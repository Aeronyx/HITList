import Foundation

/// What HITList asks the Stream ring's inbox relay (`relay/stream-inbox`, brief 176) and what it answers. Pure: the
/// requests are built here and the answers read here; the app's `StreamInbox` sends them.
///
/// A device claims what waits (`claim`: the captures nobody holds, oldest first, at most 50, held for it half an hour,
/// with its push token so the relay can wake it), makes tasks of them, then acks the ones it handled (`ack`: the relay
/// deletes their words and keeps their ids 30 days, to catch a redelivery). The "starts with Task" rule is the relay's,
/// one for every device (`settings`). Every request carries the inbox key as a bearer token; every answer is JSON.
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
        /// The relay's settings, the same for every device: the "starts with Task" rule.
        case settings = "/inbox/settings"
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

    /// A claim, with this device's push token when it has one (the relay wakes it with a background push).
    public static func claim(device: String, push: InboxPushRegistration? = nil, link: InboxLink) -> URLRequest {
        request(.claim, link: link, body: encode(ClaimBody(device: device, push: push)))
    }

    private struct ClaimBody: Encodable {
        let device: String
        let push: InboxPushRegistration?
    }

    public static func settings(_ settings: InboxSettings, link: InboxLink) -> URLRequest {
        request(.settings, link: link, body: encode(settings))
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
    /// When it was said: Stream's own time for the interaction when it gave one, else when the relay got it.
    public let capturedAt: Date?

    public init(id: String, text: String, receivedAt: Date? = nil, capturedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.receivedAt = receivedAt
        self.capturedAt = capturedAt
    }

    /// The moment the words are read as of ("tomorrow" from the evening it was said, not the morning it was taken).
    public var saidAt: Date? { capturedAt ?? receivedAt }

    /// The relay's test capture, which counts whatever the "starts with Task" rule says.
    public var isTest: Bool { id.hasPrefix(InboxAPI.testIDPrefix) }
}

/// The relay's settings, one for every device.
public struct InboxSettings: Codable, Equatable, Sendable {
    /// Only captures whose first word is "Task" become tasks; the relay leaves the rest out as they arrive.
    public var onlyStartingWithTask: Bool

    public init(onlyStartingWithTask: Bool) {
        self.onlyStartingWithTask = onlyStartingWithTask
    }
}

/// `POST /inbox/settings`'s answer.
public struct InboxSettingsReply: Decodable, Equatable, Sendable {
    public var settings: InboxSettings
}

/// This device's push token, sent with each claim so the relay can wake it when a capture arrives.
public struct InboxPushRegistration: Encodable, Equatable, Sendable {
    public enum Environment: String, Encodable, Sendable {
        /// Debug builds.
        case development
        /// TestFlight and the App Store.
        case production
    }

    /// The token in lowercase hex.
    public let token: String
    public let environment: Environment
    /// "iOS", "iPadOS" or "macOS".
    public let platform: String

    public init(token: String, environment: Environment, platform: String) {
        self.token = token
        self.environment = environment
        self.platform = platform
    }
}

/// Whether the relay can wake this device: it has an Apple push key (`configured`) and this device's token
/// (`registered`).
public struct InboxPushState: Decodable, Equatable, Sendable {
    public var configured: Bool
    public var registered: Bool

    public init(configured: Bool, registered: Bool) {
        self.configured = configured
        self.registered = registered
    }
}

/// `POST /inbox/claim`'s answer.
public struct InboxClaimReply: Decodable, Equatable, Sendable {
    public var items: [InboxItem]
    /// When the relay last heard a capture, from either source.
    public var lastReceivedAt: Date?
    /// The relay's rule (nil from a relay older than the rule's move to it).
    public var settings: InboxSettings?
    public var push: InboxPushState?

    public init(items: [InboxItem], lastReceivedAt: Date? = nil, settings: InboxSettings? = nil, push: InboxPushState? = nil) {
        self.items = items
        self.lastReceivedAt = lastReceivedAt
        self.settings = settings
        self.push = push
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([InboxItem].self, forKey: .items) ?? []
        lastReceivedAt = try? c.decodeIfPresent(Date.self, forKey: .lastReceivedAt)
        settings = try? c.decodeIfPresent(InboxSettings.self, forKey: .settings)
        push = try? c.decodeIfPresent(InboxPushState.self, forKey: .push)
    }

    private enum CodingKeys: String, CodingKey { case items, lastReceivedAt, settings, push }
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
    /// The relay's rule, the same for every device.
    public var settings: InboxSettings?
    /// The two routes have shown they share ids (one interaction came by both).
    public var idsMatch: Bool
    /// Wake-ups: whether the relay has an Apple push key, for how many devices, and its last trouble.
    public var push: Push?

    public init(pending: Int = 0, lastReceivedAt: Date? = nil, lastSource: String? = nil, lastFields: [String] = [],
                webhook: Webhook? = nil, stream: StreamConnection? = nil, settings: InboxSettings? = nil,
                idsMatch: Bool = false, push: Push? = nil) {
        self.pending = pending
        self.lastReceivedAt = lastReceivedAt
        self.lastSource = lastSource
        self.lastFields = lastFields
        self.webhook = webhook
        self.stream = stream
        self.settings = settings
        self.idsMatch = idsMatch
        self.push = push
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pending = try c.decodeIfPresent(Int.self, forKey: .pending) ?? 0
        lastReceivedAt = try? c.decodeIfPresent(Date.self, forKey: .lastReceivedAt)
        lastSource = try? c.decodeIfPresent(String.self, forKey: .lastSource)
        lastFields = (try? c.decodeIfPresent([String].self, forKey: .lastFields)) ?? []
        webhook = try? c.decodeIfPresent(Webhook.self, forKey: .webhook)
        stream = try? c.decodeIfPresent(StreamConnection.self, forKey: .stream)
        settings = try? c.decodeIfPresent(InboxSettings.self, forKey: .settings)
        idsMatch = (try? c.decodeIfPresent(Bool.self, forKey: .idsMatch)) ?? false
        push = try? c.decodeIfPresent(Push.self, forKey: .push)
    }

    private enum CodingKeys: String, CodingKey {
        case pending, lastReceivedAt, lastSource, lastFields, webhook, stream, settings, idsMatch, push
    }

    /// The relay's Apple background pushes.
    public struct Push: Decodable, Equatable, Sendable {
        public var configured: Bool
        public var devices: Int
        public var lastSentAt: Date?
        public var lastError: String?

        public init(configured: Bool, devices: Int = 0, lastSentAt: Date? = nil, lastError: String? = nil) {
            self.configured = configured
            self.devices = devices
            self.lastSentAt = lastSentAt
            self.lastError = lastError
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            configured = (try? c.decodeIfPresent(Bool.self, forKey: .configured)) ?? false
            devices = (try? c.decodeIfPresent(Int.self, forKey: .devices)) ?? 0
            lastSentAt = try? c.decodeIfPresent(Date.self, forKey: .lastSentAt)
            lastError = try? c.decodeIfPresent(String.self, forKey: .lastError)
        }

        private enum CodingKeys: String, CodingKey { case configured, devices, lastSentAt, lastError }
    }

    /// What came back from Stream when the relay couldn't read it: never its words.
    public struct AnswerShape: Decodable, Equatable, Sendable {
        public var contentTypes: [String]
        /// For each text content, whether it was JSON.
        public var json: [Bool]
        public var structured: Bool?
        public var keys: [String]?
    }

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
        /// False when Stream's sign-in came with no way to renew it (no refresh token): it ends within the hour.
        public var refreshable: Bool?
        /// The shape of an answer the relay couldn't read.
        public var answerShape: AnswerShape?

        public init(connected: Bool, approvedAt: Date? = nil, expiresAt: Date? = nil, lastPollAt: Date? = nil,
                    lastError: String? = nil, toolArguments: [String]? = nil, interactionFields: [String]? = nil,
                    refreshable: Bool? = nil, answerShape: AnswerShape? = nil) {
            self.connected = connected
            self.approvedAt = approvedAt
            self.expiresAt = expiresAt
            self.lastPollAt = lastPollAt
            self.lastError = lastError
            self.toolArguments = toolArguments
            self.interactionFields = interactionFields
            self.refreshable = refreshable
            self.answerShape = answerShape
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
            refreshable = try? c.decodeIfPresent(Bool.self, forKey: .refreshable)
            answerShape = try? c.decodeIfPresent(AnswerShape.self, forKey: .answerShape)
        }

        private enum CodingKeys: String, CodingKey {
            case connected, approvedAt, expiresAt, lastPollAt, lastError, toolArguments, interactionFields, refreshable,
                 answerShape
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
