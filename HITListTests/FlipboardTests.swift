import XCTest
import SwiftData
import SwiftUI
import HITListCore
@testable import HITList

/// The Flipboard's pure rules (fixed UTC calendar and dates) and its model actions (in-memory store;
/// these run on `Calendar.current` and `Date()` like `TaskActions`, so expectations use the same).
@MainActor
final class FlipboardTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1
        return cal
    }()
    private var utc: Calendar { Self.utc }
    private let cal = Calendar.current

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    /// 2026-month-day at hour:00 UTC.
    private func day(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private var today: Date { cal.startOfDay(for: Date()) }
    private func daysFromToday(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }

    private let every3Days = RecurrenceRule(frequency: .daily, interval: 3)

    // MARK: Membership

    func testMembershipNeedsRepeatOpenAndLabel() {
        let weekly = RecurrenceRule.weekly.encoded
        XCTAssertTrue(Flipboard.isMember(recurrence: weekly, isCompleted: false, labelNames: ["flipboard"]))
        XCTAssertTrue(Flipboard.isMember(recurrence: weekly, isCompleted: false, labelNames: ["home", "FlipBoard"]),
                      "label match ignores case")
        XCTAssertFalse(Flipboard.isMember(recurrence: weekly, isCompleted: false, labelNames: ["home"]))
        XCTAssertFalse(Flipboard.isMember(recurrence: nil, isCompleted: false, labelNames: ["flipboard"]))
        XCTAssertFalse(Flipboard.isMember(recurrence: "garbage", isCompleted: false, labelNames: ["flipboard"]))
        XCTAssertFalse(Flipboard.isMember(recurrence: weekly, isCompleted: true, labelNames: ["flipboard"]))
    }

    /// Brief 72: a switch may have a time ("Take meds 21:00"); the membership rule no longer asks for none.
    func testATimedSwitchIsOnTheBoard() throws {
        let meds = try Flipboard.createSwitch(title: "Take meds", rule: .daily, in: context)
        meds.dueDate = cal.date(bySettingHour: 21, minute: 0, second: 0, of: Date())
        meds.hasDueTime = true
        XCTAssertTrue(Flipboard.isMember(meds))
    }

    // MARK: Sides

    func testSideFromDates() {
        let now = day(10, 28, 15)
        XCTAssertEqual(Flipboard.side(due: day(10, 29), now: now, calendar: utc), .green, "due tomorrow")
        XCTAssertEqual(Flipboard.side(due: day(10, 28), now: now, calendar: utc), .red, "due today")
        XCTAssertEqual(Flipboard.side(due: day(10, 28, 23), now: now, calendar: utc), .red, "later today is still today")
        XCTAssertEqual(Flipboard.side(due: day(10, 20), now: now, calendar: utc), .red, "overdue")
        XCTAssertEqual(Flipboard.side(due: nil, now: now, calendar: utc), .red, "never flipped")
    }

    func testOverdueOnlyAfterTheDueDay() {
        let now = day(10, 28, 15)
        XCTAssertFalse(Flipboard.isOverdue(due: day(10, 28), now: now, calendar: utc))
        XCTAssertTrue(Flipboard.isOverdue(due: day(10, 27), now: now, calendar: utc))
        XCTAssertFalse(Flipboard.isOverdue(due: nil, now: now, calendar: utc))
        XCTAssertEqual(Flipboard.daysOverdue(due: day(10, 25), now: now, calendar: utc), 3)
        XCTAssertEqual(Flipboard.daysOverdue(due: day(10, 30), now: now, calendar: utc), 0)
    }

    // MARK: Interval extraction

    func testIntervalDaysForDailyEveryNAndWeeklyRules() {
        let due = day(10, 28) // a Wednesday
        XCTAssertEqual(Flipboard.intervalDays(due: due, rule: .daily, calendar: utc), 1)
        XCTAssertEqual(Flipboard.intervalDays(due: due, rule: every3Days, calendar: utc), 3)
        XCTAssertEqual(Flipboard.intervalDays(due: due, rule: .weekly, calendar: utc), 7)
        XCTAssertEqual(Flipboard.intervalDays(due: due, rule: RecurrenceRule(frequency: .weekly, interval: 2), calendar: utc), 14)
        XCTAssertEqual(Flipboard.intervalDays(due: due, rule: .monthly, calendar: utc), 30, "Sep 28 to Oct 28")
    }

    func testIntervalStartForWeekdayRuleIsThePreviousChosenDay() {
        let monWedFri = RecurrenceRule(frequency: .weekly, weekdays: [2, 4, 6])
        XCTAssertEqual(Flipboard.intervalStart(due: day(10, 28), rule: monWedFri, calendar: utc), day(10, 26), "Wed ← Mon")
        XCTAssertEqual(Flipboard.intervalStart(due: day(10, 26), rule: monWedFri, calendar: utc), day(10, 23), "Mon ← Fri")
        XCTAssertEqual(Flipboard.intervalDays(due: day(10, 26), rule: monWedFri, calendar: utc), 3)
    }

    // MARK: The light bar

    func testElapsedFractionIsClamped() {
        let due = day(10, 31) // every 3 days: the interval runs Oct 28 → Oct 31
        XCTAssertEqual(Flipboard.elapsedFraction(due: due, rule: every3Days, now: day(10, 28), calendar: utc), 0, accuracy: 1e-9)
        XCTAssertEqual(Flipboard.elapsedFraction(due: due, rule: every3Days, now: day(10, 29, 12), calendar: utc), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Flipboard.elapsedFraction(due: due, rule: every3Days, now: day(10, 31), calendar: utc), 1, accuracy: 1e-9)
        XCTAssertEqual(Flipboard.elapsedFraction(due: due, rule: every3Days, now: day(11, 9), calendar: utc), 1, "overdue clamps to 1")
        XCTAssertEqual(Flipboard.elapsedFraction(due: due, rule: every3Days, now: day(10, 1), calendar: utc), 0, "before the interval clamps to 0")
        XCTAssertEqual(Flipboard.elapsedFraction(due: nil, rule: every3Days, now: day(10, 28), calendar: utc), 1)
    }

    func testElapsedDaysReadsTwoOfThree() {
        let due = day(10, 31)
        XCTAssertEqual(Flipboard.elapsedDays(due: due, rule: every3Days, now: day(10, 28, 9), calendar: utc), 0)
        XCTAssertEqual(Flipboard.elapsedDays(due: due, rule: every3Days, now: day(10, 30, 9), calendar: utc), 2)
        XCTAssertEqual(Flipboard.elapsedDays(due: due, rule: every3Days, now: day(11, 15), calendar: utc), 3, "clamped to the interval")
    }

    // MARK: Order

    func testRedFirstMostOverdueOnTopThenGreenBySoonest() {
        let items: [(due: Date?, title: String)] = [
            (day(11, 4), "Call grandma"),
            (day(10, 28), "Floss"),        // due today
            (day(10, 30), "Shave"),
            (day(10, 20), "Water plants"), // most overdue
            (nil, "New"),                  // never flipped
            (day(10, 30), "Bins"),         // same day as Shave
        ]
        let sorted = items.sorted { Flipboard.isOrderedBefore($0, $1, calendar: utc) }.map(\.title)
        XCTAssertEqual(sorted, ["New", "Water plants", "Floss", "Bins", "Shave", "Call grandma"])
    }

    // MARK: Layout

    func testColumnCount() {
        XCTAssertEqual(FlipboardLayout.columnCount(width: 361, compact: true, spacing: 14), 2)
        XCTAssertEqual(FlipboardLayout.columnCount(width: 300, compact: false, spacing: 14), 3, "never fewer than 3 on Mac/iPad")
        XCTAssertEqual(FlipboardLayout.columnCount(width: 700, compact: false, spacing: 14), 4)
        XCTAssertEqual(FlipboardLayout.columnCount(width: 2000, compact: false, spacing: 14), 5, "never more than 5")
    }

    func testFlipIntervalRoundTrip() {
        XCTAssertEqual(FlipInterval(every3Days), FlipInterval(count: 3, unit: .days))
        XCTAssertEqual(FlipInterval(RecurrenceRule(frequency: .weekly, interval: 2))?.rule, RecurrenceRule(frequency: .weekly, interval: 2))
        // Brief 69: the card's quick choices include Monthly, so months are an interval the card shows.
        XCTAssertEqual(FlipInterval(.monthly), FlipInterval(count: 1, unit: .months))
        XCTAssertEqual(FlipInterval(RecurrenceRule(frequency: .monthly, interval: 2, anchorDay: 31))?.rule,
                       RecurrenceRule(frequency: .monthly, interval: 2))
        XCTAssertNil(FlipInterval(.weekdays))
        XCTAssertNil(FlipInterval(.yearly))
    }

    // MARK: Flipping (model)

    /// A switch due on `due`. `add` would move a past due date to today, so it is set again afterwards.
    private func switchTask(_ title: String = "Shave", due: Date?, rule: RecurrenceRule? = nil) throws -> TaskItem {
        let task = TaskItem(title: title, dueDate: due, recurrence: rule ?? every3Days)
        context.insert(task)
        try Flipboard.add(task, in: context)
        task.dueDate = due
        return task
    }

    func testFlipOnOverdueTaskLandsInTheFuture() throws {
        let task = try switchTask(due: daysFromToday(-2))
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .red)
        Flipboard.flip(task, in: context)
        XCTAssertGreaterThan(task.dueDate!, today)
        XCTAssertEqual(task.dueDate, daysFromToday(3), "a flip restarts the interval from today, not from the old due date")
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .green)
        XCTAssertFalse(task.isCompleted, "a switch rolls forward instead of completing")
        XCTAssertTrue(Flipboard.isMember(task))
    }

    func testFlipOfLongOverdueSwitchRestartsFromToday() throws {
        // toggleCompletion alone would give today (-3 + 3) and leave the switch red.
        let task = try switchTask(due: daysFromToday(-3))
        Flipboard.flip(task, in: context)
        XCTAssertEqual(task.dueDate, daysFromToday(3))
    }

    func testFlipDueTodayResetsAFullInterval() throws {
        let task = try switchTask(due: today)
        Flipboard.flip(task, in: context)
        XCTAssertEqual(task.dueDate, daysFromToday(3))
    }

    func testEarlyFlipOfGreenSwitchRestartsFromToday() throws {
        let task = try switchTask("Water plants", due: daysFromToday(4), rule: .weekly)
        Flipboard.flip(task, in: context)
        XCTAssertEqual(task.dueDate, daysFromToday(7), "watering early restarts the week from today")
    }

    func testFlipWithoutDueDateStartsTheSchedule() throws {
        let task = try switchTask(due: nil)
        task.dueDate = nil
        Flipboard.flip(task, in: context)
        XCTAssertEqual(task.dueDate, daysFromToday(3))
        XCTAssertFalse(task.isCompleted, "toggleCompletion would complete a dateless recurring task")
    }

    func testDueAfterFlipMatchesFlip() throws {
        for offset in [-10, -3, -2, -1, 0, 1, 2] {
            let task = try switchTask("t\(offset)", due: daysFromToday(offset))
            let expected = Flipboard.dueAfterFlip(due: task.dueDate, rule: every3Days, now: Date())
            Flipboard.flip(task, in: context)
            XCTAssertEqual(task.dueDate, expected, "offset \(offset)")
        }
    }

    // MARK: Joining and leaving

    func testAddCreatesLabelWithStableIdAndFillsInWhatASwitchNeeds() throws {
        let timed = cal.date(bySettingHour: 9, minute: 30, second: 0, of: daysFromToday(2))!
        let task = TaskItem(title: "Trim beard", dueDate: timed, hasDueTime: true)
        context.insert(task)
        try Flipboard.add(task, in: context)

        XCTAssertTrue(Flipboard.isMember(task))
        XCTAssertEqual(task.recurrenceRule, Flipboard.defaultRule)
        XCTAssertTrue(task.hasDueTime, "brief 72: a switch keeps its time of day")
        XCTAssertEqual(task.dueDate, timed)
        XCTAssertEqual(task.recurrenceRule?.time, RecurrenceRule.TimeOfDay(hour: 9, minute: 30))
        let labels = try context.fetch(FetchDescriptor<TaskLabel>())
        XCTAssertEqual(labels.map(\.id), [Flipboard.labelID])
        XCTAssertEqual(Flipboard.labelID, SeedIdentity.uuid(for: "TaskLabel/flipboard"))

        let other = TaskItem(title: "Floss", recurrence: .daily)
        context.insert(other)
        try Flipboard.add(other, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskLabel>()).count, 1, "the label is reused")
        XCTAssertEqual(other.dueDate, today, "a dateless task joins red, due today")
        XCTAssertEqual(Flipboard.side(due: other.dueDate, now: Date()), .red)
        XCTAssertFalse(Flipboard.hasStarted(other))
    }

    func testAddMovesAPastDueDateToTodayAndKeepsAFutureOne() throws {
        let overdue = TaskItem(title: "Bins", dueDate: daysFromToday(-5), recurrence: .weekly)
        let future = TaskItem(title: "Water plants", dueDate: daysFromToday(4), recurrence: .weekly)
        context.insert(overdue)
        context.insert(future)
        try Flipboard.add(overdue, in: context)
        try Flipboard.add(future, in: context)
        XCTAssertEqual(overdue.dueDate, today)
        XCTAssertEqual(Flipboard.side(due: overdue.dueDate, now: Date()), .red)
        XCTAssertEqual(future.dueDate, daysFromToday(4))
        XCTAssertEqual(Flipboard.side(due: future.dueDate, now: Date()), .green)
        XCTAssertTrue(Flipboard.hasStarted(future), "a switch due in the future is running")
    }

    func testAddReusesAnExistingLabelByName() throws {
        let existing = TaskLabel(name: "Flipboard")
        context.insert(existing)
        try context.save()
        let task = try switchTask(due: today)
        XCTAssertEqual(task.labels?.map(\.id), [existing.id])
    }

    func testRemoveKeepsTheRepeat() throws {
        let task = try switchTask(due: daysFromToday(1))
        Flipboard.remove(task, in: context)
        XCTAssertFalse(Flipboard.isMember(task))
        XCTAssertEqual(task.recurrenceRule, every3Days)
        XCTAssertEqual(task.dueDate, daysFromToday(1))
    }

    func testCreateSwitchStartsRed() throws {
        let task = try Flipboard.createSwitch(title: "Shave", rule: every3Days, in: context)
        XCTAssertTrue(Flipboard.isMember(task))
        XCTAssertEqual(task.dueDate, today)
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .red)
        XCTAssertFalse(Flipboard.hasStarted(task))
        XCTAssertEqual(Flipboard.caption(due: task.dueDate, rule: every3Days, started: false, now: Date()), "Flip to start")
    }

    /// George's example: "Shave" every two weeks starts red, a flip makes it green for 14 days, then it
    /// is red until shaved again.
    func testTwoWeekSwitchStartsRedFlipsGreenAndTurnsRedAfterTwoWeeks() throws {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2)
        let now = Date()
        let task = try Flipboard.createSwitch(title: "Shave", rule: rule, in: context, now: now)
        func caption(at date: Date) -> String {
            Flipboard.caption(due: task.dueDate, rule: rule, started: Flipboard.hasStarted(task), now: date)
        }

        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: now), .red)
        XCTAssertEqual(caption(at: now), "Flip to start")

        Flipboard.flip(task, in: context, now: now)
        XCTAssertEqual(task.dueDate, daysFromToday(14))
        XCTAssertTrue(Flipboard.hasStarted(task))
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: now), .green)
        XCTAssertEqual(caption(at: now), "0 of 14 days")
        XCTAssertEqual(Flipboard.elapsedFraction(due: task.dueDate, rule: rule, now: today), 0, accuracy: 1e-9)

        let day13 = cal.date(byAdding: .day, value: 13, to: now)!
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: day13), .green)
        XCTAssertEqual(caption(at: day13), "13 of 14 days")

        let day14 = cal.date(byAdding: .day, value: 14, to: now)!
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: day14), .red)
        XCTAssertEqual(caption(at: day14), "Due today")
        XCTAssertEqual(Flipboard.elapsedFraction(due: task.dueDate, rule: rule, now: day14), 1, accuracy: 1e-9)

        let day15 = cal.date(byAdding: .day, value: 15, to: now)!
        XCTAssertEqual(caption(at: day15), "1 day overdue")
    }

    func testCaptionForSwitchWithoutDueDate() {
        XCTAssertEqual(Flipboard.caption(due: nil, rule: every3Days, started: true, now: day(10, 28), calendar: utc), "Flip to start")
    }

    func testHasStartedComparesDueDayWithCreationDay() {
        XCTAssertFalse(Flipboard.hasStarted(due: day(10, 28), createdAt: day(10, 28, 15), calendar: utc), "created and due today")
        XCTAssertTrue(Flipboard.hasStarted(due: day(10, 31), createdAt: day(10, 28, 15), calendar: utc))
        XCTAssertFalse(Flipboard.hasStarted(due: nil, createdAt: day(10, 28), calendar: utc))
    }

    func testSetRuleOnANewSwitchKeepsItRed() throws {
        let task = try Flipboard.createSwitch(title: "Shave", rule: every3Days, in: context)
        Flipboard.setRule(RecurrenceRule(frequency: .weekly, interval: 2), for: task, in: context)
        XCTAssertEqual(task.dueDate, today)
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .red)
    }

    func testSetRuleKeepsWhenTheIntervalBegan() throws {
        let task = try switchTask(due: daysFromToday(2)) // started yesterday
        Flipboard.setRule(RecurrenceRule(frequency: .daily, interval: 2), for: task, in: context)
        XCTAssertEqual(task.dueDate, daysFromToday(1))
        XCTAssertEqual(task.recurrenceRule, RecurrenceRule(frequency: .daily, interval: 2))
    }

    // MARK: Flipping back (plain switch)

    func testFlipBackTurnsAPlainSwitchRedOnItsFlipDay() throws {
        let task = try switchTask(due: today)
        Flipboard.flip(task, in: context)
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .green)
        Flipboard.flipBack(task, in: context)
        XCTAssertEqual(task.dueDate, today)
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .red)
        XCTAssertEqual(task.flipCount, 0)
        XCTAssertFalse(Flipboard.canFlipBack(Flipboard.Charge(task), target: 1, rule: every3Days, now: Date()),
                       "red with nothing counted: nothing to undo")
    }
}

