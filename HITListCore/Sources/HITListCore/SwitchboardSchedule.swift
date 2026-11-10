import Foundation

/// A Switchboard's clock (brief 72): when its day (or week) begins and ends, and what that means for the switches
/// on it. Pure, so the arithmetic around midnight, the reset time, daylight-saving changes and a weekly reset day is
/// tested once and the views only ask it.
///
/// George's friend, 2026-11-10: routines that "reset every day at 4am". A board's day starts at its reset time: with a
/// 04:00 reset, 01:30 on Tuesday still belongs to Monday's board day, so switches flipped on Monday evening stay green
/// until 04:00, and then every switch of a daily board turns red again together. A weekly board's week runs from its
/// reset weekday at the reset time to the next.
///
/// A period is named by its **day**: the calendar day (a start of day) it begins on. An untimed switch's due date is
/// such a day, standing for the board day it is due in; a timed switch's due date is a real moment, and the board day
/// it belongs to is the period that moment falls in (00:30 belongs to the board day that began the evening before).
public struct SwitchboardSchedule: Hashable, Sendable {
    public enum Cadence: String, Sendable, CaseIterable, Codable {
        case daily, weekly
    }

    public var cadence: Cadence
    /// Minutes after midnight the board resets at, 0..<1440.
    public var resetMinutes: Int
    /// The Calendar weekday (1 = Sunday ... 7 = Saturday) a weekly board resets on; a daily board ignores it.
    public var resetWeekday: Int

    /// A new Switchboard resets at 04:00 (the friend's example; brief 72's "choice").
    public static let defaultResetMinutes = 4 * 60

    public init(cadence: Cadence, resetMinutes: Int = defaultResetMinutes, resetWeekday: Int = 2) {
        self.cadence = cadence
        self.resetMinutes = min(max(0, resetMinutes), 24 * 60 - 1)
        self.resetWeekday = (1...7).contains(resetWeekday) ? resetWeekday : 2
    }

    /// The stored reset day (`Switchboard.resetWeekday`: 0 = the week start from Settings, else Calendar's 1...7) as
    /// a Calendar weekday.
    public static func weekday(stored: Int, weekStart: Int) -> Int {
        if (1...7).contains(stored) { return stored }
        return (1...7).contains(weekStart) ? weekStart : 1
    }

    /// The cadence a stored string names; an unknown one (written by a later build) reads as daily.
    public static func cadence(stored: String) -> Cadence { Cadence(rawValue: stored) ?? .daily }

    // MARK: - Periods

    /// The moment the period standing for `day` begins: that day at the reset time, wall clock. On a day the clock
    /// skips the reset time (spring forward), the first moment after the gap.
    public func start(ofPeriodDay day: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: resetMinutes / 60, minute: resetMinutes % 60, second: 0, of: midnight,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? midnight
    }

