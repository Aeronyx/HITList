import Foundation

enum InboxText {
    /// Review Inbox's progress line, "3 of 7".
    static func progress(_ position: Int, of total: Int) -> String { "\(position) of \(total)" }

    /// Under Review Inbox's title: what the review goes through, "3 tasks with no date or Group".
    static func reviewSubtitle(count: Int) -> String {
        "\(count) \(count == 1 ? "task" : "tasks") with no date or Group"
    }

    /// The review's empty state.
    static let reviewedTitle = "Inbox reviewed"

    /// Under "Inbox reviewed": `left` tasks were put off with Later and still have no date or Group.
    static func reviewedMessage(left: Int) -> String {
        switch left {
        case 0: "Every task has a date or a Group."
        case 1: "1 task waits in the Inbox for later."
        default: "\(left) tasks wait in the Inbox for later."
        }
    }

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
