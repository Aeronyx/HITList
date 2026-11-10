import Foundation

// Repeats on a fixed place in the month or year (brief 71, George 2026-11-10: "every month on the 28th"
// and related phrases). Each phrase is one highlight over all its words, as "tom 4" is.
//
//   every month on the 28th · monthly on the 28th · every 28th · every month on 28 · every 1st
//   on the 28th of every month · the 28th of each month
//   every other month on the 15th · every 3 months on the 10th · quarterly · every quarter
//   every last day of the month · every month on the last day · end of every month · every first day of the month
//   every first Monday (of the month) · every last Friday · every 2nd Tuesday · every month on the third Wednesday
//   every year on Mar 3 · every March 3 · yearly on March 3rd · annually on 3 March · every 2 years on 3 Mar
extension QuickAddParser {
    /// A repeat with a place (`RecurrenceRule.Place`) starting at `words[i]`, or "quarterly" / "every quarter";
    /// nil leaves the words to the plain repeat grammar (`matchRecurrence`), which reads "every month" alone.
    static func matchPlacedRepeat(_ words: [String], at i: Int) -> (RecurrenceRule, Int)? {
        let reader = PhraseReader(words: words)
        if let head = reader.head(at: i) {
            let j = i + head.consumed
            if let (place, n) = head.frequency == .monthly ? reader.monthPlace(at: j, after: .on)
                                                            : reader.yearPlace(at: j, after: .on),
               let rule = RecurrenceRule(head.frequency, interval: head.interval, place: place) {
                return (rule, head.consumed + n)
            }
            // "quarterly" has no plain form to fall back on.
            if head.isQuarter { return (RecurrenceRule(frequency: .monthly, interval: 3), head.consumed) }
            return nil
        }
        switch reader[i] {
        case "every":
            // "every March 3", "every 3 March"
            if let (place, n) = reader.yearPlace(at: i + 1, after: .nothing),
               let rule = RecurrenceRule(.yearly, place: place) { return (rule, 1 + n) }
            // "every 28th", "every first Monday of the month", "every last day of the month"
            if let (place, n) = reader.monthPlace(at: i + 1, after: .nothing, ordinalOnly: true),
               let rule = RecurrenceRule(.monthly, place: place) {
                return (rule, 1 + n + reader.ofTheMonth(at: i + 1 + n, every: false))
            }
            return nil
        case "on", "the", "end":
            // "on the 28th of every month", "the 28th of each month", "end of every month",
            // "the last day of every month", "the first Monday of each month"
            var j = i
            if reader[j] == "on" { j += 1 }
            if reader[j] == "the" { j += 1 }
            let place: RecurrenceRule.Place, n: Int
            if reader[j] == "end" {
                (place, n) = (.lastDay, 1)
            } else if let found = reader.monthPlace(at: j, after: .nothing) {
                (place, n) = found
            } else {
                return nil
            }
            let of = reader.ofTheMonth(at: j + n, every: true)
            guard of > 0, let rule = RecurrenceRule(.monthly, place: place) else { return nil }
            return (rule, j + n + of - i)
        default:
            return nil
        }
    }
}

/// Reads the words of a placed repeat (`QuickAddParser.matchPlacedRepeat`); every word is normalised
/// (lowercased, trailing ",.;" dropped) and out-of-range reads are nil.
private struct PhraseReader {
    let words: [String]

    subscript(_ k: Int) -> String? { k >= 0 && k < words.count ? DateExpressionParser.normalize(words[k]) : nil }

    struct Head {
        var frequency: RecurrenceRule.Frequency
        var interval: Int
        var consumed: Int
        var isQuarter = false
    }

    /// "monthly", "every month", "every other month", "every 3 months", "quarterly", "every quarter";
    /// "yearly", "annually", "every year", "every other year", "every 2 years".
    func head(at i: Int) -> Head? {
        switch self[i] {
        case "monthly": return Head(frequency: .monthly, interval: 1, consumed: 1)
        case "quarterly": return Head(frequency: .monthly, interval: 3, consumed: 1, isQuarter: true)
        case "yearly", "annually": return Head(frequency: .yearly, interval: 1, consumed: 1)
        case "every": break
        default: return nil
        }
        switch self[i + 1] {
        case "month": return Head(frequency: .monthly, interval: 1, consumed: 2)
        case "quarter": return Head(frequency: .monthly, interval: 3, consumed: 2, isQuarter: true)
        case "year": return Head(frequency: .yearly, interval: 1, consumed: 2)
        case "other":
            switch self[i + 2] {
            case "month": return Head(frequency: .monthly, interval: 2, consumed: 3)
            case "year": return Head(frequency: .yearly, interval: 2, consumed: 3)
            default: return nil
            }
        default:
            guard let n = self[i + 1].flatMap({ Int($0) }), (1...RecurrenceRule.maxInterval).contains(n),
                  let unit = self[i + 2].flatMap({ DateExpressionParser.unitDays($0) }) else { return nil }
            switch unit.component {
            case .month: return Head(frequency: .monthly, interval: n, consumed: 3)
            case .year: return Head(frequency: .yearly, interval: n, consumed: 3)
            default: return nil
            }
        }
    }

