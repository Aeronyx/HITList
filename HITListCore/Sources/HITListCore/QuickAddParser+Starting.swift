import Foundation

// "starting" joins a repeat to its first day (brief 98, George 2026-11-11: "Have quickadd ignore the word
// 'starting'"): "every 3 days starting friday", "starting monday every weekday", "starting on nov 24",
// "starting from tomorrow". The word belongs to the date's highlight and is not a title word; with no date
// right after it ("the starting lineup", "starting salary talk fri", "game starting 5pm") it stays one.
extension QuickAddParser {
    /// A date phrase at `words[i]`, or "starting" / "starting from" before one (a date phrase already reads
    /// "on friday"). `isStart` says the words began with "starting": the date is the repeat's first day,
    /// so a rule that does not fall on it starts at its first occurrence on or after it.
    func matchDateOrStart(_ words: [String], at i: Int) -> (date: ParsedDate, consumed: Int, isStart: Bool)? {
        if let (date, n) = dateParser.matchDate(in: words, at: i) { return (date, n, false) }
        guard DateExpressionParser.normalize(words[i]) == "starting" else { return nil }
        var j = i + 1
        if j < words.count, DateExpressionParser.normalize(words[j]) == "from" { j += 1 }
        guard let (date, n) = dateParser.matchDate(in: words, at: j) else { return nil }
        return (date, j - i + n, true)
    }
}
