import Foundation

// Several weekdays at once repeat weekly (brief 98, George 2026-11-11: "add detection/support for multi-day
// phrases such as 'vacuum on tuesday thursday and saturday'"). A task has one date, so days named together
// can only be a repeat; one weekday alone stays a date ("call mom fri"). Each phrase is one highlight.
//
//   vacuum on tuesday thursday and saturday · tue thu sat · mon, wed & fri · mon/wed/fri · mon-fri
//   every mon, wed & fri · every other tue and thu · on mondays · on tuesdays and thursdays
//   every week on fri · weekly on mon and thu · every 2 weeks on tue and thu · every other week on mon, wed
//   weekdays · on weekdays · weekends · on weekends
//
// Not a list: days apart ("fri about sunday"), "or" ("mon or tue"), after "between" or "either", one day.
extension QuickAddParser {
    /// A weekly repeat on named weekdays starting at `words[i]`, or nil for the rest of the repeat grammar.
    static func matchWeekdayRepeat(_ words: [String], at i: Int) -> (RecurrenceRule, Int)? {
        let reader = WeekdayListReader(words: words)
        switch reader[i] {
        case "every":
            // "every mon, wed & fri", "every other tue and thu": any number of days.
            var k = i + 1
            var interval = 1
            if reader[k] == "other" { interval = 2; k += 1 }
            if let list = reader.list(at: k) {
                return (RecurrenceRule(frequency: .weekly, interval: interval, weekdays: list.days), k - i + list.consumed)
            }
            // "every week on fri", "every other week on mon, wed", "every 2 weeks on tue and thu".
            guard let (weeks, n) = reader.weeks(at: i + 1), reader[i + 1 + n] == "on",
                  let list = reader.list(at: i + 2 + n) else { return nil }
            return (RecurrenceRule(frequency: .weekly, interval: weeks, weekdays: list.days), 2 + n + list.consumed)
        case "weekly":
            guard reader[i + 1] == "on", let list = reader.list(at: i + 2) else { return nil }
            return (RecurrenceRule(frequency: .weekly, weekdays: list.days), 2 + list.consumed)
        case "on":
            // "on weekdays", "on weekends", "on mondays", "on tue and thu"; "on fri" is a date.
            if let (rule, n) = reader.weekdaysOrWeekends(at: i + 1) { return (rule, 1 + n) }
            guard let list = reader.list(at: i + 1), list.days.count >= 2 || list.isPlural else { return nil }
            return (RecurrenceRule(frequency: .weekly, weekdays: list.days), 1 + list.consumed)
        default:
            if let found = reader.weekdaysOrWeekends(at: i) { return found }
            // "tue thu sat", "mon/wed/fri", "mon-fri"; not "fri" alone, "mondays" alone, or "between mon and fri".
            guard let list = reader.list(at: i), list.days.count >= 2,
                  !["between", "either"].contains(reader[i - 1] ?? "") else { return nil }
            return (RecurrenceRule(frequency: .weekly, weekdays: list.days), list.consumed)
        }
    }
}

/// Reads weekday lists for `QuickAddParser.matchWeekdayRepeat`; every word is normalised (lowercased,
/// trailing ",.;" dropped) and out-of-range reads are nil.
private struct WeekdayListReader {
    let words: [String]

    subscript(_ k: Int) -> String? { k >= 0 && k < words.count ? DateExpressionParser.normalize(words[k]) : nil }

    struct List {
        var days: Set<Int>
        var consumed: Int
        /// A day was named in the plural ("mondays"): a repeat even alone, after "on".
        var isPlural: Bool
    }

    /// Weekdays at `k`, each one or more days ("tue", "tuesdays", "mon/wed/fri", "mon-fri"), with nothing,
    /// "and", "&", "+", "," or "/" between them. A separator with no day after it is not part of the list.
    func list(at k: Int) -> List? {
        guard let first = self[k].flatMap(Self.item) else { return nil }
        var list = List(days: first.days, consumed: 1, isPlural: first.isPlural)
        var j = k + 1
        while let word = self[j] {
            let gap = Self.separators.contains(word) ? 1 : 0
            guard let next = self[j + gap].flatMap(Self.item) else { break }
            list.days.formUnion(next.days)
            list.isPlural = list.isPlural || next.isPlural
            j += gap + 1
            list.consumed = j - k
        }
        return list
    }

    /// "week", "other week", "2 weeks" at `k` (after "every"): the interval and the words it takes.
    func weeks(at k: Int) -> (Int, Int)? {
        if self[k] == "week" { return (1, 1) }
        if self[k] == "other", self[k + 1] == "week" { return (2, 2) }
        guard let n = self[k].flatMap({ Int($0) }), (1...RecurrenceRule.maxInterval).contains(n),
              self[k + 1].flatMap({ DateExpressionParser.unitDays($0) })?.component == .weekOfYear else { return nil }
        return (n, 2)
    }

    /// "weekdays" or "weekends" (the plurals: "weekend" alone is this weekend's date, "weekday" a title word).
    func weekdaysOrWeekends(at k: Int) -> (RecurrenceRule, Int)? {
        switch self[k] {
        case "weekdays": return (.weekdays, 1)
        case "weekends": return (RecurrenceRule(frequency: .weekly, weekdays: [1, 7]), 1)
        default: return nil
        }
    }

    static let separators: Set<String> = ["and", "&", "+", ",", "/"]

    /// The days one word names: "tue", "tuesdays", "mon/wed/fri", "mon,thu", "mon-fri", "fri-sun".
    static func item(_ word: String) -> (days: Set<Int>, isPlural: Bool)? {
        let pieces = word.split(whereSeparator: { $0 == "/" || $0 == "," || $0 == "+" || $0 == "&" })
        guard !pieces.isEmpty else { return nil }
        var days = Set<Int>()
        var plural = false
        for piece in pieces {
            let ends = piece.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "–" || $0 == "—" })
            if ends.count == 2 {
                guard let from = DateExpressionParser.weekdayNames[String(ends[0])],
                      let to = DateExpressionParser.weekdayNames[String(ends[1])], from != to else { return nil }
                var day = from
                while true {
                    days.insert(day)
                    if day == to { break }
                    day = day % 7 + 1
                }
            } else if ends.count == 1, let (day, isPlural) = weekday(String(piece)) {
                days.insert(day)
                plural = plural || isPlural
            } else {
                return nil
            }
        }
        return (days, plural)
    }

    /// "tue", "tuesday", or the plural of a full name ("tuesdays").
    static func weekday(_ word: String) -> (Int, Bool)? {
        if let day = DateExpressionParser.weekdayNames[word] { return (day, false) }
        guard word.hasSuffix("days"), let day = DateExpressionParser.weekdayNames[String(word.dropLast())] else { return nil }
        return (day, true)
    }
}
