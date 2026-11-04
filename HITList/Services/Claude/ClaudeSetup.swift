import Foundation
import HITListCore

/// What Settings → Claude shows to connect Claude (brief 43): the `claude_desktop_config.json` entry and
/// the `claude mcp add` command, both pointing at the helper inside this copy of HITList.app. A side store
/// (a Debug build's "Development") adds `--store`, so the helper finds that build and not the TestFlight one.
enum ClaudeSetup {
    static let serverKey = "hitlist"

    /// The helper in the running app: HITList.app/Contents/MacOS/hitlist-mcp.
    static var helperURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/MacOS/hitlist-mcp")
    }

    static func arguments(storeSuffix: String?) -> [String] {
        ClaudeWire.cleanSuffix(storeSuffix).map { ["--store", $0] } ?? []
    }

    /// The whole `claude_desktop_config.json` for someone who has none yet; with one, its `"hitlist"`
    /// entry goes inside the existing `"mcpServers"`.
    static func desktopConfig(helperPath: String, storeSuffix: String?) -> String {
        var server: [String: JSONValue] = ["command": .string(helperPath)]
        let args = arguments(storeSuffix: storeSuffix)
        if !args.isEmpty { server["args"] = .array(args.map { .string($0) }) }
        let config: JSONValue = ["mcpServers": [serverKey: .object(server)]]
        return config.prettyString()
    }

    /// `claude mcp add` for every project (user scope).
    static func claudeCodeCommand(helperPath: String, storeSuffix: String?) -> String {
        (["claude", "mcp", "add", "--scope", "user", serverKey, "--", helperPath] + arguments(storeSuffix: storeSuffix))
            .map(shellQuoted).joined(separator: " ")
    }

    /// Single-quoted when it holds anything a shell would read (a space in a Debug build's path).
    static func shellQuoted(_ word: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+:@%=,"))
        if !word.isEmpty, word.unicodeScalars.allSatisfy(safe.contains) { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static let desktopConfigPath = "~/Library/Application Support/Claude/claude_desktop_config.json"
}
