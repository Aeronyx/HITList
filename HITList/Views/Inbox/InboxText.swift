import Foundation

enum InboxText {
    /// The inbox header, "Inbox · 7".
    static func header(count: Int) -> String { "Inbox · \(count)" }

    /// Process mode's progress line, "3 of 7".
    static func progress(_ position: Int, of total: Int) -> String { "\(position) of \(total)" }
}
