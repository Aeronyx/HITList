import Foundation

/// Which tasks Claude may see (brief 43). Labels carry the rule, so it needs no schema change:
/// either only the tasks labelled `sharedLabel` ("Only tasks with @claude", the default since brief 55),
/// or every task except those labelled `hiddenLabel` ("All tasks but @private").
///
/// A subtask has no labels of its own; it follows its parent. A hidden task is invisible to every
/// connector tool and to the export: not listed, not counted, not reachable by id, not searchable.
/// A Group or label is shown only when it has no tasks at all or at least one visible task, so the name
/// of a Group that holds nothing but hidden tasks never reaches Claude either.
public struct ClaudeAccessRule: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        /// Claude sees every task except those labelled `hiddenLabel`.
        case allExceptHidden = "allExcept"
        /// Claude sees only the tasks labelled `sharedLabel`.
        case onlyShared = "onlyShared"
    }

    public static let defaultHiddenLabel = "private"
    public static let defaultSharedLabel = "claude"

    public var mode: Mode
    public var hiddenLabel: String
    public var sharedLabel: String

    /// The default shares nothing until a task is labelled @claude (George, 2026-11-05).
    public init(mode: Mode = .onlyShared, hiddenLabel: String = defaultHiddenLabel,
                sharedLabel: String = defaultSharedLabel) {
        self.mode = mode
        self.hiddenLabel = Self.normalized(hiddenLabel, fallback: Self.defaultHiddenLabel)
        self.sharedLabel = Self.normalized(sharedLabel, fallback: Self.defaultSharedLabel)
    }

    /// A label name as typed in Settings ("@Private ") → the stored form ("Private"): trimmed, no
    /// leading "@", inner whitespace removed (quick add's labels are one word). Empty falls back.
    public static func normalized(_ name: String, fallback: String) -> String {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("@") { trimmed.removeFirst() }
        trimmed = trimmed.filter { !$0.isWhitespace }
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// The label this mode turns on: "private" (hides) or "claude" (shows).
    public var ruleLabel: String { mode == .allExceptHidden ? hiddenLabel : sharedLabel }

    /// Label names compare like quick add's: case-insensitively.
    static func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }

    /// Whether a task in its own right with these labels is visible.
    public func allows(labelNames: [String]) -> Bool {
        switch mode {
        case .allExceptHidden: !labelNames.contains { Self.same($0, hiddenLabel) }
        case .onlyShared: labelNames.contains { Self.same($0, sharedLabel) }
        }
    }

    /// Whether `task` is visible: a subtask by its parent's labels, any other task by its own.
    public func isVisible<T>(_ task: T, labelNames: (T) -> [String], parent: (T) -> T?) -> Bool {
        allows(labelNames: labelNames(parent(task) ?? task))
    }

    /// The visible tasks among `tasks`, in their order.
    public func visible<T>(_ tasks: [T], labelNames: (T) -> [String], parent: (T) -> T?) -> [T] {
        tasks.filter { isVisible($0, labelNames: labelNames, parent: parent) }
    }

    /// Whether a Group or label holding these tasks may be named: it holds none, or a visible one.
    public func showsContainer<T>(holding tasks: [T], labelNames: (T) -> [String], parent: (T) -> T?) -> Bool {
        tasks.isEmpty || tasks.contains { isVisible($0, labelNames: labelNames, parent: parent) }
    }

    /// The labels a task Claude adds or edits must keep: in `onlyShared` mode the shared label, so a
    /// task Claude made or changed never drops out of its own sight by accident. Returns `labelNames`
    /// with it added when missing.
    public func labelsKeepingAccess(_ labelNames: [String]) -> [String] {
        guard mode == .onlyShared, !labelNames.contains(where: { Self.same($0, sharedLabel) }) else { return labelNames }
        return labelNames + [sharedLabel]
    }
}