/// Charging switches (`flipTarget` > 1) and the rules a plain switch now shares with them. Pure rules
/// run on a fixed UTC calendar; the model tests run on `Calendar.current` like `FlipboardTests`.
@MainActor
final class FlipboardRulesTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1
        return cal
    }()
    private var utc: Calendar { Self.utc }
    private let cal = Calendar.current

    override func setUp() async throws {
        container = ModelContainerFactory.preview()
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    /// 2026-month-day at hour:00 UTC. Oct 26 2026 is a Monday.
    private func day(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private var today: Date { cal.startOfDay(for: Date()) }
    private func daysFromToday(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }

    private let weekly = RecurrenceRule.weekly
    private typealias Charge = Flipboard.Charge

    private func flip(_ charge: Charge, target: Int = 3, rule: RecurrenceRule = .weekly, at now: Date)
        -> (charge: Charge, outcome: Flipboard.FlipOutcome) {
        Flipboard.afterFlip(charge, target: target, rule: rule, now: now, calendar: utc)
    }

    private func count(_ charge: Charge, target: Int = 3, rule: RecurrenceRule = .weekly, at now: Date) -> Int {
        Flipboard.effectiveCount(charge, target: target, rule: rule, now: now, calendar: utc)
    }

    private func side(_ charge: Charge, at now: Date) -> Flipboard.Side {
        Flipboard.side(due: charge.due, now: now, calendar: utc)
    }

    /// `started` defaults to "has a flip counted", as for a switch created today.
    private func caption(_ charge: Charge, target: Int = 3, rule: RecurrenceRule = .weekly, started: Bool? = nil,
                         at now: Date) -> String {
        let counted = count(charge, target: target, rule: rule, at: now)
        return Flipboard.caption(due: charge.due, rule: rule, started: started ?? (counted > 0), count: counted,
                                 target: target, now: now, calendar: utc)
    }

    /// "Gym 3 times this week": due Monday, flipped Tuesday, Wednesday and Thursday.
    private func chargedGym() -> Charge {
        let start = Charge(due: day(10, 26), count: 0, periodStart: nil)
        let one = flip(start, at: day(10, 27, 18)).charge
        let two = flip(one, at: day(10, 28, 18)).charge
        return flip(two, at: day(10, 29, 18)).charge
    }

    // MARK: Counting up and charging

    func testChargerCountsUpThenChargesAtTarget() {
        let start = Charge(due: day(10, 26), count: 0, periodStart: nil)
        XCTAssertEqual(count(start, at: day(10, 27, 9)), 0)

        let (one, first) = flip(start, at: day(10, 27, 18))
        XCTAssertEqual(first, .counted(1))
        XCTAssertEqual(one.due, day(10, 26), "a counting flip leaves the due date alone")
        XCTAssertEqual(one.periodStart, day(10, 27, 18), "the first flip of the interval sets periodStart")
        XCTAssertEqual(side(one, at: day(10, 27, 18)), .red)
        XCTAssertEqual(caption(one, at: day(10, 27, 18)), "1 of 3 this week")

        let (two, second) = flip(one, at: day(10, 28, 18))
        XCTAssertEqual(second, .counted(2))
        XCTAssertEqual(two.periodStart, day(10, 27, 18), "later flips keep the interval's start")
        XCTAssertEqual(caption(two, at: day(10, 28, 18)), "2 of 3 this week")
        XCTAssertTrue(Flipboard.isCharging(two, target: 3, rule: weekly, now: day(10, 28, 18), calendar: utc))

        let (three, third) = flip(two, at: day(10, 29, 18))
        XCTAssertEqual(third, .charged)
        XCTAssertEqual(three.due, Flipboard.dueAfterFlip(due: two.due, rule: weekly, now: day(10, 29, 18), calendar: utc),
                       "charging moves the due date exactly as a single flip does")
        XCTAssertEqual(three.due, day(11, 5))
        XCTAssertEqual(three.count, 3, "the count stays at the target so the lamps read full")
        XCTAssertEqual(side(three, at: day(10, 29, 18)), .green)
        XCTAssertEqual(count(three, at: day(10, 30)), 3)
        XCTAssertEqual(caption(three, at: day(10, 30)), "Done this week")
        XCTAssertFalse(Flipboard.isCharging(three, target: 3, rule: weekly, now: day(10, 30), calendar: utc))
    }

    func testExtraFlipsWhileChargedDoNothing() {
        let charged = chargedGym()
        let (after, outcome) = flip(charged, at: day(10, 31, 12))
        XCTAssertEqual(outcome, .ignored)
        XCTAssertEqual(after, charged)
    }

    func testFirstFlipOfADatelessChargerAnchorsItToday() {
        let (one, outcome) = flip(Charge(due: nil, count: 0, periodStart: nil), at: day(10, 27, 18))
        XCTAssertEqual(outcome, .counted(1))
        XCTAssertEqual(one.due, day(10, 27))
        XCTAssertEqual(count(one, at: day(10, 27, 20)), 1)
    }

    // MARK: The interval boundary

    func testCountIsStaleOnceTheNextIntervalArrives() {
        let charged = chargedGym()
        XCTAssertEqual(side(charged, at: day(11, 4, 23)), .green)
        XCTAssertEqual(count(charged, at: day(11, 4, 23)), 3)

        // Thursday Nov 5: red again by the date rule, and the old count reads as 0.
        XCTAssertEqual(side(charged, at: day(11, 5, 8)), .red)
        XCTAssertTrue(Flipboard.isStale(periodStart: charged.periodStart, due: charged.due, rule: weekly, now: day(11, 5, 8), calendar: utc))
        XCTAssertEqual(count(charged, at: day(11, 5, 8)), 0)
        XCTAssertEqual(caption(charged, started: true, at: day(11, 5, 8)), "0 of 3 this week")
        XCTAssertEqual(charged.count, 3, "the stored count is only reset by the next flip")

        let (one, outcome) = flip(charged, at: day(11, 6, 7))
        XCTAssertEqual(outcome, .counted(1), "the next flip starts counting afresh")
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one.periodStart, day(11, 6, 7))
        XCTAssertEqual(one.due, day(11, 5))
    }

    func testAnOverdueChargerCountsOnlyTheCurrentIntervalsFlips() {
        // Due Monday Oct 19, two flips on Tuesday Oct 20, then nothing.
        let charging = Charge(due: day(10, 19), count: 2, periodStart: day(10, 20, 18))
        XCTAssertEqual(Flipboard.countingIntervalStart(due: charging.due, rule: weekly, now: day(10, 25), calendar: utc), day(10, 19))
        XCTAssertEqual(count(charging, at: day(10, 25, 12)), 2, "still the week of Oct 19")
        XCTAssertEqual(Flipboard.countingIntervalStart(due: charging.due, rule: weekly, now: day(10, 27), calendar: utc), day(10, 26))
        XCTAssertEqual(count(charging, at: day(10, 27, 12)), 0, "a new week: last week's flips no longer count")
    }

    // MARK: Flipping back

    func testFlipBackWhileChargingTakesOneFlipOff() {
        let two = Charge(due: day(10, 26), count: 2, periodStart: day(10, 27, 18))
        let one = Flipboard.afterFlipBack(two, target: 3, rule: weekly, now: day(10, 28, 20), calendar: utc)
        XCTAssertEqual(one, Charge(due: day(10, 26), count: 1, periodStart: day(10, 27, 18)))
        let zero = Flipboard.afterFlipBack(one!, target: 3, rule: weekly, now: day(10, 28, 20), calendar: utc)
        XCTAssertEqual(zero, Charge(due: day(10, 26), count: 0, periodStart: nil))
        XCTAssertNil(Flipboard.afterFlipBack(zero!, target: 3, rule: weekly, now: day(10, 28, 20), calendar: utc),
                     "red and uncharged: nothing to undo")
        XCTAssertFalse(Flipboard.canFlipBack(zero!, target: 3, rule: weekly, now: day(10, 28, 20), calendar: utc))
    }

    func testFlipBackOfAChargedSwitchKeepsTheEarlierFlips() {
        let charged = chargedGym()
        let back = Flipboard.afterFlipBack(charged, target: 3, rule: weekly, now: day(10, 29, 19), calendar: utc)!
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back.due, day(10, 27), "due no later than the day the first flip was counted")
        XCTAssertEqual(side(back, at: day(10, 29, 19)), .red)
        XCTAssertEqual(count(back, at: day(10, 29, 19)), 2, "the earlier flips are not stale")
        XCTAssertEqual(caption(back, at: day(10, 29, 19)), "2 of 3 this week")

        // Flipping again charges it again.
        XCTAssertEqual(flip(back, at: day(10, 29, 20)).outcome, .charged)
    }

    func testFlipBackOfAChargerThatJoinedGreenCountsNothing() {
        // "Add to Flipboard" with a future due date: green, never flipped.
        let joined = Charge(due: day(10, 30), count: 0, periodStart: nil)
        let back = Flipboard.afterFlipBack(joined, target: 3, rule: weekly, now: day(10, 27, 12), calendar: utc)!
        XCTAssertEqual(back.count, 0)
        XCTAssertEqual(side(back, at: day(10, 27, 12)), .red)
    }

    // MARK: Mark done and target changes

    func testMarkDoneChargesAtOnce() {
        let one = Charge(due: day(10, 26), count: 1, periodStart: day(10, 27, 18))
        let (done, outcome) = Flipboard.afterMarkDone(one, target: 3, rule: weekly, now: day(10, 28, 9), calendar: utc)
        XCTAssertEqual(outcome, .charged)
        XCTAssertEqual(done.count, 3)
        XCTAssertEqual(done.due, day(11, 4))
        XCTAssertEqual(done.periodStart, day(10, 27, 18))
        XCTAssertEqual(Flipboard.afterMarkDone(done, target: 3, rule: weekly, now: day(10, 29), calendar: utc).outcome, .ignored)
    }

    func testTargetChanges() {
        let two = Charge(due: day(10, 26), count: 2, periodStart: day(10, 27, 18))
        let lowered = Flipboard.afterTargetChange(two, from: 3, to: 2, rule: weekly, now: day(10, 28, 20), calendar: utc)
        XCTAssertEqual(lowered.count, 2)
        XCTAssertEqual(side(lowered, at: day(10, 28, 20)), .green, "2 flips already meet a target of 2")

        let raised = Flipboard.afterTargetChange(two, from: 3, to: 5, rule: weekly, now: day(10, 28, 20), calendar: utc)
        XCTAssertEqual(raised, two, "the count carries over")
        XCTAssertEqual(count(raised, target: 5, at: day(10, 28, 20)), 2)

        let charged = chargedGym()
        let fuller = Flipboard.afterTargetChange(charged, from: 3, to: 5, rule: weekly, now: day(10, 30), calendar: utc)
        XCTAssertEqual(fuller.count, 5, "a full charger stays full")
        XCTAssertEqual(fuller.due, charged.due)

        XCTAssertEqual(Flipboard.clampedTarget(0), 1)
        XCTAssertEqual(Flipboard.clampedTarget(42), Flipboard.maxFlipTarget)
        XCTAssertEqual(Flipboard.maxFlipTarget, 10)
    }

    // MARK: A plain switch is unchanged

    func testTargetOneBehavesExactlyAsBefore() {
        let rule = RecurrenceRule(frequency: .daily, interval: 3)
        let now = day(10, 28, 15)
        for offset in [-10, -3, -1, 0] {
            let due = utc.date(byAdding: .day, value: offset, to: day(10, 28))!
            let (after, outcome) = flip(Charge(due: due, count: 0, periodStart: nil), target: 1, rule: rule, at: now)
            XCTAssertEqual(outcome, .charged, "offset \(offset)")
            XCTAssertEqual(after.due, Flipboard.dueAfterFlip(due: due, rule: rule, now: now, calendar: utc), "offset \(offset)")
            XCTAssertEqual(after.due, day(10, 31))
        }
        // Green: flipped early, the interval restarts from today.
        let (early, outcome) = flip(Charge(due: day(10, 30), count: 1, periodStart: day(10, 27)), target: 1, rule: rule, at: now)
        XCTAssertEqual(outcome, .charged)
        XCTAssertEqual(early.due, day(10, 31))
        // Captions are the plain ones.
        let green = Charge(due: day(10, 31), count: 1, periodStart: now)
        XCTAssertEqual(Flipboard.caption(due: green.due, rule: rule, started: true, count: 1, target: 1, now: day(10, 29, 9), calendar: utc),
                       Flipboard.caption(due: green.due, rule: rule, started: true, now: day(10, 29, 9), calendar: utc))
        XCTAssertEqual(count(green, target: 1, rule: rule, at: day(10, 29)), 1)
        XCTAssertEqual(count(Charge(due: day(10, 28), count: 0, periodStart: nil), target: 1, rule: rule, at: now), 0)
    }

    // MARK: Order

    func testChargingSwitchesSortWithRed() {
        let items: [(due: Date?, title: String, charge: Charge)] = [
            (day(10, 30), "Water plants", Charge(due: day(10, 30), count: 1, periodStart: day(10, 27))),  // green
            (day(10, 28), "Floss", Charge(due: day(10, 28), count: 0, periodStart: nil)),                    // red, due today
            (day(10, 26), "Gym", Charge(due: day(10, 26), count: 2, periodStart: day(10, 27))),             // charging
            (day(11, 5), "Charged", chargedGym()),                                                          // charged: green
        ]
        let now = day(10, 28, 15)
        let sorted = items.sorted { Flipboard.isOrderedBefore(($0.due, $0.title), ($1.due, $1.title), calendar: utc) }
        XCTAssertEqual(sorted.map(\.title), ["Gym", "Floss", "Water plants", "Charged"])
        let sides = sorted.map { Flipboard.side(due: $0.due, now: now, calendar: utc) }
        XCTAssertEqual(sides, [.red, .red, .green, .green], "the charging switch sits with the red ones")
        XCTAssertTrue(Flipboard.isCharging(sorted[0].charge, target: 3, rule: weekly, now: now, calendar: utc))
    }

    // MARK: Captions and the drain

    func testPeriodPhrases() {
        XCTAssertEqual(Flipboard.periodPhrase(.weekly), "this week")
        XCTAssertEqual(Flipboard.periodPhrase(.daily), "today")
        XCTAssertEqual(Flipboard.periodPhrase(RecurrenceRule(frequency: .weekly, interval: 2)), "these 2 weeks")
        XCTAssertEqual(Flipboard.periodPhrase(RecurrenceRule(frequency: .daily, interval: 3)), "these 3 days")
        XCTAssertEqual(Flipboard.periodPhrase(.monthly), "this month")
        XCTAssertEqual(Flipboard.periodPhrase(.weekdays), "this round")
        XCTAssertEqual(Flipboard.caption(due: day(10, 28), rule: .daily, started: true, count: 1, target: 2,
                                         now: day(10, 28, 9), calendar: utc), "1 of 2 today")
        XCTAssertEqual(Flipboard.caption(due: day(10, 28), rule: .weekly, started: false, count: 0, target: 3,
                                         now: day(10, 28, 9), calendar: utc), "Flip to start")
    }

    func testDrainPlaysOnceForTheIntervalThatWasShownFull() {
        let charged = chargedGym()
        // The board showed it full for the interval ending Nov 5; on Nov 5 it is red with nothing counted.
        XCTAssertTrue(Flipboard.shouldDrain(recordedDue: charged.due, due: charged.due, count: 0, now: day(11, 5, 8), calendar: utc))
        XCTAssertFalse(Flipboard.shouldDrain(recordedDue: charged.due, due: charged.due, count: 3, now: day(11, 1), calendar: utc),
                       "still green")
        XCTAssertFalse(Flipboard.shouldDrain(recordedDue: day(10, 29), due: charged.due, count: 0, now: day(11, 5, 8), calendar: utc),
                       "shown full for another interval (flipped back since)")
        XCTAssertFalse(Flipboard.shouldDrain(recordedDue: nil, due: charged.due, count: 0, now: day(11, 5, 8), calendar: utc))
        XCTAssertFalse(Flipboard.shouldDrain(recordedDue: charged.due, due: charged.due, count: 1, now: day(11, 6), calendar: utc),
                       "already counting the new interval")
    }

    // MARK: Model

    func testChargerOnTheModel() throws {
        let task = try Flipboard.createSwitch(title: "Gym", rule: weekly, flipTarget: 3, in: context)
        XCTAssertEqual(task.flipTarget, 3)
        XCTAssertTrue(Flipboard.isMember(task))
        XCTAssertFalse(Flipboard.hasStarted(task))

        XCTAssertEqual(Flipboard.flip(task, in: context), .counted(1))
        XCTAssertEqual(task.flipCount, 1)
        XCTAssertNotNil(task.flipPeriodStart)
        XCTAssertEqual(task.dueDate, today, "still red, still due today")
        XCTAssertTrue(Flipboard.hasStarted(task), "a counted flip starts a charger")
        XCTAssertFalse(task.isCompleted)

        XCTAssertEqual(Flipboard.flip(task, in: context), .counted(2))
        XCTAssertEqual(Flipboard.flip(task, in: context), .charged)
        XCTAssertEqual(task.dueDate, daysFromToday(7))
        XCTAssertEqual(task.flipCount, 3)
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .green)
        XCTAssertFalse(task.isCompleted, "a charger rolls forward instead of completing")
        XCTAssertEqual(Flipboard.flip(task, in: context), .ignored)
        XCTAssertEqual(task.dueDate, daysFromToday(7))

        Flipboard.flipBack(task, in: context)
        XCTAssertEqual(task.flipCount, 2)
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .red)
        XCTAssertEqual(Flipboard.effectiveCount(task), 2)

        // Editing the interval of a red charger leaves its due date (and count) alone.
        let due = task.dueDate
        Flipboard.setRule(RecurrenceRule(frequency: .weekly, interval: 2), for: task, in: context)
        XCTAssertEqual(task.dueDate, due)
        XCTAssertEqual(Flipboard.effectiveCount(task), 2)

        Flipboard.setTarget(2, for: task, in: context)
        XCTAssertEqual(task.flipTarget, 2)
        XCTAssertEqual(Flipboard.side(due: task.dueDate, now: Date()), .green, "2 flips meet the new target")
        Flipboard.setTarget(99, for: task, in: context)
        XCTAssertEqual(task.flipTarget, Flipboard.maxFlipTarget)
    }

    func testMarkDoneOnTheModel() throws {
        let task = try Flipboard.createSwitch(title: "Gym", rule: weekly, flipTarget: 4, in: context)
        XCTAssertEqual(Flipboard.markDone(task, in: context), .charged)
        XCTAssertEqual(task.flipCount, 4)
        XCTAssertEqual(task.dueDate, daysFromToday(7))
    }

    func testCreateSwitchDefaultsToOneFlip() throws {
        let task = try Flipboard.createSwitch(title: "Shave", rule: weekly, in: context)
        XCTAssertEqual(task.flipTarget, 1)
        XCTAssertEqual(Flipboard.flip(task, in: context), .charged)
        XCTAssertEqual(task.dueDate, daysFromToday(7))
    }
}

