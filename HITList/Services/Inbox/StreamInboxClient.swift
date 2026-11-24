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

    /// The relay's rule and wake words, for every device: only what changes is sent. A relay from before the rule moved
    /// to it answers 404: `relayTooOld`.
    func setSettings(_ change: InboxSettingsChange, link: InboxLink) async throws -> InboxSettings {
        do {
            return try await send(InboxAPI.settings(change, link: link), as: InboxSettingsReply.self).settings
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

/// Delivers an ack that didn't reach the relay some other way (round 3, finding 4): on the iPhone, a background upload.
@MainActor
protocol StreamInboxAckSender: AnyObject {
    func send(ids: [String], link: InboxLink)
}

#if os(iOS)
/// The iPhone's ack of last resort (round 3, finding 4): an ack that failed goes again as a background upload, which iOS
/// carries out when it can, after the app is suspended or quit, and then wakes the app to say how it went
/// (`SyncAppDelegate`, `handleEventsForBackgroundURLSession`). A 2xx takes exactly its ids out of the ids waiting to be
/// acked (`StreamInboxSettings.ackFinished`, on the main actor); anything else leaves them for the next check. One
/// session per store (a Debug side store's is its own). The request carries the inbox key in its header, as every
/// request to the relay does, and iOS keeps it with the upload until it is sent.
final class BackgroundAck: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = BackgroundAck()

    /// The inbox's side of it, on the main actor.
    @MainActor
    final class Sender: StreamInboxAckSender {
        func send(ids: [String], link: InboxLink) { BackgroundAck.shared.send(ids: ids, link: link) }
    }

    let identifier = "com.trammells.hitlist.stream-inbox.ack." + ModelContainerFactory.storeName
    private let lock = NSLock()
    private var finishEvents: (() -> Void)?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    /// Where an upload's body waits for iOS: the app's own Application Support, readable after the first unlock.
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StreamInboxAcks", isDirectory: true)
    }

    private struct Upload: Codable {
        let ids: [String]
        let file: String
    }

    func send(ids: [String], link: InboxLink) {
        var request = InboxAPI.ack(ids: ids, link: link)
        guard let body = request.httpBody else { return }
        request.httpBody = nil
        let file = Self.folder.appendingPathComponent("ack-\(UUID().uuidString).json")
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try body.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return
        }
        let task = lock.withLock { session }.uploadTask(with: request, fromFile: file)
        task.taskDescription = (try? JSONEncoder().encode(Upload(ids: ids, file: file.lastPathComponent)))
            .flatMap { String(data: $0, encoding: .utf8) }
        task.resume()
    }

    /// iOS woke the app to hand over this session's results: the session is made again (it finds its tasks), and
    /// `completion` runs once they have all been heard. False for another session's.
    func handleEvents(identifier: String, completion: @escaping () -> Void) -> Bool {
        guard identifier == self.identifier else { return false }
        lock.withLock {
            finishEvents = completion
            _ = session
        }
        return true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let text = task.taskDescription, let upload = try? JSONDecoder().decode(Upload.self, from: Data(text.utf8)) else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let delivered = error == nil && (200..<300).contains(status)
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(upload.file))
        DispatchQueue.main.async {
            StreamInboxSettings(defaults: AppGroup.defaults).ackFinished(upload.ids, delivered: delivered)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock { () -> (() -> Void)? in
            defer { finishEvents = nil }
            return finishEvents
        }
        DispatchQueue.main.async { completion?() }
    }
}
#endif

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
