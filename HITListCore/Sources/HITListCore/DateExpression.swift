import Foundation

/// A date produced by parsing natural language. `date` is start-of-day unless `hasTime`.
public struct ParsedDate: Equatable, Sendable {
    public var date: Date
    public var hasTime: Bool
    public init(date: Date, hasTime: Bool) {
        self.date = date
        self.hasTime = hasTime
    }
}

/// Half-open interval `[start, end)`.
public struct DateSpan: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
    public func contains(_ date: Date) -> Bool { date >= start && date < end }
}

/// Parses natural-language date and time phrases relative to a fixed `now`.
///
/// Shared by Quick Add (scanning free text) and the filter language (`due: next mon`).
public struct DateExpressionParser: Sendable {
    public var calendar: Calendar
    public var now: Date
    /// Calendar weekday that starts a week for "next week" / "this week". 2 = Monday.
    public var weekStart: Int

    public init(calendar: Calendar = .current, now: Date = Date(), weekStart: Int = 2) {
        self.calendar = calendar
        self.now = now
        self.weekStart = weekStart
    }

    // MARK: - Calendar helpers

    public var today: Date { calendar.startOfDay(for: now) }

    public func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    public func day(_ offset: Int, from base: Date? = nil) -> Date {
        calendar.date(byAdding: .day, value: offset, to: startOfDay(base ?? today))!
    }

    public func startOfWeek(containing date: Date) -> Date {
        let d = startOfDay(date)
        let wd = calendar.component(.weekday, from: d)
        let diff = (wd - weekStart + 7) % 7
        return day(-diff, from: d)
    }

    /// Next date with the given calendar weekday (1 = Sunday ... 7 = Saturday).
    public func nextWeekday(_ weekday: Int, after date: Date, inclusive: Bool) -> Date {
        let d = startOfDay(date)
        let wd = calendar.component(.weekday, from: d)
        var diff = (weekday - wd + 7) % 7
        if diff == 0 && !inclusive { diff = 7 }
        return day(diff, from: d)
    }

    public func lastDayOfMonth(containing date: Date) -> Date {
        let range = calendar.range(of: .day, in: .month, for: date)!
        var comps = calendar.dateComponents([.year, .month], from: date)
        comps.day = range.count
        return startOfDay(calendar.date(from: comps)!)
    }

