import Foundation
import HITListCore

/// Talks to the Stream ring's relay (brief 176; `InboxAPI` builds each request): 15 s a request, no retries. A refusal
/// or a failure comes back as a `StreamInboxProblem`, which says it in a person's words.
struct StreamInboxClient {
    let session: URLSession

    static func live() -> StreamInboxClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = InboxAPI.timeout
        configuration.timeoutIntervalForResource = InboxAPI.timeout
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return StreamInboxClient(session: URLSession(configuration: configuration))
    }

    func claim(device: String, push: InboxPushRegistration?, link: InboxLink) async throws -> InboxClaimReply {
        try await send(InboxAPI.claim(device: device, push: push, link: link), as: InboxClaimReply.self)
    }

    /// The relay's rule, for every device. A relay from before the rule moved to it answers 404: `relayTooOld`.
    func setSettings(_ settings: InboxSettings, link: InboxLink) async throws -> InboxSettings {
        do {
            return try await send(InboxAPI.settings(settings, link: link), as: InboxSettingsReply.self).settings
        } catch StreamInboxProblem.notARelay {
            throw StreamInboxProblem.relayTooOld
        }
    }

    func ack(ids: [String], link: InboxLink) async throws -> InboxAckReply {
        try await send(InboxAPI.ack(ids: ids, link: link), as: InboxAckReply.self)
    }

    func status(link: InboxLink) async throws -> InboxStatus {
        try await send(InboxAPI.status(link: link), as: InboxStatus.self)
    }

    func test(link: InboxLink) async throws {
        _ = try await data(InboxAPI.test(link: link))
    }

    func connectLink(link: InboxLink) async throws -> InboxConnectLink {
        try await send(InboxAPI.connectLink(link: link), as: InboxConnectLink.self)
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await data(request)
        do {
            return try InboxAPI.decode(type, from: data)
        } catch {
            throw StreamInboxProblem.unreadable
        }
    }

    private func data(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw StreamInboxProblem(error)
        }
        guard let http = response as? HTTPURLResponse else { throw StreamInboxProblem.unreadable }
        guard (200..<300).contains(http.statusCode) else { throw StreamInboxProblem(status: http.statusCode) }
        return data
    }
}

/// What went wrong, in words for Settings. None names how HITList syncs (`StreamRingSettingsTests`).
enum StreamInboxProblem: Error, Equatable, Sendable {
    case notALink
    case offline
    case unreachable
    case timedOut
    case keyRefused
    case notARelay
    case relayTrouble(Int)
    case unreadable
    case keychain
    /// The Keychain couldn't be read just now (locked before the first unlock after a restart): not a missing key.
    case keyUnavailable
    /// The relay is older than what HITList asked of it: setup.sh again redeploys it.
    case relayTooOld
    case storeUnavailable
    /// Captures that couldn't be made into tasks this time (a save failed): they stay in the relay.
    case notSaved(Int)

    init(_ error: Error) {
        if let problem = error as? StreamInboxProblem {
            self = problem
            return
        }
        switch (error as? URLError)?.code {
        case .notConnectedToInternet?, .dataNotAllowed?, .internationalRoamingOff?: self = .offline
        case .timedOut?: self = .timedOut
        case .cancelled?: self = .timedOut
        default: self = .unreachable
        }
    }

    init(status: Int) {
        switch status {
        case 401, 403: self = .keyRefused
        case 404, 405: self = .notARelay
        default: self = .relayTrouble(status)
        }
    }

    var words: String {
        switch self {
        case .notALink: InboxLink.notALink
        case .offline: "This device is offline. Captures wait in your relay."
        case .unreachable: "Couldn't reach your relay. Captures wait there for next time."
        case .timedOut: "Your relay didn't answer in time. Captures wait there for next time."
        case .keyRefused: "Your relay didn't accept this device's key. Paste the inbox link again; setup.sh prints it."
        case .notARelay: "That address doesn't answer like an inbox relay."
        case .relayTrouble(let code): "Your relay had a problem (error \(code)). Captures wait there for next time."
        case .unreadable: "Your relay's answer couldn't be read. Run setup.sh again to update it."
        case .keychain: "This device couldn't keep the inbox key in its Keychain."
        case .keyUnavailable: "This device's Keychain can't be read until it is unlocked. HITList checks again then."
        case .relayTooOld: "Your relay is older than this switch. Run setup.sh again to update it."
        case .storeUnavailable: "HITList couldn't open your tasks, so captures wait in your relay."
        case .notSaved(let count):
            count == 1
                ? "A capture couldn't be added. It stays in your relay for next time."
                : "\(count) captures couldn't be added. They stay in your relay for next time."
        }
    }
}