/// Brief 59: the lists the app builds itself (Upcoming, the board, the Duo, Spotlight, Siri, Claude) follow
/// `FlipboardSwitch.listing`: a switch is on the Flipboard only (brief 72), green or red, unless it opted in ("Overdue
/// becomes task"); an opted-in red one is a task for today.
@MainActor
final class FlipboardListingAppTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private func daysFromToday(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }

    override func setUp() async throws { container = ModelContainerFactory.preview() }
    override func tearDown() async throws { container = nil }

    private func plain(_ title: String, due: Date?, switch isSwitch: Bool = false) -> PlainTask {
        PlainTask(title: title, dueDate: due, labelNames: isSwitch ? ["flipboard"] : [], isRecurring: isSwitch)
    }

    /// A green switch (flipped today, due in two weeks) and a red one (three days overdue), both opted in unless
    /// `optedIn` is false.
    private func switches(optedIn: Bool = true) throws -> (green: TaskItem, red: TaskItem) {
        let green = try Flipboard.createSwitch(title: "Shave", rule: RecurrenceRule(frequency: .weekly, interval: 2), in: context)
        Flipboard.flip(green, in: context)
        let red = try Flipboard.createSwitch(title: "Water plants", rule: RecurrenceRule(frequency: .daily, interval: 3), in: context)
        red.dueDate = daysFromToday(-3)
        green.overdueBecomesTask = optedIn
        red.overdueBecomesTask = optedIn
        try context.save()
        XCTAssertEqual(Flipboard.side(due: green.dueDate, now: Date()), .green)
        XCTAssertEqual(Flipboard.side(due: red.dueDate, now: Date()), .red)
        return (green, red)
    }

    // MARK: Upcoming, the board, the Duo

    func testUpcomingShowsNoSwitchEitherSide() {
        let items = [plain("Shave", due: daysFromToday(2), switch: true), plain("Water", due: daysFromToday(-3), switch: true),
                     plain("Fresh", due: nil, switch: true), plain("Dentist", due: daysFromToday(2)),
                     plain("Call Sam", due: daysFromToday(-1)), plain("Groceries", due: today)]
        let schedule = UpcomingSchedule(items: items, now: Date(), dayCount: 7)
        XCTAssertEqual(schedule.overdue.map(\.filterTitle), ["Call Sam"])
        XCTAssertEqual(schedule.days.flatMap(\.items).map(\.filterTitle), ["Groceries", "Dentist"])
        let counts = UpcomingSchedule<PlainTask>.counts(of: items, now: Date())
        XCTAssertEqual(counts[daysFromToday(2)], 1, "the week strip's dots leave switches out too")
        XCTAssertNil(counts[daysFromToday(-3)])
    }

    func testTheBoardShowsNoSwitchEitherSide() {
        let items = [plain("Shave", due: daysFromToday(2), switch: true), plain("Water", due: daysFromToday(-3), switch: true),
                     plain("Dentist", due: daysFromToday(2)), plain("Call Sam", due: daysFromToday(-1))]
        let board = UpcomingBoardModel(items: items, window: UpcomingWindow(), now: Date(), showOverdue: true)
        XCTAssertEqual(board.columns.flatMap(\.items).map(\.filterTitle).sorted(), ["Call Sam", "Dentist"])
    }

    func testTheDuosNextDaysLeaveGreenSwitchesOut() {
        let items = [plain("Shave", due: daysFromToday(2), switch: true), plain("Dentist", due: daysFromToday(2))]
        let shown = DuoNextDays.listed(items, now: Date())
        XCTAssertEqual(DuoNextDays.group(shown, due: \.filterDueDate, now: Date()).flatMap(\.items).map(\.filterTitle),
                       ["Dentist"])
    }

    // MARK: The default (brief 72)

    func testByDefaultNoSwitchReachesSpotlightSiriOrShortcuts() throws {
        let (green, red) = try switches(optedIn: false)
        let plainTask = TaskItem(title: "Dentist", dueDate: daysFromToday(2))
        context.insert(plainTask)
        XCTAssertEqual(SpotlightSync.indexable([green, red, plainTask], now: Date()).map(\.title), ["Dentist"])
        XCTAssertEqual(try IntentActions.today(in: context).lines.map(\.title), [])
        XCTAssertEqual(try IntentActions.suggestedTasks(in: context).map(\.title), ["Dentist"])
        XCTAssertEqual(try IntentActions.openTasks(matching: "water", in: context).map(\.title), [])
        XCTAssertFalse(TaskOrdering.isInToday(red, now: Date()))
        XCTAssertFalse(TaskOrdering.isInInbox(red, now: Date()))
    }

    func testASwitchboardsOptInBringsItsSwitchesBack() throws {
        let (_, red) = try switches(optedIn: false)
        let board = Switchboard(name: "Chores")
        context.insert(board)
        red.switchboard = board
        try context.save()
        XCTAssertFalse(red.filterSwitchOptedIn)
        board.overdueBecomesTask = true
        XCTAssertTrue(red.filterSwitchOptedIn, "the board's toggle opts its switches in")
        XCTAssertEqual(red.filterSwitchboard, SwitchboardSchedule(cadence: .daily, resetMinutes: 240,
                                                                  resetWeekday: Preferences.weekStartWeekday()))
        XCTAssertTrue(TaskOrdering.isInToday(red, now: Date()), "never flipped since it joined: due")
    }

    // MARK: Spotlight

    func testSpotlightLeavesGreenSwitchesOutAndDescribesRedOnesWithoutADate() throws {
        let (green, red) = try switches()
        let plainTask = TaskItem(title: "Dentist", dueDate: daysFromToday(2))
        context.insert(plainTask)
        let indexed = SpotlightSync.indexable([green, red, plainTask], now: Date()).map(\.title)
        XCTAssertEqual(indexed, ["Water plants", "Dentist"])
        let line = try XCTUnwrap(TaskEntity(spotlight: red).attributeSet.contentDescription)
        XCTAssertEqual(line, "Flipboard switch · every 3 days", "no date: a red switch is today's every day")
        XCTAssertNotEqual(SpotlightRecord(red).fingerprint, SpotlightRecord(TaskItem(title: "Water plants")).fingerprint)
    }

    // MARK: Siri and Shortcuts

    func testSiriListsARedSwitchAsTodaysNotOverdue() throws {
        _ = try switches()
        let summary = try IntentActions.today(in: context)
        XCTAssertEqual(summary.lines.map(\.title), ["Water plants"])
        XCTAssertEqual(summary.lines.map(\.isOverdue), [false])
        XCTAssertEqual(summary.lines.map(\.when), [nil])
        XCTAssertEqual(summary.headline, "1 task today.")
    }

    func testShortcutsLeaveGreenSwitchesOut() throws {
        _ = try switches()
        XCTAssertEqual(try IntentActions.suggestedTasks(in: context).map(\.title), ["Water plants"])
        XCTAssertEqual(try IntentActions.openTasks(matching: "shave", in: context).map(\.title), [])
    }

    func testCompletingASwitchFromSiriFlipsIt() throws {
        let (_, red) = try switches()
        let dialog = try IntentActions.complete(red.id, in: context)
        XCTAssertEqual(red.dueDate, daysFromToday(3), "a flip restarts the interval from today")
        XCTAssertEqual(Flipboard.side(due: red.dueDate, now: Date()), .green)
        XCTAssertTrue(dialog.hasPrefix("Flipped ‘Water plants’."), dialog)
    }

    // MARK: Claude

    func testClaudeListsEverySwitchAndSaysWhichSide() throws {
        _ = try switches()
        let handler = ClaudeToolHandler(context: context, rule: ClaudeAccessRule(mode: .allExceptHidden))
        let result = handler.call(ClaudeTools.listTasks, [:])
        let json = try JSONValue.decode(Data(result.text.utf8))
        let tasks = try XCTUnwrap(json["tasks"]?.arrayValue)
        XCTAssertEqual(Set(tasks.compactMap { $0["title"]?.stringValue }), ["Shave", "Water plants"])
        let shave = try XCTUnwrap(tasks.first { $0["title"] == "Shave" })
        XCTAssertEqual(shave["flipboard_switch"], "green")
        let water = try XCTUnwrap(tasks.first { $0["title"] == "Water plants" })
        XCTAssertEqual(water["flipboard_switch"], "red")
        XCTAssertEqual(water["overdue_becomes_task"], true)
        XCTAssertNil(water["switchboard"], "a loose switch")
    }
}


