import Foundation

/// HITList's URL scheme (brief 74), the widgets' way into the app: a task's row opens that task, the rest of a widget
/// opens its screen. Compiled into the app and the widget extension (project.yml), so both spell the links one way.
///
///     hitlist://task/6F9619FF-8B86-D011-B42D-00C04FC964FF
///     hitlist://today      hitlist://upcoming      hitlist://flipboard
///
/// The app routes them through `IntentRouter`, as Siri's Open intents and Spotlight results are
/// (`DeepLinkRouting.swift`).
enum DeepLink: Equatable, Hashable, Sendable {
    case task(UUID)
    case today
    case upcoming
    case flipboard

    static let scheme = "hitlist"

    /// The link a URL names; nil for anything else (another scheme, an unknown screen, a malformed id).
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        let path = url.path().split(separator: "/").map(String.init)
        switch (host, path.count) {
        case ("today", 0): self = .today
        case ("upcoming", 0): self = .upcoming
        case ("flipboard", 0): self = .flipboard
        case ("task", 1):
            guard let id = UUID(uuidString: path[0]) else { return nil }
            self = .task(id)
        default: return nil
        }
    }

    var url: URL {
        switch self {
        case .task(let id): URL(string: "\(Self.scheme)://task/\(id.uuidString)")!
        case .today: URL(string: "\(Self.scheme)://today")!
        case .upcoming: URL(string: "\(Self.scheme)://upcoming")!
        case .flipboard: URL(string: "\(Self.scheme)://flipboard")!
        }
    }
}