    /// The day standing for the period `moment` falls in.
    public func periodDay(containing moment: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: moment)
        switch cadence {
        case .daily:
            return moment >= start(ofPeriodDay: today, calendar: calendar) ? today : day(today, plus: -1, calendar: calendar)
        case .weekly:
            for back in 0...7 {
                let candidate = day(today, plus: -back, calendar: calendar)
                if calendar.component(.weekday, from: candidate) == resetWeekday,
                   moment >= start(ofPeriodDay: candidate, calendar: calendar) {
                    return candidate
                }
            }
            return day(today, plus: -7, calendar: calendar)
        }
    }

    /// The period `moment` falls in: from its start to the next period's.
    public func period(containing moment: Date, calendar: Calendar = .current) -> DateInterval {
        let day = periodDay(containing: moment, calendar: calendar)
        let begins = start(ofPeriodDay: day, calendar: calendar)
        let ends = start(ofPeriodDay: nextPeriodDay(after: day, calendar: calendar), calendar: calendar)
        return DateInterval(start: begins, end: max(begins, ends))
    }

    /// The day of the period after the one standing for `day`.
    public func nextPeriodDay(after day: Date, calendar: Calendar = .current) -> Date {
        self.day(calendar.startOfDay(for: day), plus: length, calendar: calendar)
    }

    /// Days in a period.
    public var length: Int { cadence == .daily ? 1 : 7 }

    // MARK: - A switch on the board

    /// The board day a switch's due date stands for: for no time, the period its day's reset falls in (a daily
    /// board: that day itself); for a time, the period the moment falls in.
    public func boardDay(ofDue due: Date, hasTime: Bool, calendar: Calendar = .current) -> Date {
        let moment = hasTime ? due : start(ofPeriodDay: due, calendar: calendar)
        return periodDay(containing: moment, calendar: calendar)
    }

    /// The due date moved by whole periods so that it stands for `periodDay`: the day itself without a time; with
    /// one, the same wall-clock time (and on a weekly board the same weekday) that many periods on or back.
    public func moving(_ due: Date, hasTime: Bool, toPeriodDay periodDay: Date, calendar: Calendar = .current) -> Date {
        let target = calendar.startOfDay(for: periodDay)
        guard hasTime else { return target }
        let from = boardDay(ofDue: due, hasTime: true, calendar: calendar)
        let days = calendar.dateComponents([.day], from: from, to: target).day ?? 0
        var moved = days == 0 ? due : calendar.date(byAdding: .day, value: days, to: due) ?? due
        // A daylight-saving change can leave the moved moment a period out; step it back in (at most twice).
        for _ in 0..<2 {
            let landed = boardDay(ofDue: moved, hasTime: true, calendar: calendar)
            guard landed != target else { break }
            moved = calendar.date(byAdding: .day, value: landed < target ? length : -length, to: moved) ?? moved
        }
        return moved
    }

    /// Green while the switch's board day is still ahead (done for the period now), red from its board day on. A
    /// switch with no due date has never been flipped: red.
    public func side(due: Date?, hasTime: Bool, now: Date, calendar: Calendar = .current) -> FlipboardSwitch.Side {
        guard let due else { return .red }
        return boardDay(ofDue: due, hasTime: hasTime, calendar: calendar) > periodDay(containing: now, calendar: calendar)
            ? .green : .red
    }

    /// When a red switch is due in the period now: the period's start without a time, else its time in this period
    /// (a switch missed in earlier periods is due again at this period's time: routines don't pile up). For a green
    /// switch, its own due date.
    public func dueMoment(due: Date?, hasTime: Bool, now: Date, calendar: Calendar = .current) -> Date {
        let current = periodDay(containing: now, calendar: calendar)
        guard let due, hasTime else {
            if let due, boardDay(ofDue: due, hasTime: false, calendar: calendar) > current {
                return start(ofPeriodDay: due, calendar: calendar)
            }
            return start(ofPeriodDay: current, calendar: calendar)
        }
        let day = boardDay(ofDue: due, hasTime: true, calendar: calendar)
        return day < current ? moving(due, hasTime: true, toPeriodDay: current, calendar: calendar) : due
    }

    /// Red and its moment in this period has come: from the period's start without a time, from its time with one.
    public func isDueNow(due: Date?, hasTime: Bool, now: Date, calendar: Calendar = .current) -> Bool {
        side(due: due, hasTime: hasTime, now: now, calendar: calendar) == .red
            && now >= dueMoment(due: due, hasTime: hasTime, now: now, calendar: calendar)
    }

    /// A red timed switch past its time in this period: the Flipboard's quiet "late". Untimed switches are never
    /// late (the board just reset; nothing counts what is missed).
    public func isLate(due: Date?, hasTime: Bool, now: Date, calendar: Calendar = .current) -> Bool {
        guard hasTime, due != nil else { return false }
        return isDueNow(due: due, hasTime: hasTime, now: now, calendar: calendar)
    }

    /// Where a flip lands the due date: the next period (its day, or its time in it), not "interval from the flip
    /// day".
    public func dueAfterFlip(due: Date?, hasTime: Bool, now: Date, calendar: Calendar = .current) -> Date {
        let next = nextPeriodDay(after: periodDay(containing: now, calendar: calendar), calendar: calendar)
        guard let due, hasTime else { return next }
        return moving(due, hasTime: true, toPeriodDay: next, calendar: calendar)
    }

    /// Where "Flip back to red" puts it: this period (its day, or its time in it).
    public func dueAfterFlipBack(due: Date?, hasTime: Bool, now: Date, calendar: Calendar = .current) -> Date {
        let current = periodDay(containing: now, calendar: calendar)
        guard let due, hasTime else { return current }
        return moving(due, hasTime: true, toPeriodDay: current, calendar: calendar)
    }

    /// How far through the period now is, 0...1 (the light bar of a green switch).
    public func elapsedFraction(now: Date, calendar: Calendar = .current) -> Double {
        let period = period(containing: now, calendar: calendar)
        guard period.duration > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(period.start) / period.duration))
    }

    // MARK: - Helpers

    private func day(_ day: Date, plus days: Int, calendar: Calendar) -> Date {
        guard days != 0 else { return day }
        return calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: day) ?? day)
    }
}
