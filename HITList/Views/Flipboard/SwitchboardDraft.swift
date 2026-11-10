import Foundation
import SwiftData
import HITListCore

/// What the Switchboard card holds while you type and pick (brief 72), as a plain value so tests can drive it: the
/// name, Daily or Weekly, the reset time (04:00 for a new board), the reset day of a weekly board (0, "the week
/// start", until one is picked) and "Overdue becomes task".
struct SwitchboardDraft: Equatable {
    var name: String
    var cadence: SwitchboardSchedule.Cadence
    var resetTime: PickerTime
    /// 0 = the week start from Settings, else Calendar's 1...7.
    var resetWeekday: Int
    var overdueBecomesTask: Bool
    /// The board as the card found it, when editing: what "changed" is measured against.
    private(set) var original: Original?

    struct Original: Equatable {
        let name: String
        let cadence: SwitchboardSchedule.Cadence
        let resetTime: PickerTime
        let resetWeekday: Int
        let overdueBecomesTask: Bool
    }

    /// A new board: Daily, resetting at 04:00.
    init(name: String = "", cadence: SwitchboardSchedule.Cadence = .daily,
         resetTime: PickerTime = SwitchboardDraft.time(minutes: SwitchboardSchedule.defaultResetMinutes),
         resetWeekday: Int = 0, overdueBecomesTask: Bool = false) {
        self.name = name
        self.cadence = cadence
        self.resetTime = resetTime
        self.resetWeekday = resetWeekday
        self.overdueBecomesTask = overdueBecomesTask
    }

    /// An existing board, filled in.
    init(_ board: Switchboard) {
        self.init(name: board.name, cadence: board.cadenceValue, resetTime: Self.time(minutes: board.resetMinutes),
                  resetWeekday: board.resetWeekday, overdueBecomesTask: board.overdueBecomesTask)
        original = Original(name: board.name, cadence: cadence, resetTime: resetTime, resetWeekday: resetWeekday,
                            overdueBecomesTask: overdueBecomesTask)
    }

    static func time(minutes: Int) -> PickerTime {
        let minutes = min(max(0, minutes), 24 * 60 - 1)
        return PickerTime(hour: minutes / 60, minute: minutes % 60)
    }

    var resetMinutes: Int { resetTime.hour * 60 + resetTime.minute }

    var trimmedName: String { TaskLimits.clampedTitle(name) }

    /// Save has a name to give the board.
    var canSave: Bool { !trimmedName.isEmpty }

    /// The card has something to lose: a new board's name, or an edit's changes.
    var hasContent: Bool {
        guard let original else { return !trimmedName.isEmpty }
        return trimmedName != original.name || cadence != original.cadence || resetTime != original.resetTime
            || (cadence == .weekly && resetWeekday != original.resetWeekday) || overdueBecomesTask != original.overdueBecomesTask
    }

    /// Add (a new board, after the others) or Save (`editing`; a clock change re-lands its switches). Nil without a
    /// name.
    @MainActor
    @discardableResult
    func save(editing board: Switchboard?, in context: ModelContext, now: Date = Date()) throws -> Switchboard? {
        guard canSave else { return nil }
        guard let board else {
            return try Flipboard.createSwitchboard(name: trimmedName, cadence: cadence, resetMinutes: resetMinutes,
                                                   resetWeekday: resetWeekday, overdueBecomesTask: overdueBecomesTask, in: context)
        }
        Flipboard.update(board, name: trimmedName, cadence: cadence, resetMinutes: resetMinutes, resetWeekday: resetWeekday,
                         overdueBecomesTask: overdueBecomesTask, in: context, now: now)
        return board
    }

    // MARK: Words

    /// The reset days a weekly board offers: the week start first ("Week start (Monday)"), then every day of the week
    /// from the week start on.
    static func weekdayChoices(weekStart: Int, calendar: Calendar = .current) -> [(value: Int, title: String)] {
        let names = calendar.standaloneWeekdaySymbols
        let start = (1...7).contains(weekStart) ? weekStart : 1
        let days = (0..<7).map { (start - 1 + $0) % 7 + 1 }
        return [(0, "Week start (\(names[start - 1]))")] + days.map { ($0, names[$0 - 1]) }
    }

    /// What a board's header and card say about its day: "Daily · resets 04:00", "Weekly · resets Monday 04:00".
    static func cadenceLine(cadence: SwitchboardSchedule.Cadence, resetMinutes: Int, resetWeekday: Int,
                            weekStart: Int = Preferences.weekStartWeekday(), calendar: Calendar = .current,
                            locale: Locale = .current) -> String {
        var cal = calendar
        cal.locale = locale
        let reference = cal.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let at = cal.date(byAdding: .minute, value: min(max(0, resetMinutes), 24 * 60 - 1), to: reference) ?? reference
        let time = Flipboard.timeText(at, calendar: cal, locale: locale)
        switch cadence {
        case .daily:
            return "Daily · resets \(time)"
        case .weekly:
            let weekday = SwitchboardSchedule.weekday(stored: resetWeekday, weekStart: weekStart)
            return "Weekly · resets \(cal.standaloneWeekdaySymbols[weekday - 1]) \(time)"
        }
    }

    static func cadenceLine(_ board: Switchboard, calendar: Calendar = .current, locale: Locale = .current) -> String {
        cadenceLine(cadence: board.cadenceValue, resetMinutes: board.resetMinutes, resetWeekday: board.resetWeekday,
                    calendar: calendar, locale: locale)
    }

    /// The header's count: "3 of 5" switches done (green) now.
    static func doneCount(_ switches: [TaskItem], now: Date) -> String {
        let done = switches.filter { Flipboard.side(of: $0, now: now) == .green }.count
        return "\(done) of \(switches.count)"
    }
}
