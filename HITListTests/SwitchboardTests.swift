import XCTest
import SwiftData
import HITListCore
@testable import HITList

/// Brief 72: Switchboards, routines of Flipboard switches, as the app's services carry them.
@MainActor
final class SwitchboardExportTests: XCTestCase {
    /// "Copy for Claude" holds the boards its shown switches are on, and says what a switch and a board are.
    func testTheClaudeExportCarriesTheBoardsOfTheSwitchesItShows() throws {
        let container = ModelContainerFactory.preview()
        let context = container.mainContext
        defer { withExtendedLifetime(container) {} }
        let bed = Switchboard(name: "Before Bed"), empty = Switchboard(name: "Deep Clean")
        context.insert(bed)
        context.insert(empty)
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, in: context)
        floss.switchboard = bed
        try context.save()

        let snapshot = try ClaudeExport.snapshot(from: context, rule: ClaudeAccessRule(mode: .allExceptHidden))
        XCTAssertEqual(snapshot.switchboards?.map(\.name), ["Before Bed"], "only the boards of what it shows")
        XCTAssertEqual(snapshot.tasks.first { $0.title == "Floss" }?.switchboardID, bed.id)
        XCTAssertTrue(ClaudeExport.schemaNote.contains("\"switchboardID\""))
        XCTAssertTrue(ClaudeExport.schemaNote.contains("\"overdueBecomesTask\""))
    }
}

