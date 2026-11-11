import Foundation

/// Brief 82 (round 19, 0.9.3): a date with no time names a calendar day, and it is that same day on every device, in
/// every time zone, before and after a zone change. "Due Thursday" never becomes Wednesday because someone flew.
///
/// **The stored form.** Such a value (a due date without `hasDueTime`, a deadline, a shared task's day) is stored as its
/// day's **anchor**: 10:00:00 UTC on that day. That moment falls inside the same calendar day in every zone from UTC−10
/// (Honolulu) to UTC+13:45 (Chatham in summer), so every comparison against local day boundaries (`startOfDay`), every
/// formatter, and every build from before 0.9.3 read the right day with no change. In UTC−11, −12 and +14 an anchor
/// reads a day off; a device there never has its values rewritten (`rewrite` refuses), so its own days stay right.
///
/// **The old form.** Builds before 0.9.3 stored the writer's local midnight. `day(of:calendar:)` reads one as:
/// 1. an anchor: its own (UTC) day;
/// 2. a midnight in this device's zone: that local day (a value written here, as it was written);
/// 3. a midnight in some other zone (its time of day in UTC is on a quarter hour, as every zone's midnight is): the day
///    it began in the writer's zone. A midnight at T UTC was written at offset −T when T ≤ 10:00 (Honolulu to London),
///    else at 24:00 − T (east of London). So Chicago's Thursday midnight read in Los Angeles is Thursday, not Wednesday
///    22:00, and a device that flew west before it updated still finds the day it was given;
/// 4. anything else (a stray moment on an undated-time task): the local day it shows here.
///
/// **Rewriting never guesses (brief 92).** Readings 3 and 4 are guesses: a value on a quarter hour need not be a
/// midnight. Thursday 09:00 in Chicago is 15:00 UTC, the moment Tokyo's Friday begins; anything that steps an anchor
/// keeping its time of day (a repeat's roll-over, a date picker that keeps the time of the date it opened on, a 0.9.2
/// device doing either) lands it, after a clock change, an hour off 10:00 UTC (Oct 30's anchor, 06:00 EDT in New York,
/// stepped to Nov 11 is 06:00 EST: 11:00 UTC, where UTC+13's Nov 12 begins). So `verdict` stores an anchor only for a
/// value this device can vouch for, a midnight in its own zone (reading 2, the first moment after a gap in the clock
/// included), and leaves every other value exactly as it is stored, whatever `day(of:)` makes of it. Such a value reads
/// as the local day it shows on each device, as before 0.9.3, until a device in its writer's zone anchors it.
///
/// Rewriting happens in the app's one place (the save, the import pass, the first-run pass); `isEnabled` turns it off
/// and leaves reading as it is.
public enum DayAnchor {
    /// The one switch (brief 82): false stops every rewrite into the anchored form, here and in the app. Reading, and
    /// the lists' order, stay as they are either way.
    public static let isEnabled = true

    /// The hour, UTC, a day is stored at.
    public static let hourUTC = 10

    /// A calendar day in the Gregorian calendar: what a date with no time names.
    public struct Day: Hashable, Comparable, Sendable, CustomStringConvertible {
        public var year: Int
        public var month: Int
        public var day: Int

        public init(year: Int, month: Int, day: Int) {
            self.year = year
            self.month = month
            self.day = day
        }

        public static func < (a: Day, b: Day) -> Bool {
            (a.year, a.month, a.day) < (b.year, b.month, b.day)
        }

        /// "2026-11-12".
        public var description: String {
            String(format: "%04d-%02d-%02d", year, month, day)
        }
    }

    // MARK: - The anchor

    /// 10:00:00 UTC on `day`.
    public static func anchor(of day: Day) -> Date {
        let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: hourUTC)
        return utc.date(from: parts) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    /// Whether `value` is a day's anchor: 10:00:00 UTC to the millisecond (CloudKit, the Shared Tasks store and the JSON
    /// keep a date to the millisecond or the second, never less).
    public static func isAnchor(_ value: Date) -> Bool {
        abs(secondsIntoUTCDay(value) - Double(hourUTC * 3600)) < 0.0005
    }

    /// The anchor of the day `value` names (`day(of:calendar:)`); an anchor is its own.
    public static func anchored(_ value: Date, calendar: Calendar) -> Date {
        isAnchor(value) ? value : anchor(of: day(of: value, calendar: calendar))
    }

    // MARK: - Rewriting (brief 92: only what this device can vouch for)