/// Brief 59: a red switch's row in Today. Completing it is a flip; the toast says "Flipped"; Undo puts the
/// switch back exactly as it was. The row shows the switch glyph and no date.
@MainActor
final class FlipboardRowTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private func daysFromToday(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }

    override func setUp() async throws { container = ModelContainerFactory.preview() }
    override func tearDown() async throws { container = nil }

    /// A red switch in Today: three days overdue, with "Overdue becomes task" on (brief 72; off, it is on no list).
    private func redSwitch(_ title: String = "Water plants", target: Int = 1) throws -> TaskItem {
        let task = try Flipboard.createSwitch(title: title, rule: RecurrenceRule(frequency: .daily, interval: 3),
                                              flipTarget: target, in: context)
        task.dueDate = daysFromToday(-3)
        task.overdueBecomesTask = true
        try context.save()
        return task
    }

    func testCompletingARedSwitchsRowFlipsItGreenAndItLeavesToday() throws {
        let task = try redSwitch()
        XCTAssertTrue(TaskOrdering.isInToday(task, now: Date()))
        let record = Flipboard.completion(for: task)
        Flipboard.completeRow(task, in: context)
        XCTAssertFalse(task.isCompleted)
        XCTAssertEqual(task.dueDate, daysFromToday(3), "the interval restarts from today, not from the old due date")
        XCTAssertEqual(Flipboard.side(of: task), .green)
        XCTAssertFalse(TaskOrdering.isInToday(task, now: Date()))
        XCTAssertEqual(CompletionToastState.message(for: [record]), "Flipped ‘Water plants’")
    }

    func testUndoPutsTheSwitchBackExactly() throws {
        let task = try redSwitch()
        task.reminderDate = Date().addingTimeInterval(3600)
        let before = (task.dueDate, task.flipCount, task.flipPeriodStart, task.reminderDate, task.recurrence)
        let record = Flipboard.completion(for: task)
        Flipboard.completeRow(task, in: context)
        XCTAssertTrue(Flipboard.undo(record, on: task, in: context))
        XCTAssertEqual(task.dueDate, before.0)
        XCTAssertEqual(task.flipCount, before.1)
        XCTAssertEqual(task.flipPeriodStart, before.2)
        XCTAssertEqual(task.reminderDate, before.3)
        XCTAssertEqual(task.recurrence, before.4)
        XCTAssertEqual(Flipboard.side(of: task), .red)
    }

    func testACounterCountsOneFlipAndUndoTakesItBack() throws {
        let gym = try redSwitch("Gym", target: 3)
        let record = Flipboard.completion(for: gym)
        Flipboard.completeRow(gym, in: context)
        XCTAssertEqual(Flipboard.effectiveCount(gym), 1)
        XCTAssertEqual(Flipboard.side(of: gym), .red, "still Today's until it is charged")
        XCTAssertTrue(Flipboard.undo(record, on: gym, in: context))
        XCTAssertEqual(Flipboard.effectiveCount(gym), 0)
    }

    func testAnOrdinaryTaskStillCompletes() throws {
        let task = TaskItem(title: "Groceries", dueDate: today)
        context.insert(task)
        let record = Flipboard.completion(for: task)
        XCTAssertEqual(record.revert, .uncomplete)
        XCTAssertNil(record.flip)
        Flipboard.completeRow(task, in: context)
        XCTAssertTrue(task.isCompleted)
        XCTAssertFalse(Flipboard.undo(record, on: task, in: context), "not a flip: the list undoes it as before")
        let rent = TaskItem(title: "Rent", dueDate: daysFromToday(-1), recurrence: .monthly)
        context.insert(rent)
        XCTAssertEqual(Flipboard.completion(for: rent).revert, .restoreDueDate(daysFromToday(-1)))
    }

    func testTheToastSaysFlippedForFlipsAndCompletedOtherwise() throws {
        let flip = Flipboard.completion(for: try redSwitch("Shave"))
        let other = CompletedTask(id: UUID(), title: "Groceries", revert: .uncomplete)
        XCTAssertEqual(CompletionToastState.message(for: [flip]), "Flipped ‘Shave’")
        XCTAssertEqual(CompletionToastState.message(for: [flip, Flipboard.completion(for: try redSwitch("Floss"))]), "2 flipped")
        XCTAssertEqual(CompletionToastState.message(for: [flip, other]), "2 completed")
        XCTAssertEqual(CompletionToastState.message(for: [other]), "Completed ‘Groceries’")
        var state = CompletionToastState()
        _ = state.add(flip)
        XCTAssertEqual(state.message, "Flipped ‘Shave’")
    }

    func testTheRowShowsTheSwitchGlyphForARedSwitchOnly() throws {
        let red = try redSwitch()
        XCTAssertTrue(TaskRow.showsSwitch(red, now: Date(), completing: false))
        XCTAssertTrue(TaskRow.hasMeta(red, hidesDay: true, showProject: false), "Today's all-day rows keep the glyph")
        Flipboard.flip(red, in: context)
        XCTAssertFalse(TaskRow.showsSwitch(red, now: Date(), completing: false), "green: an ordinary repeating row")
        XCTAssertTrue(TaskRow.showsSwitch(red, now: Date(), completing: true), "while its flip animates out it keeps the glyph")
        let rent = TaskItem(title: "Rent", dueDate: daysFromToday(-1), recurrence: .monthly)
        context.insert(rent)
        XCTAssertFalse(TaskRow.showsSwitch(rent, now: Date(), completing: false))
    }
}