/// Brief 72, item 3: the Flipboard's rules on a Switchboard (pure, fixed UTC calendar and dates). A board's day starts
/// at its reset time; a flip lands on the board's next period; chargers count within the period; a switch may have a
/// time, which its caption shows.
@MainActor
final class SwitchboardRulesTests: XCTestCase {
    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1
        return cal
    }()
    private var utc: Calendar { Self.utc }
    private let british = Locale(identifier: "en_GB")

    /// 2026-10-month-day at hour:minute UTC. 2026-10-19 is a Monday.
    private func d(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private let daily = SwitchboardSchedule(cadence: .daily, resetMinutes: 240)
    private let weekly = SwitchboardSchedule(cadence: .weekly, resetMinutes: 240, resetWeekday: 2)
    private var dailyClock: Flipboard.Clock { Flipboard.Clock(rule: .daily, board: daily) }

    // MARK: Flips

    func testAFlipOnABoardLandsOnTheNextBoardDayNotIntervalFromTheFlip() {
        let (next, outcome) = Flipboard.afterFlip(Flipboard.Charge(due: d(19), count: 0, periodStart: nil), target: 1,
                                                  clock: dailyClock, now: d(19, 21), calendar: utc)
        XCTAssertEqual(outcome, .charged)
        XCTAssertEqual(next.due, d(20))
        XCTAssertEqual(dailyClock.side(next.due, now: d(20, 1, 30), calendar: utc), .green, "past midnight: still done")
        XCTAssertEqual(dailyClock.side(next.due, now: d(20, 4), calendar: utc), .red, "the reset")
    }

    func testAGreenBoardSwitchIsAlreadyDoneForThePeriod() {
        let green = Flipboard.Charge(due: d(20), count: 1, periodStart: d(19, 21))
        let (same, outcome) = Flipboard.afterFlip(green, target: 1, clock: dailyClock, now: d(19, 22), calendar: utc)
        XCTAssertEqual(outcome, .ignored, "a flip can't do it twice in one board day")
        XCTAssertEqual(same, green)
    }

    func testAWeeklyBoardsFlipLandsOnItsNextResetDay() {
        let clock = Flipboard.Clock(rule: .weekly, board: weekly)
        let (next, _) = Flipboard.afterFlip(Flipboard.Charge(due: d(19), count: 0, periodStart: nil), target: 1, clock: clock,
                                            now: d(22, 9), calendar: utc)
        XCTAssertEqual(next.due, d(26), "next Monday")
    }

    func testAChargerOnABoardCountsWithinTheBoardDay() {
        let clock = dailyClock
        let start = Flipboard.Charge(due: d(19), count: 0, periodStart: nil)
        let (one, outcome) = Flipboard.afterFlip(start, target: 3, clock: clock, now: d(19, 10), calendar: utc)
        XCTAssertEqual(outcome, .counted(1))
        XCTAssertEqual(Flipboard.effectiveCount(one, target: 3, clock: clock, now: d(20, 2), calendar: utc), 1,
                       "02:00 Tuesday is still Monday's board day")
        XCTAssertEqual(Flipboard.effectiveCount(one, target: 3, clock: clock, now: d(20, 4), calendar: utc), 0,
                       "the reset makes the count stale")
        let (two, _) = Flipboard.afterFlip(one, target: 3, clock: clock, now: d(19, 12), calendar: utc)
        let (charged, last) = Flipboard.afterFlip(two, target: 3, clock: clock, now: d(19, 20), calendar: utc)
        XCTAssertEqual(last, .charged)
        XCTAssertEqual(charged.due, d(20))
        XCTAssertEqual(Flipboard.effectiveCount(charged, target: 3, clock: clock, now: d(19, 23), calendar: utc), 3)
    }

    func testFlipBackOnABoardPutsItBackInThisBoardDay() {
        let green = Flipboard.Charge(due: d(20), count: 1, periodStart: d(19, 21))
        let back = try! XCTUnwrap(Flipboard.afterFlipBack(green, target: 1, clock: dailyClock, now: d(20, 1), calendar: utc))
        XCTAssertEqual(back.due, d(19), "01:00 Tuesday: Monday's board day")
        XCTAssertEqual(dailyClock.side(back.due, now: d(20, 1), calendar: utc), .red)
        XCTAssertNil(Flipboard.afterFlipBack(back, target: 1, clock: dailyClock, now: d(20, 1), calendar: utc), "nothing left to undo")
    }

    func testATimedBoardSwitchFlipsToItsTimeOnTheNextBoardDay() {
        let clock = Flipboard.Clock(rule: .daily, board: daily, hasTime: true)
        let (next, _) = Flipboard.afterFlip(Flipboard.Charge(due: d(19, 21), count: 0, periodStart: nil), target: 1,
                                            clock: clock, now: d(19, 20), calendar: utc)
        XCTAssertEqual(next.due, d(20, 21))
    }

    func testALooseTimedSwitchsFlipKeepsItsTime() {
        let clock = Flipboard.Clock(rule: RecurrenceRule(frequency: .daily, interval: 3), hasTime: true)
        let (next, _) = Flipboard.afterFlip(Flipboard.Charge(due: d(19, 21), count: 0, periodStart: nil), target: 1,
                                            clock: clock, now: d(19, 22), calendar: utc)
        XCTAssertEqual(next.due, d(22, 21), "three days on, at 21:00")
    }

    // MARK: Captions and lights

    func testCaptionsOnABoard() {
        let cap = { (clock: Flipboard.Clock, due: Date?, now: Date, count: Int, target: Int) in
            Flipboard.caption(clock: clock, due: due, started: true, count: count, target: target, now: now,
                              calendar: self.utc, locale: self.british)
        }
        XCTAssertEqual(cap(dailyClock, d(20), d(19, 22), 1, 1), "Done today")
        XCTAssertEqual(cap(dailyClock, d(19), d(19, 22), 0, 1), "Due today")
        XCTAssertEqual(cap(dailyClock, d(12), d(19, 22), 0, 1), "Due today", "no counts of what is late")
        XCTAssertEqual(cap(dailyClock, d(19), d(19, 22), 2, 3), "2 of 3 today")
        let week = Flipboard.Clock(rule: .weekly, board: weekly)
        XCTAssertEqual(cap(week, d(26), d(21), 1, 1), "Done this week")
        XCTAssertEqual(cap(week, d(19), d(21), 0, 1), "Due this week")
        let timed = Flipboard.Clock(rule: .daily, board: daily, hasTime: true)
        XCTAssertEqual(cap(timed, d(19, 21), d(19, 10), 0, 1), "Due 21:00", "calm before its time")
        XCTAssertEqual(cap(timed, d(19, 21), d(19, 22), 0, 1), "Due since 21:00")
        XCTAssertEqual(cap(timed, d(18, 21), d(19, 10), 0, 1), "Due 21:00", "missed yesterday: today's time")
    }

    func testALooseTimedSwitchsCaption() {
        let clock = Flipboard.Clock(rule: .daily, hasTime: true)
        let cap = { (due: Date, now: Date) in
            Flipboard.caption(clock: clock, due: due, started: true, count: 0, target: 1, now: now, calendar: self.utc,
                              locale: self.british)
        }
        XCTAssertEqual(cap(d(19, 21), d(19, 10)), "Due 21:00")
        XCTAssertEqual(cap(d(19, 21), d(19, 22)), "Due since 21:00")
        XCTAssertEqual(cap(d(17, 21), d(19, 10)), "2 days overdue", "a loose switch keeps its day counts")
        XCTAssertEqual(Flipboard.caption(clock: Flipboard.Clock(rule: .daily), due: d(19), started: true, count: 0, target: 1,
                                         now: d(19, 10), calendar: utc), "Due today", "untimed, as before")
    }

    func testTheLightBreathesOnlyWhenLate() {
        let timed = Flipboard.Clock(rule: .daily, board: daily, hasTime: true)
        XCTAssertFalse(timed.isLate(d(19, 21), now: d(19, 20), calendar: utc))
        XCTAssertTrue(timed.isLate(d(19, 21), now: d(19, 21, 1), calendar: utc))
        XCTAssertFalse(dailyClock.isLate(d(12), now: d(19, 10), calendar: utc), "an untimed board switch is never late")
        XCTAssertTrue(Flipboard.Clock(rule: .daily).isLate(d(17), now: d(19, 10), calendar: utc), "a loose one past its day is")
    }

    func testTheLightBarRunsThroughTheBoardDay() {
        XCTAssertEqual(Flipboard.elapsedFraction(clock: dailyClock, due: d(20), now: d(19, 16), calendar: utc), 0.5, accuracy: 0.001)
        XCTAssertEqual(Flipboard.elapsedFraction(clock: dailyClock, due: d(19), now: d(19, 16), calendar: utc), 1, "red: full")
    }

    // MARK: Order

    func testABoardOrdersTimedSwitchesByTheirTimeInTheBoardDayThenTheUntimed() {
        let order = Flipboard.boardOrder([
            (title: "Floss", minutes: nil, created: d(1)),
            (title: "Lights out", minutes: 30, created: d(2)),
            (title: "Take meds", minutes: 21 * 60, created: d(3)),
            (title: "Stretch", minutes: 7 * 60, created: d(4)),
            (title: "Brush teeth", minutes: nil, created: d(5)),
        ], resetMinutes: 240)
        XCTAssertEqual(order, ["Stretch", "Take meds", "Lights out", "Floss", "Brush teeth"],
                       "00:30 comes last of the times: it belongs to the end of the board day")
    }
}

