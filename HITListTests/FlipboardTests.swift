import XCTest
import SwiftData
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

    func testMembershipNeedsRepeatNoTimeOpenAndLabel() {
        let weekly = RecurrenceRule.weekly.encoded
        XCTAssertTrue(Flipboard.isMember(recurrence: weekly, hasDueTime: false, isCompleted: false, labelNames: ["flipboard"]))
        XCTAssertTrue(Flipboard.isMember(recurrence: weekly, hasDueTime: false, isCompleted: false, labelNames: ["home", "FlipBoard"]),
                      "label match ignores case")
        XCTAssertFalse(Flipboard.isMember(recurrence: weekly, hasDueTime: false, isCompleted: false, labelNames: ["home"]))
        XCTAssertFalse(Flipboard.isMember(recurrence: nil, hasDueTime: false, isCompleted: false, labelNames: ["flipboard"]))
        XCTAssertFalse(Flipboard.isMember(recurrence: "garbage", hasDueTime: false, isCompleted: false, labelNames: ["flipboard"]))
        XCTAssertFalse(Flipboard.isMember(recurrence: weekly, hasDueTime: true, isCompleted: false, labelNames: ["flipboard"]))
        XCTAssertFalse(Flipboard.isMember(recurrence: weekly, hasDueTime: false, isCompleted: true, labelNames: ["flipboard"]))
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
        XCTAssertNil(FlipInterval(.monthly))
        XCTAssertNil(FlipInterval(.weekdays))
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
        XCTAssertFalse(task.hasDueTime)
        XCTAssertEqual(task.dueDate, daysFromToday(2), "time of day dropped")
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
