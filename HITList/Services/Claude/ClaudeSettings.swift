import Foundation
import HITListCore

/// Settings → Claude's choices (brief 43), kept in `AppGroup.defaults` so the `hitlist-mcp` helper can
/// read "Allow Claude" too. Per store: a Debug build on its side store (`HITLIST_STORE_SUFFIX`) has its
/// own switch and rule, so trying the connector there never opens the TestFlight app's tasks. Device-local,
/// like every preference: each Mac and iPhone is set on its own.
struct ClaudeSettings {
    let defaults: UserDefaults
    let storeSuffix: String?

    init(defaults: UserDefaults = AppGroup.defaults,
         storeSuffix: String? = ProcessInfo.processInfo.environment[SyncStoreGuard.suffixVariable]) {
        self.defaults = defaults
        self.storeSuffix = ClaudeWire.cleanSuffix(storeSuffix)
    }

    /// The master switch "Allow Claude": off by default. Off, the app keeps no port open at all.
    var allowedKey: String { ClaudeWire.allowedKey(storeSuffix: storeSuffix) }
    var modeKey: String { key(Preferences.claudeMode) }
    var hiddenLabelKey: String { key(Preferences.claudeHiddenLabel) }
    var sharedLabelKey: String { key(Preferences.claudeSharedLabel) }

    private func key(_ base: String) -> String { base + (storeSuffix.map { ".\($0)" } ?? "") }

    var isAllowed: Bool {
        get { defaults.bool(forKey: allowedKey) }
        nonmutating set { defaults.set(newValue, forKey: allowedKey) }
    }

    /// Which tasks Claude (and the export) may see. Defaults: everything except @private.
    var rule: ClaudeAccessRule {
        get {
            ClaudeAccessRule(mode: defaults.string(forKey: modeKey).flatMap(ClaudeAccessRule.Mode.init(rawValue:)) ?? .allExceptHidden,
                             hiddenLabel: defaults.string(forKey: hiddenLabelKey) ?? ClaudeAccessRule.defaultHiddenLabel,
                             sharedLabel: defaults.string(forKey: sharedLabelKey) ?? ClaudeAccessRule.defaultSharedLabel)
        }
        nonmutating set {
            defaults.set(newValue.mode.rawValue, forKey: modeKey)
            defaults.set(newValue.hiddenLabel, forKey: hiddenLabelKey)
            defaults.set(newValue.sharedLabel, forKey: sharedLabelKey)
        }
    }
}

/// The connector's preference keys (brief 43). `ClaudeSettings` adds the store suffix for a side store;
/// "Allow Claude" is `ClaudeWire.allowedKey`, which the helper reads as well.
extension Preferences {
    static let claudeMode = "claude.mode"
    static let claudeHiddenLabel = "claude.hiddenLabel"
    static let claudeSharedLabel = "claude.sharedLabel"
}