/// Brief 72, item 3: switches and Switchboards in the store (in-memory; these run on `Calendar.current` and `Date()`,
/// so expectations ask the board's own clock).
@MainActor
final class SwitchboardActionsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let cal = Calendar.current

    override func setUp() async throws { container = ModelContainerFactory.preview() }
    override func tearDown() async throws { container = nil }

    private func board(_ name: String = "Before Bed", cadence: SwitchboardSchedule.Cadence = .daily) throws -> Switchboard {
        try Flipboard.createSwitchboard(name: name, cadence: cadence, in: context)
    }

    func testANewSwitchboardIsDailyAtFourAndTakesTheNextPlace() throws {
        let bed = try board()
        let clean = try board("Deep Clean", cadence: .weekly)
        XCTAssertEqual(bed.cadenceValue, .daily)
        XCTAssertEqual(bed.resetMinutes, 240)
        XCTAssertEqual(clean.cadenceValue, .weekly)
        XCTAssertEqual(clean.resetWeekday, 0, "the week start from Settings")
        XCTAssertEqual([bed.sortOrder, clean.sortOrder], [0, 1])
        XCTAssertEqual(try Flipboard.switchboards(in: context).map(\.name), ["Before Bed", "Deep Clean"])
    }

    func testABoardsNameIsTrimmedAndNeverEmpty() throws {
        XCTAssertThrowsError(try Flipboard.createSwitchboard(name: "   ", in: context))
        XCTAssertEqual(try Flipboard.createSwitchboard(name: "  Before Bed ", in: context).name, "Before Bed")
    }

    func testMovingBoardsUpAndDown() throws {
        let a = try board("A"), b = try board("B"), c = try board("C")
        Flipboard.moveSwitchboard(c, by: -1, in: context)
        XCTAssertEqual(try Flipboard.switchboards(in: context).map(\.name), ["A", "C", "B"])
        Flipboard.moveSwitchboard(a, by: -1, in: context)
        XCTAssertEqual(try Flipboard.switchboards(in: context).map(\.name), ["A", "C", "B"], "the first stays first")
        Flipboard.moveSwitchboard(a, by: 1, in: context)
        XCTAssertEqual(try Flipboard.switchboards(in: context).map(\.name), ["C", "A", "B"])
        _ = b
    }

    func testASwitchCreatedOnABoardOnItsCadenceIsDueThisBoardDay() throws {
        let bed = try board()
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, board: bed, in: context)
        XCTAssertEqual(floss.switchboard?.id, bed.id)
        XCTAssertEqual(floss.resetBoard?.id, bed.id, "the board's cadence: it resets with the board")
        XCTAssertTrue(Flipboard.isMember(floss))
        XCTAssertEqual(floss.dueDate, bed.schedule().periodDay(containing: Date()))
        XCTAssertEqual(Flipboard.side(of: floss), .red, "not done yet this board day")
        Flipboard.flip(floss, in: context)
        XCTAssertEqual(floss.dueDate, bed.schedule().dueAfterFlip(due: nil, hasTime: false, now: Date()))
        XCTAssertEqual(Flipboard.side(of: floss), .green)
        Flipboard.flipBack(floss, in: context)
        XCTAssertEqual(Flipboard.side(of: floss), .red)
    }

    func testATimedSwitch() throws {
        let meds = try Flipboard.createSwitch(title: "Take meds", rule: .daily, time: PickerTime(hour: 21, minute: 0), in: context)
        XCTAssertTrue(meds.hasDueTime)
        XCTAssertEqual(meds.dueDate, cal.date(bySettingHour: 21, minute: 0, second: 0, of: Date()))
        XCTAssertEqual(meds.recurrenceRule?.time, RecurrenceRule.TimeOfDay(hour: 21, minute: 0))
        XCTAssertEqual(Flipboard.time(of: meds), PickerTime(hour: 21, minute: 0))
        Flipboard.setTime(PickerTime(hour: 7, minute: 30), for: meds, in: context)
        XCTAssertEqual(Flipboard.time(of: meds), PickerTime(hour: 7, minute: 30))
        XCTAssertEqual(cal.startOfDay(for: meds.dueDate!), cal.startOfDay(for: Date()), "the same day")
        Flipboard.setTime(nil, for: meds, in: context)
        XCTAssertFalse(meds.hasDueTime)
        XCTAssertNil(Flipboard.time(of: meds))
        XCTAssertEqual(meds.dueDate, cal.startOfDay(for: Date()))
        XCTAssertNil(meds.recurrenceRule?.time)
    }

    // MARK: A board's reset is a default, not a lock (George, 2026-11-16)

    /// George: "when you group switches that already exist … they maintain their old timing. That way we can group
    /// switches together, one that resets once a week and one that resets every other day."
    func testGroupingSwitchesKeepsEachOnesTiming() throws {
        let bed = try board()
        let weekly = try Flipboard.createSwitch(title: "Water the plants", rule: .weekly, in: context)
        Flipboard.flip(weekly, in: context)
        let everyOther = try Flipboard.createSwitch(title: "Shave", rule: RecurrenceRule(frequency: .daily, interval: 2), in: context)
        Flipboard.flip(everyOther, in: context)
        let red = try Flipboard.createSwitch(title: "Floss", rule: RecurrenceRule(frequency: .daily, interval: 3), in: context)
        let before = [weekly, everyOther, red].map { ($0.dueDate, $0.recurrence, $0.hasDueTime) }

        for task in [weekly, everyOther, red] { Flipboard.move(task, to: bed, in: context) }
        XCTAssertEqual(Set(bed.switches?.map(\.title) ?? []), ["Water the plants", "Shave", "Floss"])
        for (task, was) in zip([weekly, everyOther, red], before) {
            XCTAssertEqual(task.dueDate, was.0, "\(task.title) is due when it was")
            XCTAssertEqual(task.recurrence, was.1, "\(task.title) repeats as it did")
            XCTAssertEqual(task.hasDueTime, was.2)
            XCTAssertNil(task.resetBoard, "\(task.title) sits on the board on its own days")
            XCTAssertNil(task.filterSwitchboard, "so every list, widget and reminder judges it as a loose switch")
        }
        XCTAssertEqual(Flipboard.side(of: weekly), .green)
        XCTAssertEqual(Flipboard.side(of: red), .red)

        // They flip as they did loose: the interval from the flip day, not the board's next day.
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        Flipboard.flip(red, in: context)
        XCTAssertEqual(red.dueDate, cal.date(byAdding: .day, value: 3, to: today))
        XCTAssertEqual(Flipboard.caption(clock: Flipboard.Clock(everyOther), due: everyOther.dueDate, started: true, count: 1,
                                         target: 1, now: Date()), "0 of 2 days", "and count their own days")

        // And leave as they came.
        Flipboard.move(weekly, to: nil, in: context)
        XCTAssertNil(weekly.switchboard)
        XCTAssertEqual(weekly.dueDate, before[0].0)
        XCTAssertEqual(weekly.recurrence, before[0].1)
    }

    /// A switch whose repeat is the board's cadence joins the board's clock, done staying done and due staying due,
    /// and goes on as a loose switch on that cadence when it leaves.
    func testASwitchOnTheBoardsCadenceJoinsItsClockAndLeavesItKeepingItsSide() throws {
        let bed = try board()
        let green = try Flipboard.createSwitch(title: "Vitamins", rule: .daily, in: context)
        Flipboard.flip(green, in: context)
        let red = try Flipboard.createSwitch(title: "Floss", rule: .daily, in: context)
        Flipboard.move(green, to: bed, in: context)
        Flipboard.move(red, to: bed, in: context)
        XCTAssertEqual(green.resetBoard?.id, bed.id)
        XCTAssertEqual(Flipboard.side(of: green), .green, "done stays done: due on the next board day")
        XCTAssertEqual(green.dueDate, bed.schedule().dueAfterFlip(due: nil, hasTime: false, now: Date()))
        XCTAssertEqual(Flipboard.side(of: red), .red)
        XCTAssertEqual(green.recurrenceRule, .daily)

        Flipboard.move(green, to: nil, in: context)
        Flipboard.move(red, to: nil, in: context)
        XCTAssertNil(green.switchboard)
        XCTAssertEqual(green.recurrenceRule, .daily, "a loose switch keeps the cadence as its interval")
        XCTAssertEqual(Flipboard.side(of: green), .green)
        XCTAssertEqual(Flipboard.side(of: red), .red)
        XCTAssertTrue(bed.switches?.isEmpty ?? true)
    }

    func testASwitchCreatedOnABoardOnAnotherIntervalKeepsItsOwnDays() throws {
        let bed = try board()
        let sheets = try Flipboard.createSwitch(title: "Change the sheets", rule: RecurrenceRule(frequency: .weekly, interval: 2),
                                                board: bed, in: context)
        XCTAssertEqual(sheets.switchboard?.id, bed.id)
        XCTAssertEqual(sheets.recurrenceRule, RecurrenceRule(frequency: .weekly, interval: 2))
        XCTAssertNil(sheets.resetBoard)
        XCTAssertEqual(sheets.dueDate, Calendar.current.startOfDay(for: Date()), "due today, as a new loose switch is")
        XCTAssertFalse(Flipboard.hasStarted(sheets), "red until its first flip, as a new loose switch is")
    }

    func testMovingASwitchBetweenBoards() throws {
        let bed = try board(), clean = try board("Deep Clean", cadence: .weekly)
        let vacuum = try Flipboard.createSwitch(title: "Vacuum", rule: .daily, board: bed, in: context)
        Flipboard.flip(vacuum, in: context)
        Flipboard.move(vacuum, to: clean, in: context)
        XCTAssertEqual(vacuum.switchboard?.id, clean.id)
        XCTAssertEqual(vacuum.recurrenceRule, .daily, "still every day: not the weekly board's cadence")
        XCTAssertNil(vacuum.resetBoard, "so on its own days there")
        XCTAssertEqual(Flipboard.side(of: vacuum), .green, "done stays done")
        XCTAssertTrue(bed.switches?.isEmpty ?? true)

        let mop = try Flipboard.createSwitch(title: "Mop", rule: .weekly, in: context)
        Flipboard.move(mop, to: clean, in: context)
        XCTAssertEqual(mop.resetBoard?.id, clean.id, "every week on a weekly board: with the board")
        Flipboard.move(vacuum, to: bed, in: context)
        XCTAssertEqual(vacuum.resetBoard?.id, bed.id, "and back on the daily board, with that one")
        XCTAssertEqual(Flipboard.side(of: vacuum), .green)
    }

    /// The card's Save on a board's clock moves the switches that reset with it and leaves the others alone; one
    /// whose repeat is the board's new cadence resets with it from then on.
    func testChangingABoardsClockLeavesSwitchesOnTheirOwnDaysAlone() throws {
        let bed = try board()
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, board: bed, in: context)
        let shave = try Flipboard.createSwitch(title: "Shave", rule: RecurrenceRule(frequency: .daily, interval: 2), in: context)
        Flipboard.flip(shave, in: context)
        Flipboard.move(shave, to: bed, in: context)
        let plants = try Flipboard.createSwitch(title: "Water the plants", rule: .weekly, in: context)
        Flipboard.flip(plants, in: context)
        Flipboard.move(plants, to: bed, in: context)
        let shaveDue = shave.dueDate

        Flipboard.update(bed, name: bed.name, cadence: .daily, resetMinutes: 6 * 60, resetWeekday: 0,
                         overdueBecomesTask: false, in: context)
        XCTAssertEqual(shave.dueDate, shaveDue, "a new reset time is nothing to a switch on its own days")
        XCTAssertEqual(floss.resetBoard?.id, bed.id)

        Flipboard.update(bed, name: bed.name, cadence: .weekly, resetMinutes: 6 * 60, resetWeekday: 0,
                         overdueBecomesTask: false, in: context)
        XCTAssertEqual(floss.recurrenceRule, .weekly, "the one that reset with the board follows its cadence")
        XCTAssertEqual(floss.resetBoard?.id, bed.id)
        XCTAssertEqual(shave.dueDate, shaveDue)
        XCTAssertEqual(shave.recurrenceRule, RecurrenceRule(frequency: .daily, interval: 2))
        XCTAssertNil(shave.resetBoard)
        XCTAssertEqual(plants.resetBoard?.id, bed.id, "every week on a board that is now weekly: with the board")
        XCTAssertEqual(Flipboard.side(of: plants), .green, "done stays done")
    }

    func testChangingABoardsCadenceRelandsItsSwitches() throws {
        let bed = try board()
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, board: bed, in: context)
        Flipboard.flip(floss, in: context)
        let stretch = try Flipboard.createSwitch(title: "Stretch", rule: .daily, board: bed, in: context)
        Flipboard.update(bed, name: "Weekly Reset", cadence: .weekly, resetMinutes: 9 * 60, resetWeekday: 7,
                         overdueBecomesTask: true, in: context)
        XCTAssertEqual(bed.name, "Weekly Reset")
        XCTAssertEqual(bed.cadenceValue, .weekly)
        XCTAssertEqual(bed.resetMinutes, 540)
        XCTAssertEqual(bed.resetWeekday, 7)
        XCTAssertTrue(bed.overdueBecomesTask)
        XCTAssertEqual(floss.recurrenceRule, .weekly)
        XCTAssertEqual(Flipboard.side(of: floss), .green, "done stays done")
        XCTAssertEqual(Flipboard.side(of: stretch), .red)
        XCTAssertTrue(stretch.filterSwitchOptedIn, "the board's toggle")
    }

    func testDeletingABoardKeepsItsSwitchesLooseOrDeletesThem() throws {
        let bed = try board(), clean = try board("Deep Clean")
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, board: bed, in: context)
        let vacuum = try Flipboard.createSwitch(title: "Vacuum", rule: .weekly, board: clean, in: context)
        _ = try TaskActions.addSubtask("Under the bed", to: vacuum, in: context)
        Flipboard.deleteSwitchboard(bed, deletingSwitches: false, in: context)
        XCTAssertNil(floss.switchboard)
        XCTAssertTrue(Flipboard.isMember(floss), "kept, as a loose switch")
        Flipboard.deleteSwitchboard(clean, deletingSwitches: true, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title), ["Floss"], "its switches and their sub-tasks went")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Switchboard>()), 0)
    }

    /// Remove from Flipboard takes a switch off its board too, and deleting a board with its switches never deletes a
    /// task that is no longer a switch.
    func testRemovingASwitchFromTheFlipboardTakesItOffItsBoard() throws {
        let bed = try board()
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, board: bed, in: context)
        let stretch = try Flipboard.createSwitch(title: "Stretch", rule: .daily, board: bed, in: context)
        Flipboard.remove(floss, in: context)
        XCTAssertNil(floss.switchboard)
        XCTAssertEqual(Flipboard.switches(on: bed).map(\.title), ["Stretch"])
        // An older build takes the label off but knows nothing of the board.
        stretch.labels = []
        XCTAssertTrue(Flipboard.switches(on: bed).isEmpty)
        Flipboard.deleteSwitchboard(bed, deletingSwitches: true, in: context)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<TaskItem>()).map(\.title)), ["Floss", "Stretch"],
                       "neither is a switch any more: both stay")
    }

    func testAddingATimedTaskToTheBoardKeepsItsTime() throws {
        let gym = TaskItem(title: "Gym", dueDate: cal.date(bySettingHour: 7, minute: 0, second: 0, of: Date()), hasDueTime: true,
                           recurrence: .weekdays)
        context.insert(gym)
        try Flipboard.add(gym, in: context)
        XCTAssertTrue(gym.hasDueTime, "brief 72: a switch may have a time")
        XCTAssertTrue(Flipboard.isMember(gym))
    }

    func testUndoingADeleteBringsTheSwitchBackOnItsBoard() throws {
        let bed = try board()
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, board: bed, overdueBecomesTask: true, in: context)
        let gone = Flipboard.delete(floss, in: context)
        XCTAssertTrue(bed.switches?.isEmpty ?? true)
        let back = try XCTUnwrap(Flipboard.restore(gone, in: context))
        XCTAssertEqual(back.switchboard?.id, bed.id)
        XCTAssertTrue(back.overdueBecomesTask)
    }

    func testTheBoardOrderOfRealSwitches() throws {
        let bed = try board()
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, board: bed, in: context)
        let meds = try Flipboard.createSwitch(title: "Take meds", rule: .daily, time: PickerTime(hour: 21, minute: 0),
                                              board: bed, in: context)
        let lights = try Flipboard.createSwitch(title: "Lights out", rule: .daily, time: PickerTime(hour: 0, minute: 30),
                                                board: bed, in: context)
        XCTAssertEqual(Flipboard.sorted(onBoard: [floss, lights, meds], bed).map(\.title), ["Take meds", "Lights out", "Floss"])
    }
}

