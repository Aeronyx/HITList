import Foundation

enum InboxText {
    /// The inbox header, "Inbox · 7".
    static func header(count: Int) -> String { "Inbox · \(count)" }

    /// Review Inbox's progress line, "3 of 7".
    static func progress(_ position: Int, of total: Int) -> String { "\(position) of \(total)" }

    /// The Inbox menu's item, "Review 3 unsorted…"; nil (no item) when nothing needs review.
    static func reviewMenuItem(count: Int) -> String? {
        count > 0 ? "Review \(count) unsorted…" : nil
    }
}
