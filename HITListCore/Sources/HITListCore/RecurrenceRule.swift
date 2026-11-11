import Foundation

/// A deliberately small recurrence model: every N days/weeks/months/years,
/// optionally restricted to specific weekdays (weekly only).
///
/// Monthly and yearly rules may carry an anchor day: the day of the month the task started on, so "every
/// month" from Jan 31 goes Feb 28, Mar 31, Apr 30 instead of drifting to the 28th, and "every year" from
/// Feb 29 comes back to Feb 29 in the next leap year (George, 2026-11-02). A timed task's rule carries its
/// wall-clock time too, so a repeat at 2:30 that the spring change pushed to 3:00 comes back to 2:30 the
/// next day (George, 2026-11-03). Equality ignores both: they follow the task's due date, not the repeat.
///
/// A monthly or yearly rule may also have a place typed in quick add (brief 71): "every month on the
/// 28th", "every last day of the month", "every first Monday", "every year on Mar 3". A place belongs to
/// the repeat, as "every monday" keeps Monday: a task moved off it comes back to it at the next
/// occurrence. Equality includes it.
public struct RecurrenceRule: Codable, Hashable, Sendable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency
    public var interval: Int
    /// Calendar weekdays (1 = Sunday ... 7 = Saturday). Only meaningful for `.weekly`.
    public var weekdays: Set<Int>?
    /// The day of the month (1...31) a monthly or yearly repeat keeps returning to; nil for daily and
    /// weekly rules, and for rules written before 0.4.0 (they behave as they always did until a
    /// completion anchors them: see `anchored(to:calendar:)`).
    public var anchorDay: Int?
    /// The wall-clock time each occurrence is rebuilt at; nil for all-day tasks and rules written before
    /// 0.4.1 (they step the stored due date, as they always did, until a completion times them).
    public var time: TimeOfDay?

    public struct TimeOfDay: Codable, Hashable, Sendable {
        public var hour: Int
        public var minute: Int
        public init(hour: Int, minute: Int) {
            self.hour = hour
            self.minute = minute
        }
        var isValid: Bool { (0...23).contains(hour) && (0...59).contains(minute) }
    }

    /// Where in the month or year a monthly or yearly repeat falls (brief 71); nil for every other rule and
    /// for "every month" / "every year" alone, which follow the due date's day (`anchorDay`).
    public var place: Place?

    public enum Place: Hashable, Codable, Sendable {
        /// Monthly on this day (1...31); a shorter month's last day stands in for the 29th to 31st.
        case day(Int)
        /// Monthly on each month's own last day.
        case lastDay
        /// Monthly on a weekday (1 = Sunday ... 7 = Saturday): the first to fifth (1...5) or the last (-1)
        /// of its days in the month. A month without a fifth one is skipped.
        case weekday(Int, ordinal: Int)
        /// Yearly on this date; Feb 29 is Feb 28 in other years.
        case date(month: Int, day: Int)

        /// The longest each month can be, Feb 29 allowed.
        static let monthLengths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

        func fits(_ frequency: Frequency) -> Bool {
            switch self {
            case .day(let day): return frequency == .monthly && (1...31).contains(day)
            case .lastDay: return frequency == .monthly
            case .weekday(let weekday, let ordinal):
                return frequency == .monthly && (1...7).contains(weekday) && ((1...5).contains(ordinal) || ordinal == -1)
            case .date(let month, let day):
                return frequency == .yearly && (1...12).contains(month) && (1...Self.monthLengths[month - 1]).contains(day)
            }
        }

        /// The anchor day a build that knows no places reads (`encoded`), so to it "every month on the
        /// 28th", "every last day of the month" and "every year on Mar 3" repeat as typed; a weekday in
        /// the month has no day of its own and repeats there on the due date's day.
        var anchorDay: Int? {
            switch self {
            case .day(let day): return day
            case .lastDay: return 31
            case .weekday: return nil
            case .date(_, let day): return day
            }
        }

        /// The sixth part of `encoded`: "d28", "dlast", "w2#1" (first Monday), "w6#-1" (last Friday), "m3d3".
        var code: String {
            switch self {
            case .day(let day): return "d\(day)"
            case .lastDay: return "dlast"
            case .weekday(let weekday, let ordinal): return "w\(weekday)#\(ordinal)"
            case .date(let month, let day): return "m\(month)d\(day)"
            }
        }

        init?(code: String) {
            if code == "dlast" { self = .lastDay; return }
            if code.hasPrefix("d"), let day = Int(code.dropFirst()) { self = .day(day); return }
            if code.hasPrefix("w") {
                let parts = code.dropFirst().split(separator: "#", omittingEmptySubsequences: false)
                guard parts.count == 2, let weekday = Int(parts[0]), let ordinal = Int(parts[1]) else { return nil }
                self = .weekday(weekday, ordinal: ordinal); return
            }
            if code.hasPrefix("m"), let d = code.firstIndex(of: "d"),
               let month = Int(code[code.index(after: code.startIndex)..<d]), let day = Int(code[code.index(after: d)...]) {
                self = .date(month: month, day: day); return
            }
            return nil
        }
    }

    public init(frequency: Frequency, interval: Int = 1, weekdays: Set<Int>? = nil, anchorDay: Int? = nil,
                place: Place? = nil) {
        self.frequency = frequency
        self.interval = min(max(1, interval), Self.maxInterval)
        self.weekdays = weekdays?.isEmpty == true ? nil : weekdays
        self.place = place.flatMap { $0.fits(frequency) ? $0 : nil }
        if let place = self.place {
            self.anchorDay = place.anchorDay
        } else {
            self.anchorDay = Self.usesAnchor(frequency) ? anchorDay.flatMap { (1...31).contains($0) ? $0 : nil } : nil
        }
    }

    private static func usesAnchor(_ frequency: Frequency) -> Bool { frequency == .monthly || frequency == .yearly }

    public static func == (a: RecurrenceRule, b: RecurrenceRule) -> Bool {
        a.frequency == b.frequency && a.interval == b.interval && a.weekdays == b.weekdays && a.place == b.place
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(frequency)
        hasher.combine(interval)
        hasher.combine(weekdays)
        hasher.combine(place)
    }

    /// The longest interval a rule holds: the date arithmetic (7 × interval for weeks, the weekday walk)
    /// trapped on absurd values typed into quick add or arriving from another device.
    public static let maxInterval = 999

    public static let daily = RecurrenceRule(frequency: .daily)
    public static let weekly = RecurrenceRule(frequency: .weekly)
    public static let monthly = RecurrenceRule(frequency: .monthly)
    public static let yearly = RecurrenceRule(frequency: .yearly)
    public static let weekdays = RecurrenceRule(frequency: .weekly, weekdays: [2, 3, 4, 5, 6])

    // MARK: Storage as a compact string ("weekly;2;2,4") so SwiftData/CloudKit can hold it.
    //
    // A fourth part holds the anchor day: "monthly;1;;31". Builds before 0.4.0 read only the first three
    // parts and see an empty weekday list, so to them it is plain "every month" (no schema change).
    // A fifth holds the time: "daily;1;;;02:30", "monthly;1;;31;09:00". Builds up to 0.4.0 (13) read four
    // parts at most, so to them it is the rule without its time.
    // A sixth holds the place (brief 71): "monthly;1;;28;;d28", "monthly;1;;31;09:00;dlast",
    // "monthly;1;;;;w2#1", "yearly;1;;3;;m3d3". Builds up to 0.9.0 (20) read five parts at most, so to them
    // it is the rule with its anchor day: right for a day, the last day and a date in the year, and plain
    // "every month" from the due date for a weekday in the month. A place this build does not know is
    // dropped the same way.

    public var encoded: String {
        var parts = ["\(frequency.rawValue)", "\(interval)"]
        parts.append(weekdays.map { $0.sorted().map(String.init).joined(separator: ",") } ?? "")
        parts.append(anchorDay.map(String.init) ?? "")
        parts.append(time.map { String(format: "%02d:%02d", $0.hour, $0.minute) } ?? "")
        parts.append(place?.code ?? "")
        while parts.count > 2, parts.last == "" { parts.removeLast() }
        return parts.joined(separator: ";")
    }

    public init?(encoded: String) {
        let parts = encoded.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let freq = Frequency(rawValue: parts[0]), let interval = Int(parts[1]) else { return nil }
        var weekdays: Set<Int>? = nil
        if parts.count >= 3, !parts[2].isEmpty {
            weekdays = Set(parts[2].split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
        }
        let anchorDay = parts.count >= 4 ? Int(parts[3]) : nil
        let place = parts.count >= 6 ? Place(code: parts[5]) : nil
        self.init(frequency: freq, interval: interval, weekdays: weekdays, anchorDay: anchorDay, place: place)
        if parts.count >= 5 {
            let clock = parts[4].split(separator: ":", omittingEmptySubsequences: false)
            if clock.count == 2, clock.allSatisfy({ $0.count == 2 }), let h = Int(clock[0]), let m = Int(clock[1]) {
                self = withTime(hour: h, minute: m)
            }
        }
    }

    // MARK: Time of day

    /// This rule rebuilding each occurrence at `hour:minute`; an impossible time leaves it untimed.
    public func withTime(hour: Int, minute: Int) -> RecurrenceRule {
        var rule = self
        let time = TimeOfDay(hour: hour, minute: minute)
        rule.time = time.isValid ? time : nil
        return rule
    }

    public var withoutTime: RecurrenceRule {
        var rule = self
        rule.time = nil
        return rule
    }

    /// This rule for a task due at `due`: timed to its wall-clock time when it has one, untimed otherwise.
    /// Call it whenever the task's time changes (quick add, the Repeat menu, the editor's time).
    public func timed(to due: Date?, hasTime: Bool, calendar: Calendar = .current) -> RecurrenceRule {
        guard hasTime, let due else { return withoutTime }
        let parts = calendar.dateComponents([.hour, .minute], from: due)
        return withTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    // MARK: Anchor day

    /// The day of the month a monthly or yearly step from `date` aims for: the anchor while `date` is on
    /// it (or on a shorter month's last day short of it), otherwise `date`'s own day. A task moved from
    /// the 31st to the 15th therefore repeats on the 15th; a rule without an anchor clamps and drifts as
    /// it always did.
    func targetDay(from date: Date, calendar: Calendar) -> Int {
        let day = calendar.component(.day, from: date)
        guard let anchorDay else { return day }
        if day == anchorDay { return anchorDay }
        let monthLength = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        return day == monthLength && anchorDay > day ? anchorDay : day
    }

    /// This rule anchored to a task due at `due`: monthly and yearly rules take the day it keeps returning
    /// to (an existing anchor `due` still matches is kept); daily and weekly rules, and rules with a place,
    /// are returned as they are.
    public func anchored(to due: Date, calendar: Calendar = .current) -> RecurrenceRule {
        guard Self.usesAnchor(frequency), place == nil else { return self }
        var rule = self
        rule.anchorDay = targetDay(from: due, calendar: calendar)
        return rule
    }

    /// This rule picked from the Repeat menu for a task whose repeat was `previous` and which is due at
    /// `due`. Menu rules carry no anchor and compare equal to anchored ones, so picking "Every month" again
    /// on a "31st" task due Feb 28 must not forget the 31st: a monthly or yearly rule keeps the day
    /// `previous` returned to (same frequency) while `due` still matches it, and otherwise takes `due`'s
    /// day, as a completion would. A rule that already has an anchor, or has no use for one, is returned
    /// as it is; so is any rule for an undated task.
    public func keepingAnchor(of previous: RecurrenceRule?, due: Date?, calendar: Calendar = .current) -> RecurrenceRule {
        guard Self.usesAnchor(frequency), anchorDay == nil, place == nil, let due else { return self }
        var rule = self
        if let previous, previous.frequency == frequency { rule.anchorDay = previous.anchorDay }
        return rule.anchored(to: due, calendar: calendar)
    }

    // MARK: Occurrence math

    /// The first occurrence strictly after `date`: at the rule's time when it has one (rebuilt on the
    /// day, so a time the clock skipped one night is back the next), else at `date`'s time of day.
    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date {
        let next = step(after: date, calendar: calendar)
        guard let time,
              let rebuilt = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0,
                                          of: calendar.startOfDay(for: next)), rebuilt > date else { return next }
        return rebuilt
    }

    private func step(after date: Date, calendar: Calendar) -> Date {
        if let place { return occurrence(of: place, after: date, inclusive: false, stride: interval, calendar: calendar) }
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date)!
        case .monthly, .yearly:
            // Calendar clamps to the end of a shorter month (Jan 31 + 1 month = Feb 28); then move to the
            // target day, or as close to it as the new month allows. Adding days keeps the time of day.
            let stepped = calendar.date(byAdding: frequency == .monthly ? .month : .year, value: interval, to: date)!
            let monthLength = calendar.range(of: .day, in: .month, for: stepped)?.count ?? 28
            let day = min(targetDay(from: date, calendar: calendar), monthLength)
            let shift = day - calendar.component(.day, from: stepped)
            return shift == 0 ? stepped : calendar.date(byAdding: .day, value: shift, to: stepped)!
        case .weekly:
            guard let weekdays, !weekdays.isEmpty else {
                return calendar.date(byAdding: .day, value: 7 * interval, to: date)!
            }
            // Walk forward day by day; honor `interval` by only accepting weeks that are a
            // multiple of `interval` away from the anchor week.
            let anchorWeek = startOfWeek(date, calendar: calendar)
            var candidate = date
            for _ in 0..<(7 * interval + 7) {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
                let wd = calendar.component(.weekday, from: candidate)
                guard weekdays.contains(wd) else { continue }
                let week = startOfWeek(candidate, calendar: calendar)
                let weeksApart = calendar.dateComponents([.weekOfYear], from: anchorWeek, to: week).weekOfYear ?? 0
                if weeksApart % interval == 0 { return candidate }
            }
            return calendar.date(byAdding: .day, value: 7 * interval, to: date)!
        }
    }

    /// The due date to assign when a task due at `due` is completed at `now`:
    /// the next occurrence after `due` that is not already in the past (by day).
    public func nextDueDate(from due: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        var next = nextOccurrence(after: due, calendar: calendar)
        var guardCount = 0
        while calendar.startOfDay(for: next) < today && guardCount < 1000 {
            next = nextOccurrence(after: next, calendar: calendar)
            guardCount += 1
        }
        return next
    }

    /// The first day on the rule's place strictly after `date`'s day (or on it, when `inclusive`), at
    /// `date`'s time of day. Months (years) are counted from `date`'s own in steps of `stride`, as a
    /// weekly rule counts weeks; one with no such day (no fifth Monday) is skipped.
    private func occurrence(of place: Place, after date: Date, inclusive: Bool, stride: Int, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let unit: Calendar.Component = frequency == .yearly ? .year : .month
        var start = calendar.dateComponents([.year, .month], from: date)
        start.day = 1
        if frequency == .yearly { start.month = 1 }
        if let first = calendar.date(from: start) {
            for k in 0..<64 {
                guard let period = calendar.date(byAdding: unit, value: k * stride, to: first),
                      let candidate = Self.day(of: place, in: period, calendar: calendar) else { continue }
                guard candidate > day || (inclusive && candidate == day) else { continue }
                let clock = calendar.dateComponents([.hour, .minute, .second], from: date)
                return calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: clock.second ?? 0,
                                     of: candidate) ?? candidate
            }
        }
        return calendar.date(byAdding: unit, value: interval, to: date)!
    }

    /// The start of the day `place` names in the month of `period` (the year of `period` for a date), or
    /// nil when that month has none.
    static func day(of place: Place, in period: Date, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month], from: period)
        if case .date(let month, _) = place { parts.month = month }
        parts.day = 1
        guard let first = calendar.date(from: parts),
              let length = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
        switch place {
        case .day(let day), .date(_, let day):
            parts.day = min(day, length)
        case .lastDay:
            parts.day = length
        case .weekday(let weekday, let ordinal):
            var day = 1 + (weekday - calendar.component(.weekday, from: first) + 7) % 7
            if ordinal > 0 {
                day += 7 * (ordinal - 1)
                guard day <= length else { return nil }
            } else {
                while day + 7 <= length { day += 7 }
            }
            parts.day = day
        }
        return calendar.date(from: parts).map { calendar.startOfDay(for: $0) }
    }

    /// The first occurrence on or after `date` (used to pick a start date for "every monday", "every 28th").
    /// A rule with a place starts on the soonest day on it whatever its interval ("every 3 months on the
    /// 10th" typed on Oct 21 starts Nov 10); the interval counts from there.
    public func firstOccurrence(onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        if let place { return occurrence(of: place, after: date, inclusive: true, stride: 1, calendar: calendar) }
        guard frequency == .weekly, let weekdays, !weekdays.isEmpty else { return date }
        let wd = calendar.component(.weekday, from: date)
        if weekdays.contains(wd) { return date }
        return nextOccurrence(after: date, calendar: calendar)
    }

    private func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        let d = calendar.startOfDay(for: date)
        let wd = calendar.component(.weekday, from: d)
        let diff = (wd - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -diff, to: d)!
    }

    // MARK: Display

    /// The row's words for the rule, its days listed from Sunday: `displayText(weekStart:)`.
    public var displayText: String { displayText(weekStart: 1) }

    /// What a row, a chip and the Repeat menu call the rule (brief 97: every one begins "Every", as the menu's
    /// choices do): "Every day", "Every 3 days", "Every weekday", "Every Tue, Thu and Sat", "Every 2 weeks on Tue
    /// and Thu", "Every month", "Every month on the 28th", "Every month on the last day", "Every month on the second
    /// Wednesday", "Every year on Mar 3". A weekly rule's days are listed from `weekStart` (1 = Sunday ... 7 =
    /// Saturday), the first day of the week in Settings.
    public func displayText(weekStart: Int) -> String {
        if let place { return Self.words(for: place, interval: interval) }
        switch frequency {
        case .daily: return interval == 1 ? "Every day" : "Every \(interval) days"
        case .monthly: return interval == 1 ? "Every month" : "Every \(interval) months"
        case .yearly: return interval == 1 ? "Every year" : "Every \(interval) years"
        case .weekly:
            if let weekdays, !weekdays.isEmpty {
                if weekdays == [2, 3, 4, 5, 6] { return interval == 1 ? "Every weekday" : "Every \(interval) weeks on weekdays" }
                let names = RepeatWords.list(RepeatWords.ordered(weekdays, weekStart: weekStart).map { RepeatWords.shortWeekdays[$0 - 1] })
                return interval == 1 ? "Every \(names)" : "Every \(interval) weeks on \(names)"
            }
            return interval == 1 ? "Every week" : "Every \(interval) weeks"
        }
    }

    /// "Every month on the 28th", "Every month on the last day", "Every month on the first Monday", "Every year on
    /// Mar 3"; with an interval "Every 3 months on the 10th", "Every 2 years on Mar 3". (Brief 71 said "Monthly on the
    /// 28th", "Last day of the month", "First Monday of the month", "Yearly on Mar 3" until brief 97.)
    private static func words(for place: Place, interval n: Int) -> String {
        let head: String
        switch place {
        case .day, .lastDay, .weekday: head = n == 1 ? "Every month" : "Every \(n) months"
        case .date: head = n == 1 ? "Every year" : "Every \(n) years"
        }
        return head + " " + RepeatWords.on(place, shortMonth: true)
    }

    /// "1st", "2nd", "3rd", "4th", "11th", "22nd".
    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
