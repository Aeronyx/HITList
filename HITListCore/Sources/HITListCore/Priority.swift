import Foundation

/// Task priority. `p1` is the most urgent, `p4` means "no priority" (Todoist convention).
public enum Priority: Int, Codable, CaseIterable, Sendable, Hashable {
    case p1 = 1
    case p2 = 2
    case p3 = 3
    case p4 = 4

    public static let none: Priority = .p4

    public init(clamping raw: Int) {
        self = Priority(rawValue: min(4, max(1, raw))) ?? .p4
    }

    public var displayName: String {
        switch self {
        case .p1: return "Priority 1"
        case .p2: return "Priority 2"
        case .p3: return "Priority 3"
        case .p4: return "No priority"
        }
    }

    public var shortName: String { "P\(rawValue)" }

    /// True when this priority is more urgent than `other`.
    public func isMoreUrgent(than other: Priority) -> Bool { rawValue < other.rawValue }
}