    enum Lead { case on, nothing }

    /// A place in the month: "the 28th", "28", "the last day", "the first day", "the first Monday", "the 2nd
    /// Tuesday", "the last Friday"; after "on" when `lead` is `.on`. `ordinalOnly` ("every 28th") refuses a
    /// bare number ("every 28" is too close to "every 2 weeks").
    func monthPlace(at i: Int, after lead: Lead, ordinalOnly: Bool = false) -> (RecurrenceRule.Place, Int)? {
        var j = i
        if lead == .on {
            guard self[j] == "on" else { return nil }
            j += 1
        }
        if self[j] == "the", lead == .on { j += 1 }
        guard let word = self[j] else { return nil }
        let next = self[j + 1]
        // "first Monday", "2nd Tuesday", "last Friday"
        if let ordinal = Self.weekOrdinal(word), let weekday = next.flatMap({ DateExpressionParser.weekdayNames[$0] }) {
            return (.weekday(weekday, ordinal: ordinal), j + 2 - i)
        }
        // "last day", "first day"
        if next == "day", let ordinal = Self.ordinalWords[word] ?? (Self.hasOrdinalSuffix(word) ? DateExpressionParser.dayNumber(word) : nil) {
            return (ordinal == -1 ? .lastDay : .day(ordinal), j + 2 - i)
        }
        // "28th", "1st", "28"; never "5 jan" (a date), "9 am" (a time) or "3 weeks"
        guard let day = DateExpressionParser.dayNumber(word), !ordinalOnly || Self.hasOrdinalSuffix(word) else { return nil }
        if let next, DateExpressionParser.monthNames[next] != nil || DateExpressionParser.unitDays(next) != nil
            || next == "am" || next == "pm" || DateExpressionParser.weekdayNames[next] != nil { return nil }
        return (.day(day), j + 1 - i)
    }

    /// A date in the year: "Mar 3", "March 3rd", "3 March", "the 3rd of March"; after "on" when `lead` is `.on`.
    func yearPlace(at i: Int, after lead: Lead) -> (RecurrenceRule.Place, Int)? {
        var j = i
        if lead == .on {
            guard self[j] == "on" else { return nil }
            j += 1
        }
        if self[j] == "the" { j += 1 }
        guard let first = self[j], let second = self[j + 1] else { return nil }
        if let month = DateExpressionParser.monthNames[first], let day = DateExpressionParser.dayNumber(second) {
            return (.date(month: month, day: day), j + 2 - i)
        }
        if let day = DateExpressionParser.dayNumber(first) {
            if let month = DateExpressionParser.monthNames[second] { return (.date(month: month, day: day), j + 2 - i) }
            if second == "of", let month = self[j + 2].flatMap({ DateExpressionParser.monthNames[$0] }) {
                return (.date(month: month, day: day), j + 3 - i)
            }
        }
        return nil
    }

    /// "of the month", "of every month", "of each month" at `i`: the words it takes, or 0. `every` requires
    /// "every" or "each" (a phrase with no "every" before it is a repeat only through them).
    func ofTheMonth(at i: Int, every: Bool) -> Int {
        guard self[i] == "of", self[i + 2] == "month", let which = self[i + 1] else { return 0 }
        switch which {
        case "every", "each": return 3
        case "the": return every ? 0 : 3
        default: return 0
        }
    }

    static let ordinalWords: [String: Int] = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "last": -1]

    /// "first" … "fifth", "1st" … "5th", "last" (-1): which of a weekday's days in the month.
    static func weekOrdinal(_ word: String) -> Int? {
        if let n = ordinalWords[word] { return n }
        guard hasOrdinalSuffix(word), let n = DateExpressionParser.dayNumber(word), (1...5).contains(n) else { return nil }
        return n
    }

    /// "1st", "22nd", "28th": a number written as an ordinal.
    static func hasOrdinalSuffix(_ word: String) -> Bool {
        ["st", "nd", "rd", "th"].contains { word.hasSuffix($0) } && Int(word.dropLast(2)) != nil
    }
}

private extension RecurrenceRule {
    /// A rule with a place, or nil when the place cannot be (Feb 30, a sixth Monday).
    init?(_ frequency: Frequency, interval: Int = 1, place: Place) {
        self.init(frequency: frequency, interval: interval, place: place)
        guard self.place == place else { return nil }
    }
}
