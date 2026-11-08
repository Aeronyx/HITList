import Foundation

/// What Browse's search field does with what was typed (brief 61: "Filters should also just become part of
/// the search bar"). Text that reads as a filter query (`#Work`, `@waiting & p1`, `no date`, `overdue`)
/// filters by it, as a saved filter would; anything else looks through titles and notes
/// (`TaskOrdering.search`), as the field always has.
///
/// "Reads as a query" means two things: it parses (`FilterQuery`), and it says so. Either it carries a mark
/// of the filter language (a `#`, `@` or `%` name, `&`, `|`, `(`, a leading `!`, a comparison, a quoted
/// phrase, a `due:`-style field, a comma between terms), or every word in it is a whole keyword of the
/// language (`overdue`, `no date`, `p1`, `friday`, `7 days`). The parser also takes short forms (`tom`,
/// `tod`, `mon`) and lone numbers as dates; in a search field those are far more often a name ("Tom") or a
/// number, so they search.
public enum SearchIntent: Equatable, Sendable {
    /// Nothing typed but spaces.
    case empty
    /// Words to look for in titles and notes. `unfinishedQuery` is set when the text has a query's marks but
    /// doesn't parse yet ("@waiting &"), so the empty state can say what is missing.
    case text(String, unfinishedQuery: String? = nil)
    /// A filter-language query, trimmed.
    case query(String)

    public init(_ raw: String, calendar: Calendar = .current, now: Date = Date()) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { self = .empty; return }
        let marked = Self.hasQueryMarks(text)
        do {
            _ = try FilterQuery(text, calendar: calendar, now: now)
        } catch let error as FilterQueryError {
            self = .text(text, unfinishedQuery: marked ? error.message : nil)
            return
        } catch {
            self = .text(text)
            return
        }
        self = marked || Self.hasSeparators(text) || Self.isAllKeywords(text) ? .query(text) : .text(text)
    }

    /// The query, when the text is one.
    public var query: String? {
        if case .query(let source) = self { return source }
        return nil
    }

    // MARK: - The rule

    /// Characters only the filter language gives meaning to. `!` counts only at the start of a term
    /// ("!#Work", "today & !p4"), so "Call mom!" stays text. Text with one of these that doesn't parse is a
    /// query on its way ("@waiting &").
    static func hasQueryMarks(_ text: String) -> Bool {
        if text.contains(where: { "#@%&|()<>=\"".contains($0) }) { return true }
        var previous: Character = " "
        for character in text {
            if character == "!", previous.isWhitespace || previous == "(" { return true }
            previous = character
        }
        return false
    }

    /// A comma (the language's "and") or a field's colon: a query when the text parses ("today, p1",
    /// "due: friday"), but ordinary punctuation when it doesn't ("milk, eggs", "Re: invoice").
    static func hasSeparators(_ text: String) -> Bool {
        text.contains(",") || text.contains(":")
    }

    /// Every word a whole keyword of the language (numbers allowed beside one: "7 days"), and at least one
    /// that isn't a number.
    static func isAllKeywords(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        var sawKeyword = false
        for word in words {
            if keywords.contains(word) { sawKeyword = true; continue }
            if Int(word.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))) != nil { continue }
            return false
        }
        return sawKeyword
    }

    /// The filter language's whole words (`FilterSyntax`), without its short forms and without "all" (which,
    /// alone, would list every open task while someone types "allergy").
    static let keywords: Set<String> = [
        "today", "tomorrow", "yesterday", "overdue", "no", "has", "date", "due", "time", "recurring",
        "completed", "priority", "project", "labels", "this", "next", "week", "weeks", "month", "months",
        "weekend", "day", "days", "before", "after", "p1", "p2", "p3", "p4",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
        "november", "december",
    ]
}
