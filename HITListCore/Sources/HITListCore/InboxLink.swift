import Foundation

/// The inbox link the Stream ring's relay prints for HITList (`relay/stream-inbox/setup.sh`, brief 176): the relay's
/// address with its inbox key after `#`, `https://stream-inbox.example.workers.dev/#<key>`. The key rides in the
/// fragment, which a browser never sends, so opening the link anywhere shows only the relay's `{"ok":true}`.
///
/// `https` only, but for `http://127.0.0.1` and `http://localhost` (a relay run on this Mac by its tests). Anything else
/// is `notALink`.
public struct InboxLink: Equatable, Sendable {
    /// `https://host[:port]`, no path.
    public let origin: URL
    public let key: String

    /// What Settings says about anything else.
    public static let notALink = "That isn't an inbox link"

    /// The inbox key's length: `openssl rand -hex 32` makes 64; a shorter or longer key of the same characters is
    /// taken too.
    public static let keyLength = 16...256

    /// Reads a pasted link: surrounding spaces, new lines, quotes and angle brackets are dropped first.
    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("<", ">"), ("\"", "\""), ("'", "'"), ("“", "”"), ("`", "`")]
        where trimmed.count >= 2 && trimmed.hasPrefix(open) && trimmed.hasSuffix(close) {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        guard let parts = URLComponents(string: trimmed),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil,
              parts.path.isEmpty || parts.path == "/",
              let key = parts.fragment
        else { return nil }
        self.init(scheme: scheme, host: host, port: parts.port, key: key)
    }

    /// The link again from what a device keeps: the origin in its settings and the key in its Keychain.
    public init?(origin: String, key: String) {
        guard let parts = URLComponents(string: origin), let scheme = parts.scheme?.lowercased(),
              let host = parts.host?.lowercased(), parts.path.isEmpty || parts.path == "/" else { return nil }
        self.init(scheme: scheme, host: host, port: parts.port, key: key)
    }

    private init?(scheme: String, host: String, port: Int?, key: String) {
        guard scheme == "https" || (scheme == "http" && Self.localHosts.contains(host)) else { return nil }
        guard Self.keyLength.contains(key.count), key.unicodeScalars.allSatisfy(Self.keyCharacters.contains) else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.port = port
        guard let origin = parts.url else { return nil }
        self.origin = origin
        self.key = key
    }

    /// The hosts a plain-`http` link may name: this Mac, for the relay's own tests.
    public static let localHosts: Set<String> = ["127.0.0.1", "localhost"]

    /// URL-safe characters only (RFC 3986's unreserved set).
    private static let keyCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// The link as `setup.sh` prints it.
    public var text: String { origin.absoluteString + "/#" + key }

    /// One of the relay's endpoints: `url("/inbox/claim")`.
    public func url(_ path: String) -> URL {
        URL(string: origin.absoluteString + (path.hasPrefix("/") ? path : "/" + path))!
    }
}