/// Brief 59: Delete removes a switch (and its sub-tasks) from the store at once; Undo brings it back as it
/// was; the Flipboard's query and Spotlight drop it with no relaunch.
@MainActor
final class FlipboardDeleteTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    override func setUp() async throws { container = ModelContainerFactory.preview() }
    override func tearDown() async throws { container = nil }

    /// The Flipboard's own query (`FlipboardView`): open recurring tasks that are members.
    private func board() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted && $0.recurrence != nil }))
            .filter(Flipboard.isMember)
    }

    private func gym() throws -> TaskItem {
        let home = Project(name: "Home")
        context.insert(home)
        let task = try Flipboard.createSwitch(title: "Gym", rule: RecurrenceRule(frequency: .weekly, interval: 1),
                                              flipTarget: 3, in: context)
        task.project = home
        task.notes = "Legs, then core"
        task.priority = 2
        Flipboard.flip(task, in: context)
        _ = try TaskActions.addSubtasks(["Shoes", "Towel"], to: task, in: context)
        task.orderedSubtasks.first?.isCompleted = true
        try context.save()
        return task
    }

    func testDeleteRemovesTheSwitchAndItsSubtasksAtOnce() throws {
        let task = try gym()
        XCTAssertEqual(try board().map(\.title), ["Gym"])
        _ = Flipboard.delete(task, in: context)
        XCTAssertEqual(try board(), [], "the board's query drops it")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0, "the switch and both sub-tasks are gone")
        XCTAssertFalse(context.hasChanges, "saved at once, so the delete goes to iCloud now")
    }

    func testUndoBringsTheSwitchBackAsItWas() throws {
        let task = try gym()
        let id = task.id, due = task.dueDate, created = task.createdAt
        let deleted = Flipboard.delete(task, in: context)
        let back = try XCTUnwrap(Flipboard.restore(deleted, in: context))
        XCTAssertEqual(back.id, id)
        XCTAssertEqual(back.title, "Gym")
        XCTAssertEqual(back.notes, "Legs, then core")
        XCTAssertEqual(back.priority, 2)
        XCTAssertEqual(back.dueDate, due)
        XCTAssertEqual(back.createdAt, created)
        XCTAssertEqual(back.recurrenceRule, RecurrenceRule(frequency: .weekly, interval: 1))
        XCTAssertEqual(back.flipTarget, 3)
        XCTAssertEqual(back.flipCount, 1)
        XCTAssertNotNil(back.flipPeriodStart)
        XCTAssertEqual(back.project?.name, "Home")
        XCTAssertEqual(back.labelList.map(\.name), ["flipboard"])
        XCTAssertEqual(back.orderedSubtasks.map(\.title), ["Shoes", "Towel"])
        XCTAssertEqual(back.orderedSubtasks.map(\.isCompleted), [true, false])
        XCTAssertEqual(try board().map(\.id), [id])
        XCTAssertFalse(context.hasChanges)
    }

    func testSpotlightDropsADeletedSwitch() async throws {
        let task = try Flipboard.createSwitch(title: "Water plants", rule: .daily, in: context)
        task.overdueBecomesTask = true  // red and opted in: indexed (brief 72)
        try context.save()
        let index = RecordingIndex()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "flipboard-delete-\(UUID().uuidString)"))
        let sync = SpotlightSync(index: index, defaults: defaults, isAllowed: true, refreshDelay: .zero)
        await sync.refresh(in: context)
        XCTAssertEqual(index.indexed, [task.id])
        let id = task.id
        _ = Flipboard.delete(task, in: context)
        let plan = await sync.refresh(in: context)
        XCTAssertEqual(plan.remove, [id])
        XCTAssertEqual(index.removed, [id])
    }
}