/// Brief 72, item 5: the Switchboard card's draft and words.
@MainActor
final class SwitchboardDraftTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
    private let british = Locale(identifier: "en_GB")

    override func setUp() async throws { container = ModelContainerFactory.preview() }
    override func tearDown() async throws { container = nil }

    func testANewBoardIsDailyAtFour() {
        let draft = SwitchboardDraft()
        XCTAssertEqual(draft.cadence, .daily)
        XCTAssertEqual(draft.resetTime, PickerTime(hour: 4, minute: 0))
        XCTAssertEqual(draft.resetWeekday, 0)
        XCTAssertFalse(draft.overdueBecomesTask)
        XCTAssertFalse(draft.canSave)
        XCTAssertFalse(draft.hasContent)
        XCTAssertTrue(SwitchboardDraft(name: "B").hasContent)
    }

    func testAddWritesTheBoard() throws {
        var draft = SwitchboardDraft(name: " Deep Clean ")
        draft.cadence = .weekly
        draft.resetTime = PickerTime(hour: 9, minute: 30)
        draft.resetWeekday = 7
        draft.overdueBecomesTask = true
        let board = try XCTUnwrap(try draft.save(editing: nil, in: context))
        XCTAssertEqual(board.name, "Deep Clean")
        XCTAssertEqual(board.cadenceValue, .weekly)
        XCTAssertEqual(board.resetMinutes, 570)
        XCTAssertEqual(board.resetWeekday, 7)
        XCTAssertTrue(board.overdueBecomesTask)
        XCTAssertNil(try SwitchboardDraft(name: "  ").save(editing: nil, in: context))
    }

    func testEditingStartsFilledInAndSaves() throws {
        let board = try Flipboard.createSwitchboard(name: "Before Bed", in: context)
        var draft = SwitchboardDraft(board)
        XCTAssertFalse(draft.hasContent)
        draft.resetWeekday = 3
        XCTAssertFalse(draft.hasContent, "a daily board's reset day is nothing to lose")
        draft.resetTime = PickerTime(hour: 5, minute: 0)
        XCTAssertTrue(draft.hasContent)
        try draft.save(editing: board, in: context)
        XCTAssertEqual(board.resetMinutes, 300)
    }

    func testTheCadenceLine() {
        XCTAssertEqual(SwitchboardDraft.cadenceLine(cadence: .daily, resetMinutes: 240, resetWeekday: 0, weekStart: 2,
                                                    calendar: utc, locale: british), "Daily · resets 04:00")
        XCTAssertEqual(SwitchboardDraft.cadenceLine(cadence: .weekly, resetMinutes: 240, resetWeekday: 0, weekStart: 2,
                                                    calendar: utc, locale: british), "Weekly · resets Monday 04:00")
        XCTAssertEqual(SwitchboardDraft.cadenceLine(cadence: .weekly, resetMinutes: 9 * 60, resetWeekday: 7, weekStart: 2,
                                                    calendar: utc, locale: british), "Weekly · resets Saturday 09:00")
    }

    func testTheWeekdayChoicesStartFromTheWeekStart() {
        var cal = utc
        cal.locale = british
        let choices = SwitchboardDraft.weekdayChoices(weekStart: 2, calendar: cal)
        XCTAssertEqual(choices.map(\.value), [0, 2, 3, 4, 5, 6, 7, 1])
        XCTAssertEqual(choices.first?.title, "Week start (Monday)")
        XCTAssertEqual(choices.last?.title, "Sunday")
    }

    func testTheDoneCount() throws {
        let board = try Flipboard.createSwitchboard(name: "Before Bed", in: context)
        let floss = try Flipboard.createSwitch(title: "Floss", rule: .daily, board: board, in: context)
        _ = try Flipboard.createSwitch(title: "Stretch", rule: .daily, board: board, in: context)
        Flipboard.flip(floss, in: context)
        XCTAssertEqual(SwitchboardDraft.doneCount(board.switches ?? [], now: Date()), "1 of 2")
    }
}
