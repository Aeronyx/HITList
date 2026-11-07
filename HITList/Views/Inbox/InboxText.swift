import Foundation

enum InboxText {
    /// The inbox header, "Inbox · 7".
    static func header(count: Int) -> String { "Inbox · \(count)" }

    /// Review Inbox's progress line, "3 of 7".
    static func progress(_ position: Int, of total: Int) -> String { "\(position) of \(total)" }

    /// The review card's age line, "Added 3 days ago".
    static func added(_ created: Date, now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        return "Added \(formatter.localizedString(for: min(created, now), relativeTo: now))"
    }

    /// The Inbox menu's item, "Review 3 unsorted…"; nil (no item) when nothing needs review.
    static func reviewMenuItem(count: Int) -> String? {
        count > 0 ? "Review \(count) unsorted…" : nil
    }
}
