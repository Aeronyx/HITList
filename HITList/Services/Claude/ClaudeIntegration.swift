import Foundation
import HITListCore

/// What Settings → Claude shows, and what turning the integration on says first (brief 49, George on
/// 2026-11-05: "disabled entirely by default; only offer the privacy option when the user intentionally
/// enables the Claude integration"). Plain values, so tests pin the gating.
///
/// Off (the default), the section is one switch and one sentence: no privacy choice, no setup snippets, no
/// Test connection, no Copy for Claude, and on the Mac no message port (`ClaudeConnector`), so the helper
/// answers `ClaudeWire.accessOffMessage`. The switch is the setting 0.6.0 called "Allow Claude"
/// (`ClaudeSettings.isAllowed`, the key the helper reads), so whoever turned that on keeps it on.
enum ClaudeIntegration {
    /// The pieces of Settings → Claude, in the order they appear.
    enum Part: Equatable, CaseIterable {
        /// The one switch, "Claude integration", with its sentence.
        case master
        /// Which tasks Claude sees: All but @private / Only @claude, the label, Visible now.
        case privacy
        /// Copy for Claude and Share….
        case export
        /// Mac: the Claude Desktop and Claude Code snippets.
        case setup
        /// Mac: Test connection.
        case test
    }

    static func parts(enabled: Bool, mac: Bool) -> [Part] {
        guard enabled else { return [.master] }
        return mac ? [.master, .privacy, .export, .setup, .test] : [.master, .privacy, .export]
    }

    /// Whether anything outside Settings may offer Copy for Claude (a menu, a share sheet, Browse). Nothing
    /// does today; anything that ever does asks this first.
    static func offersExport(_ settings: ClaudeSettings = ClaudeSettings()) -> Bool { settings.isAllowed }

    static let switchTitle = "Claude integration"

    /// The sentence under the switch: what the integration does, on this device.
    static func summary(mac: Bool) -> String {
        mac
            ? "Lets Claude Desktop and Claude Code on this Mac read and update the tasks you choose, while HITList is open."
            : "Lets you copy the tasks you choose as text, to paste into a chat with Claude or any other assistant."
    }

    /// The question before the switch goes on (HIG, generative AI: say what is used and how, ask first).
    struct Confirmation: Equatable {
        let title: String
        let message: String
        let confirm: String
    }

    static func confirmation(rule: ClaudeAccessRule, mac: Bool) -> Confirmation {
        let sees = switch rule.mode {
        case .allExceptHidden: "every task except those labelled @\(rule.hiddenLabel)"
        case .onlyShared: "only tasks labelled @\(rule.sharedLabel)"
        }
        let message = mac
            ? "Claude Desktop and Claude Code on this Mac will be able to read your tasks, add tasks, complete them and change them while HITList is open. Claude never deletes a task. It sees \(sees); you can change that next. What Claude reads goes to Anthropic under your Claude account's terms. Turn this off at any time."
            : "Copy for Claude will copy \(sees) as text, for you to paste into a chat with Claude or any other assistant; you can change which tasks next. HITList sends nothing on its own. Turn this off at any time."
        return Confirmation(title: "Turn On Claude Integration?", message: message, confirm: "Turn On")
    }

    /// The switch with its question: turning it on asks first (`isAsking`) and goes on only on `confirm()`;
    /// turning it off needs no question.
    struct Switch: Equatable {
        private(set) var isOn: Bool
        private(set) var isAsking = false

        init(isOn: Bool) { self.isOn = isOn }

        /// The switch was moved to `on`.
        mutating func request(_ on: Bool) {
            if on {
                if !isOn { isAsking = true }
            } else {
                isOn = false
                isAsking = false
            }
        }

        mutating func confirm() {
            guard isAsking else { return }
            isAsking = false
            isOn = true
        }

        mutating func cancel() { isAsking = false }
    }
}