    /// What a store makes of a date with no time on a device in `calendar`'s zone, and why.
    public enum Verdict: Equatable, Sendable {
        /// Store this instead: the value is a midnight in this device's zone (the first moment after a gap in the clock
        /// counts), and this is its day's anchor.
        case anchor(Date)
        /// Already an anchor: nothing to do, in any zone.
        case alreadyAnchored
        /// Rewriting is off (`isEnabled`).
        case disabled
        /// Left exactly as stored: on a quarter hour in UTC but not a midnight in this device's zone. It may be another
        /// zone's midnight (Tokyo's Friday, read in Chicago) or a time on a quarter hour (Chicago's Thursday 09:00, the
        /// same instant); nothing here can tell which.
        case notThisZonesMidnight
        /// Left exactly as stored: not on a quarter hour, so no zone's midnight (a stray moment).
        case notAMidnight
        /// Left exactly as stored: this zone's own midnight, but the anchor would read as another day here (UTC−11, −12
        /// and +14), so the device keeps showing the day it shows now.
        case zoneCannotHoldAnAnchor

        /// Whether the value stays exactly as stored for a reason worth counting (not an anchor, not the switch).
        public var isLeftAlone: Bool {
            switch self {
            case .notThisZonesMidnight, .notAMidnight, .zoneCannotHoldAnAnchor: return true
            case .anchor, .alreadyAnchored, .disabled: return false
            }
        }
    }

    /// The verdict on `value` (the rules at the top): an anchor only for a midnight in this device's zone, kept to the
    /// millisecond (CloudKit's and the Shared Tasks store's precision); every other value is left exactly as it is.
    public static func verdict(_ value: Date, calendar: Calendar, enabled: Bool = isEnabled) -> Verdict {
        guard enabled else { return .disabled }
        if isAnchor(value) { return .alreadyAnchored }
        let here = gregorian(in: calendar.timeZone)
        let start = here.startOfDay(for: value.addingTimeInterval(0.0005))
        guard abs(start.timeIntervalSince(value)) < 0.0005 else {
            return isOnAQuarterHour(value) ? .notThisZonesMidnight : .notAMidnight
        }
        let day = localDay(of: start, calendar: calendar)
        let anchor = anchor(of: day)
        return localDay(of: anchor, calendar: calendar) == day ? .anchor(anchor) : .zoneCannotHoldAnAnchor
    }

    /// What the store should keep instead of `value`, or nil to keep it exactly as it is (`verdict`).
    public static func rewrite(_ value: Date, calendar: Calendar, enabled: Bool = isEnabled) -> Date? {
        if case .anchor(let anchor) = verdict(value, calendar: calendar, enabled: enabled) { return anchor }
        return nil
    }

    // MARK: - Reading

    /// The calendar day a date with no time names (the rules at the top). Idempotent through `anchored`: the day of an
    /// anchor is the day it was made from, in every zone.
    public static func day(of value: Date, calendar: Calendar) -> Day {
        if isAnchor(value) { return utcDay(of: value) }
        let here = gregorian(in: calendar.timeZone)
        if here.startOfDay(for: value) == value { return localDay(of: value, calendar: calendar) }
        guard isOnAQuarterHour(value) else { return localDay(of: value, calendar: calendar) }
        let seconds = secondsIntoUTCDay(value)
        // A midnight at `seconds` past midnight UTC was written at UTC−seconds or UTC+(24 h − seconds): the one inside
        // −10:00...+14:00, west of +14 at 10:00 (where an anchor sits).
        let offset = seconds <= Double(hourUTC * 3600) ? -seconds : 86_400 - seconds
        return utcDay(of: value.addingTimeInterval(offset))
    }

    /// The calendar day `value` falls on in `calendar`'s zone: what a formatter or `startOfDay` shows on this device.
    public static func localDay(of value: Date, calendar: Calendar) -> Day {
        let parts = gregorian(in: calendar.timeZone).dateComponents([.year, .month, .day], from: value)
        return Day(year: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// The start of `day` in `calendar`'s zone (a local midnight, or the first moment after a gap).
    public static func start(of day: Day, calendar: Calendar) -> Date {
        let zone = gregorian(in: calendar.timeZone)
        let noon = zone.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
        return zone.startOfDay(for: noon ?? anchor(of: day))
    }

    // MARK: - Helpers

    private static let utc: Calendar = gregorian(in: TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!)

    private static func gregorian(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private static func utcDay(of value: Date) -> Day {
        let parts = utc.dateComponents([.year, .month, .day], from: value)
        return Day(year: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Whether `value` is on a quarter hour in UTC (to a millisecond), as every zone's midnight is: every offset in use is
    /// a whole number of quarter hours.
    static func isOnAQuarterHour(_ value: Date) -> Bool {
        let quarters = secondsIntoUTCDay(value) / 900
        return abs(quarters - quarters.rounded()) < 0.000_001
    }

    /// Seconds since midnight UTC on `value`'s UTC day, 0..<86 400. Every UTC day is 86 400 s long for `Date`.
    private static func secondsIntoUTCDay(_ value: Date) -> Double {
        let t = value.timeIntervalSinceReferenceDate
        let r = t.truncatingRemainder(dividingBy: 86_400)
        return r < 0 ? r + 86_400 : r
    }
}
