import Foundation

/// Hard limits on what a task holds. Titles are cut here on every path that writes one (`TaskActions`,
/// the task popout); rows wrap a long title in full, so the cap keeps a stray paste from making a row
/// a page tall.
public enum TaskLimits {
    /// Characters in a title (George: 500).
    public static let titleCharacters = 500

    /// `title` cut to `titleCharacters`, whitespace trimmed.
    public static func clampedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > titleCharacters ? String(trimmed.prefix(titleCharacters)) : trimmed
    }

    /// A description's first line, for a list row (the popout shows all of it).
    public static func firstLine(of notes: String) -> String {
        notes.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
