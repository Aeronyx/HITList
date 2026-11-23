import Foundation

/// What a capture said to the Stream ring, or a phrase Siri heard, becomes before the quick-add parser reads it
/// (brief 176). Speech arrives as a sentence: "Task: call the dentist tomorrow at 9am p2." The parser wants the card's
/// words: "Call the dentist tomorrow at 9am p2".
///
/// - Trimmed.
/// - One leading "Task", "To do", "Todo", "New task", "Add", "HITList" or "Hit list" dropped when a ":", "," or a dash
///   follows it ("Task: …", "Hit list, …", "Todo - …"); a dash only with a space after it, so "Add-on" stays.
/// - One trailing "." or "!" dropped (never "?": a question can be the task).
/// - The first letter a capital, unless the first word has capitals of its own ("iPhone case").
/// - Nil when nothing is left.
///
/// With Settings → Stream Ring → "Only captures that start with 'Task'" on, a capture counts only when its first word is
/// "Task" (any case, with or without the punctuation after it: speech gives "Task, …", "Task. …" and "Task …"), and
/// that word is dropped; every other capture stays in Stream (`text(from:onlyStartingWithTask:)` is nil).
public enum SpokenTask {
    /// The words a capture may start with to address the list, longest first so "New task" wins over "Task"'s turn.
    public static let leads = ["new task", "hit list", "hitlist", "to-do", "to do", "todo", "task", "add"]

    /// The text for the parser, or nil when nothing is left.
    public static func text(from capture: String) -> String? {
        finish(droppingLead(capture[...].trimmed))
    }

    /// Whether the capture's first word is "Task".
    public static func startsWithTask(_ capture: String) -> Bool {
        afterTaskWord(capture[...]) != nil
    }

    /// The text for the parser under the rule: with `onlyStartingWithTask`, nil for a capture that doesn't start with
    /// "Task" (it is left in Stream) and the rest of one that does; without it, `text(from:)`.
    public static func text(from capture: String, onlyStartingWithTask: Bool) -> String? {
        guard onlyStartingWithTask else { return text(from: capture) }
        guard let rest = afterTaskWord(capture[...]) else { return nil }
        return finish(rest)
    }

    // MARK: - The steps

    /// One lead word and the mark after it, or the text as it was.
    static func droppingLead(_ text: Substring) -> Substring {
        for lead in leads {
            guard text.count > lead.count, text.prefix(lead.count).lowercased() == lead else { continue }
            let afterSpaces = text.dropFirst(lead.count).drop { $0 == " " }
            guard let mark = afterSpaces.first else { continue }
            let rest = afterSpaces.dropFirst()
            switch mark {
            case ":", ",":
                return rest.trimmed
            case "-", "–", "—":
                // "Todo - buy milk" and "Todo – buy milk", never "Add-on".
                guard rest.isEmpty || rest.first?.isWhitespace == true else { continue }
                return rest.trimmed
            default:
                continue
            }
        }
        return text
    }

    /// The rest after a first word "Task": its mark (":", ",", ".", ";" or a dash) and spaces dropped; nil when the
    /// first word is something else ("Tasks", "Taskbar", "Add").
    static func afterTaskWord(_ text: Substring) -> Substring? {
        let trimmed = text.trimmed
        guard trimmed.prefix(4).lowercased() == "task" else { return nil }
        let rest = trimmed.dropFirst(4)
        guard let next = rest.first else { return rest }
        guard !(next.isLetter || next.isNumber || next == "'" || next == "’") else { return nil }
        var after = rest.drop { $0 == " " }
        if let mark = after.first, ":,.;-–—".contains(mark) { after = after.dropFirst() }
        return after.trimmed
    }

    /// One trailing "." or "!" off, the first letter a capital, nil when empty.
    static func finish(_ text: Substring) -> String? {
        var text = text.trimmed
        if let last = text.last, last == "." || last == "!" { text = text.dropLast().trimmed }
        guard let first = text.first else { return nil }
        let firstWord = text.prefix { !$0.isWhitespace }
        let hasOwnCapitals = firstWord.dropFirst().contains { $0.isUppercase }
        guard first.isLowercase, !hasOwnCapitals else { return String(text) }
        return first.uppercased() + text.dropFirst()
    }
}

private extension Substring {
    var trimmed: Substring {
        let start = firstIndex { !$0.isWhitespace } ?? endIndex
        let end = lastIndex { !$0.isWhitespace }.map { index(after: $0) } ?? start
        return self[start..<Swift.max(start, end)]
    }
}