    public func firstDayOfNextMonth(after date: Date) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: date)
        comps.day = 1
        let first = calendar.date(from: comps)!
        return startOfDay(calendar.date(byAdding: .month, value: 1, to: first)!)
    }

    public func date(_ base: Date, hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: startOfDay(base))!
    }

    // MARK: - Spans for filters

    public func span(forDay date: Date) -> DateSpan {
        let s = startOfDay(date)
        return DateSpan(start: s, end: day(1, from: s))
    }

    /// Today plus the following `n` days.
    public func spanNextDays(_ n: Int) -> DateSpan {
        DateSpan(start: today, end: day(n + 1))
    }

    public func spanThisWeek() -> DateSpan {
        let s = startOfWeek(containing: today)
        return DateSpan(start: s, end: day(7, from: s))
    }

    public func spanNextWeek() -> DateSpan {
        let s = day(7, from: startOfWeek(containing: today))
        return DateSpan(start: s, end: day(7, from: s))
    }

    public func spanThisMonth() -> DateSpan {
        var comps = calendar.dateComponents([.year, .month], from: today)
        comps.day = 1
        let s = startOfDay(calendar.date(from: comps)!)
        return DateSpan(start: s, end: firstDayOfNextMonth(after: s))
    }

    public func spanNextMonth() -> DateSpan {
        let s = firstDayOfNextMonth(after: today)
        return DateSpan(start: s, end: firstDayOfNextMonth(after: s))
    }

    /// The upcoming (or current, if today is Sat/Sun) Saturday and Sunday.
    public func spanWeekend() -> DateSpan {
        let wd = calendar.component(.weekday, from: today)
        let saturday: Date
        if wd == 1 { // Sunday: weekend started yesterday
            saturday = day(-1)
        } else {
            saturday = nextWeekday(7, after: today, inclusive: true)
        }
        return DateSpan(start: saturday, end: day(2, from: saturday))
    }

    /// The weekend after `spanWeekend()`.
    public func spanNextWeekend() -> DateSpan {
        let s = day(7, from: spanWeekend().start)
        return DateSpan(start: s, end: day(2, from: s))
    }

    /// The past `n` days plus today.
    public func spanLastDays(_ n: Int) -> DateSpan {
        DateSpan(start: day(-n), end: day(1))
    }

    /// The whole of the named month (1...12): this year's if it hasn't ended yet, otherwise next year's.
    public func spanMonth(_ month: Int) -> DateSpan {
        var year = calendar.component(.year, from: today)
        if month < calendar.component(.month, from: today) { year += 1 }
        let s = startOfDay(makeDate(year: year, month: month, day: 1)!)
        return DateSpan(start: s, end: firstDayOfNextMonth(after: s))
    }

    // MARK: - Vocabulary

    static let weekdayNames: [String: Int] = [
        "sun": 1, "sunday": 1,
        "mon": 2, "monday": 2,
        "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "weds": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6,
        "sat": 7, "saturday": 7,
    ]

    static let monthNames: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
        "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
        "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    public static func weekday(named word: String) -> Int? { weekdayNames[normalize(word)] }

    static func normalize(_ word: String) -> String {
        var w = word.lowercased()
        while let last = w.last, ",.;".contains(last) { w.removeLast() }
        return w
    }

    /// Parses "5", "5th", "22nd" → 5, 22.
    static func dayNumber(_ word: String) -> Int? {
        let w = normalize(word)
        if let n = Int(w) { return (1...31).contains(n) ? n : nil }
        for suffix in ["st", "nd", "rd", "th"] where w.hasSuffix(suffix) {
            if let n = Int(w.dropLast(2)), (1...31).contains(n) { return n }
        }
        return nil
    }

    /// How far "in N days" / "N weeks" may reach: beyond this the words stay in the title (Calendar
    /// turned "in 99999999999 days" into a date no formatter can print).
    static let relativeCounts = -9999...9999

    static func unitDays(_ word: String) -> (component: Calendar.Component, multiplier: Int)? {
        switch normalize(word) {
        case "day", "days", "d": return (.day, 1)
        case "week", "weeks", "wk", "wks", "w": return (.weekOfYear, 1)
        case "month", "months", "mo", "mos": return (.month, 1)
        case "year", "years", "yr", "yrs", "y": return (.year, 1)
        default: return nil
        }
    }

    // MARK: - Scanning

    /// Attempts to match a date phrase beginning at `words[i]`. Returns the date and the
    /// number of words consumed. Words should already be lowercased.
    public func matchDate(in words: [String], at i: Int) -> (ParsedDate, Int)? {
        guard i < words.count else { return nil }
        let w = Self.normalize(words[i])
        let next: String? = i + 1 < words.count ? Self.normalize(words[i + 1]) : nil
        let next2: String? = i + 2 < words.count ? Self.normalize(words[i + 2]) : nil

        func d(_ date: Date) -> ParsedDate { ParsedDate(date: startOfDay(date), hasTime: false) }

        switch w {
        case "today", "tod":
            return (d(today), 1)
        case "tomorrow", "tom", "tmr", "tmrw":
            return (d(day(1)), 1)
        case "yesterday":
            return (d(day(-1)), 1)
        case "eom":
            return (d(lastDayOfMonth(containing: today)), 1)
        case "on":
            if let (pd, n) = matchDate(in: words, at: i + 1) { return (pd, n + 1) }
            return nil
        case "next":
            guard let n = next else { return nil }
            if n == "week" { return (d(day(7, from: startOfWeek(containing: today))), 2) }
            if n == "month" { return (d(firstDayOfNextMonth(after: today)), 2) }
            if n == "year" {
                var comps = calendar.dateComponents([.year], from: today)
                comps.year! += 1; comps.month = 1; comps.day = 1
                return (d(calendar.date(from: comps)!), 2)
            }
            if let wd = Self.weekdayNames[n] {
                // The occurrence of that weekday in next week.
                let nextWeekStart = day(7, from: startOfWeek(containing: today))
                return (d(nextWeekday(wd, after: nextWeekStart, inclusive: true)), 2)
            }
            return nil
        case "this":
            guard let n = next else { return nil }
            if let wd = Self.weekdayNames[n] {
                let weekStartDate = startOfWeek(containing: today)
                return (d(nextWeekday(wd, after: weekStartDate, inclusive: true)), 2)
            }
            if n == "weekend" { return (d(spanWeekend().start), 2) }
            return nil
        case "end":
            if next == "of", let n2 = next2 {
                if n2 == "month" { return (d(lastDayOfMonth(containing: today)), 3) }
                if n2 == "week" { return (d(day(6, from: startOfWeek(containing: today))), 3) }
                if n2 == "year" {
                    var comps = calendar.dateComponents([.year], from: today)
                    comps.month = 12; comps.day = 31
                    return (d(calendar.date(from: comps)!), 3)
                }
            }
            return nil
        case "in":
            guard let n = next, let n2 = next2 else { return nil }
            let count: Int? = (n == "a" || n == "an" || n == "one") ? 1 : Int(n)
            if let count, Self.relativeCounts.contains(count), let unit = Self.unitDays(n2) {
                return (d(calendar.date(byAdding: unit.component, value: count, to: today)!), 3)
            }
            return nil
        case "weekend":
            return (d(spanWeekend().start), 1)
        default:
            break
        }

        if let wd = Self.weekdayNames[w] {
            return (d(nextWeekday(wd, after: today, inclusive: false)), 1)
        }

        // "3 days", "2 weeks"
        if let count = Int(w), let n = next, let unit = Self.unitDays(n), count > 0, Self.relativeCounts.contains(count) {
            return (d(calendar.date(byAdding: unit.component, value: count, to: today)!), 2)
        }

        // "jan 5", "january 5th", "jan 5 2027"
        if let month = Self.monthNames[w], let n = next, let dayNum = Self.dayNumber(n) {
            if let n2 = next2, let year = Int(n2), year >= 1900 {
                if let date = makeDate(year: year, month: month, day: dayNum) { return (d(date), 3) }
            }
            if let date = upcomingDate(month: month, day: dayNum) { return (d(date), 2) }
            return nil
        }

        // "5 jan", "5th january", "5 jan 2027"
        if let dayNum = Self.dayNumber(w), let n = next, let month = Self.monthNames[n] {
            if let n2 = next2, let year = Int(n2), year >= 1900 {
                if let date = makeDate(year: year, month: month, day: dayNum) { return (d(date), 3) }
            }
            if let date = upcomingDate(month: month, day: dayNum) { return (d(date), 2) }
            return nil
        }

        // ISO 2026-01-05
        if let date = parseISO(w) { return (d(date), 1) }
        // 1/5, 1/5/2026, 1/5/26
        if let date = parseSlash(w) { return (d(date), 1) }

        return nil
    }

    /// Attempts to match a time phrase at `words[i]`. Returns hour, minute, and words consumed.
    public func matchTime(in words: [String], at i: Int) -> (hour: Int, minute: Int, consumed: Int)? {
        guard i < words.count else { return nil }
        let w = Self.normalize(words[i])
        let next: String? = i + 1 < words.count ? Self.normalize(words[i + 1]) : nil

        switch w {
        case "noon": return (12, 0, 1)
        case "midnight": return (0, 0, 1)
        case "at":
            guard let n = next else { return nil }
            if let t = Self.parseClock(n, allowBareHour: true) {
                // "at 5 pm"
                if let n2 = (i + 2 < words.count ? Self.normalize(words[i + 2]) : nil), n2 == "am" || n2 == "pm" {
                    if let t2 = Self.parseClock(n + n2, allowBareHour: true) { return (t2.hour, t2.minute, 3) }
                }
                return (t.hour, t.minute, 2)
            }
            if n == "noon" { return (12, 0, 2) }
            if n == "midnight" { return (0, 0, 2) }
            return nil
        default:
            break
        }

        // "5 pm" as two words
        if let n = next, n == "am" || n == "pm", let t = Self.parseClock(w + n, allowBareHour: true) {
            return (t.hour, t.minute, 2)
        }
        if let t = Self.parseClock(w, allowBareHour: false) {
            return (t.hour, t.minute, 1)
        }
        return nil
    }

    /// Parses "5pm", "5:30pm", "17:00", "5:30", "5p", and (if allowed) a bare "5".
    static func parseClock(_ raw: String, allowBareHour: Bool) -> (hour: Int, minute: Int)? {
        var s = normalize(raw)
        var meridiem: String? = nil
        for suffix in ["am", "pm", "a", "p"] where s.hasSuffix(suffix) {
            meridiem = String(suffix.prefix(1))
            s = String(s.dropLast(suffix.count))
            break
        }
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        var hour: Int
        var minute = 0
        if let colon = s.firstIndex(of: ":") {
            guard let h = Int(s[..<colon]), let m = Int(s[s.index(after: colon)...]) else { return nil }
            guard s[s.index(after: colon)...].count == 2 else { return nil }
            hour = h; minute = m
        } else {
            guard let h = Int(s), s.count <= 2 else { return nil }
            if meridiem == nil && !allowBareHour { return nil }
            hour = h
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if let m = meridiem {
            guard (1...12).contains(hour) else { return nil }
            if m == "a" { hour = hour == 12 ? 0 : hour }
            else { hour = hour == 12 ? 12 : hour + 12 }
        } else if allowBareHour && s.firstIndex(of: ":") == nil {
            // "at 5" → 5 PM; "at 9" → 9 AM.
            if (1...6).contains(hour) { hour += 12 }
        }
        return (hour, minute)
    }

    func makeDate(year: Int, month: Int, day: Int) -> Date? {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        guard let date = calendar.date(from: comps) else { return nil }
        // Reject invalid dates such as Feb 30 which Calendar would roll over.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.month == month, check.day == day else { return nil }
        return date
    }

    /// The next occurrence of month/day on or after today.
    func upcomingDate(month: Int, day: Int) -> Date? {
        let year = calendar.component(.year, from: today)
        if let date = makeDate(year: year, month: month, day: day), date >= today { return date }
        return makeDate(year: year + 1, month: month, day: day)
    }

    func parseISO(_ w: String) -> Date? {
        let parts = w.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return makeDate(year: y, month: m, day: d)
    }

    func parseSlash(_ w: String) -> Date? {
        let parts = w.split(separator: "/")
        guard parts.count == 2 || parts.count == 3,
              let m = Int(parts[0]), let d = Int(parts[1]) else { return nil }
        if parts.count == 3 {
            guard var y = Int(parts[2]) else { return nil }
            if y < 100 { y += 2000 }
            return makeDate(year: y, month: m, day: d)
        }
        return upcomingDate(month: m, day: d)
    }

    // MARK: - Whole-phrase parsing

    /// Parses a complete phrase such as "next mon", "jan 5 at 3pm", "2026-01-05".
    /// Returns nil unless every word is consumed by a date or time match.
    public func parse(_ phrase: String) -> ParsedDate? {
        let words = phrase.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() }
        guard !words.isEmpty else { return nil }
        var i = 0
        var date: Date? = nil
        var time: (Int, Int)? = nil
        while i < words.count {
            if date == nil, let (pd, n) = matchDate(in: words, at: i) {
                date = pd.date; i += n; continue
            }
            if time == nil, let t = matchTime(in: words, at: i) {
                time = (t.hour, t.minute); i += t.consumed; continue
            }
            return nil
        }
        if let date {
            if let time { return ParsedDate(date: self.date(date, hour: time.0, minute: time.1), hasTime: true) }
            return ParsedDate(date: date, hasTime: false)
        }
        if let time {
            var base = today
            var candidate = self.date(base, hour: time.0, minute: time.1)
            if candidate < now { base = day(1); candidate = self.date(base, hour: time.0, minute: time.1) }
            return ParsedDate(date: candidate, hasTime: true)
        }
        return nil
    }
}