@MainActor
private final class RecordingIndex: SpotlightIndexing {
    var indexed: [UUID] = []
    var removed: [UUID] = []
    func index(_ entities: [TaskEntity]) async throws { indexed += entities.map(\.id) }
    func remove(_ ids: [UUID]) async throws { removed += ids }
    func removeAll() async throws {}
}

/// Brief 59: the tip says the rule in one sentence. Brief 96: the empty board says nothing but its Add a Switch tile.
final class FlipboardWordsTests: XCTestCase {
    /// Brief 72: the tip says a switch is a routine, in one sentence.
    func testTheTipSaysASwitchIsARoutine() {
        XCTAssertTrue(HITTipKind.flipboard.message.contains("A switch is a routine"), HITTipKind.flipboard.message)
        XCTAssertEqual(HITTipKind.flipboard.message.filter { $0 == "." }.count, 1, "one sentence")
    }

    /// Brief 96 (George: "New Switchboard shouldn't be a starting option"): the empty board offers a switch alone; a
    /// Switchboard is offered once there is a switch to put on one, or a board already.
    func testTheEmptyBoardOffersASwitchAlone() {
        XCTAssertFalse(FlipboardView.offersNewSwitchboard(switches: 0, boards: 0), "the empty board")
        XCTAssertTrue(FlipboardView.offersNewSwitchboard(switches: 1, boards: 0), "a switch to group")
        XCTAssertTrue(FlipboardView.offersNewSwitchboard(switches: 0, boards: 1), "a board, still empty")
    }

    /// Brief 96: the Add a Switch tile is the size of a switch, alone on an empty board as beside switches, at the
    /// iPhone's tile width and the Mac's.
    @MainActor
    func testTheAddTileIsTheSizeOfASwitch() {
        for width: CGFloat in [161, 187, 240] {
            let tile = Self.height(AddSwitchTile {}, width: width)
            let face = Self.height(FlipSwitchFace(title: "Take out the recycling", ruleText: "every week", target: 1, lamps: 0,
                                                  side: .red, isOverdue: false, fraction: 0, caption: "Flip to start",
                                                  reduceMotion: true) { RockerSwitch(tilt: -1) }, width: width)
            XCTAssertGreaterThan(face, 200, "a real switch's face at \(width) pt")
            XCTAssertEqual(tile, face, accuracy: 0.5, "the + tile at \(width) pt")
        }
    }

    @MainActor
    private static func height<V: View>(_ view: V, width: CGFloat) -> CGFloat {
        let sized = view.frame(width: width)
        #if os(macOS)
        return NSHostingView(rootView: sized).fittingSize.height
        #else
        return UIHostingController(rootView: sized).sizeThatFits(in: CGSize(width: width, height: 2000)).height
        #endif
    }

    /// Brief 72: someone whose switches came from before Switchboards (their red switches waited in Today) is told
    /// they stay on the Flipboard now, and how to bring one back; everyone else gets the Flipboard's own tip.
    func testTheTipForPeopleWhoseRedSwitchesWereInToday() {
        let before = FlipboardTips.switchesStayFrom.addingTimeInterval(-86_400)
        let after = FlipboardTips.switchesStayFrom.addingTimeInterval(3600)
        XCTAssertEqual(FlipboardTips.kind(for: [after, before]), .switchesStay)
        XCTAssertEqual(FlipboardTips.kind(for: [after]), .flipboard)
        XCTAssertNil(FlipboardTips.kind(for: []))
        XCTAssertTrue(HITTipKind.switchesStay.message.contains("Overdue becomes task"))
        XCTAssertTrue(HITTip(.switchesStay, generation: 0).waitsUntilSettled)
    }

    func testTheDebugClockReadsTheFlipboardNowArgument() {
        let utc = TimeZone(identifier: "UTC")!
        let read = FlipboardDebug.now(arguments: ["HITList", "-flipboardNow", "2026-11-11T03:30"], timeZone: utc)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        XCTAssertEqual(read, cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 3, minute: 30)))
        XCTAssertNil(FlipboardDebug.now(arguments: ["HITList"]))
        XCTAssertNil(FlipboardDebug.now(arguments: ["HITList", "-flipboardNow"]))
    }
}
